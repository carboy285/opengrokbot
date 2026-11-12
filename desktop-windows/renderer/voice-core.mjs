// Pure helpers for voice mode (no DOM), so they can be unit-tested in Node.

export function speakable(raw) {
  return String(raw ?? '')
    .replace(/```[\s\S]*?(```|$)/g, ' (code omitted) ')
    .replace(/https?:\/\/\S+/g, ' link ')
    .replace(/[`*_#>|~]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 4000);
}

/**
 * Splits a reply that is still streaming into speakable pieces: text from `offset` up to the last finished
 * sentence (or everything once `final`), never cutting inside a ``` code block. Mirrors VoiceText.nextChunk in Swift.
 */
export function nextChunk(text, offset, final, eager = false) {
  const chars = Array.from(String(text ?? ''));
  if (offset >= chars.length) return { chunk: '', next: Math.max(offset, chars.length) };
  if (final) return { chunk: chars.slice(offset).join(''), next: chars.length };
  let end = offset;
  for (let i = chars.length - 2; i >= offset; i--) {
    if ('.!?\n'.includes(chars[i]) && /\s/.test(chars[i + 1])) { end = i + 1; break; }
  }
  if (end === offset && eager) {
    // Nothing has been spoken yet: start at the first natural pause instead of waiting for a whole sentence.
    for (let j = offset + 14; j < chars.length - 1; j++) {
      if (',;:—'.includes(chars[j]) && /\s/.test(chars[j + 1])) { end = j + 1; break; }
    }
    // No pause yet but a good run of words: start at the last complete word instead of waiting.
    if (end === offset && chars.length - offset >= 48) {
      const space = chars.lastIndexOf(' ', chars.length - 2);
      if (space - offset >= 30) end = space + 1;
    }
  }
  if (end <= offset) return { chunk: '', next: offset };
  const candidate = chars.slice(0, end).join('');
  if ((candidate.split('```').length - 1) % 2 === 1) {
    end = Array.from(candidate.slice(0, candidate.lastIndexOf('```'))).length;
    if (end <= offset) return { chunk: '', next: offset };
  }
  return { chunk: chars.slice(offset, end).join(''), next: end };
}

/** Longest text one speech request should carry for a provider; longer replies are split at natural pauses. */
export function maxSpeechLength(provider) { return provider === 'groq' ? 190 : provider === 'nvidiaNIM' || provider === 'nvidiaCloud' ? 400 : Infinity; }

/** Splits text into pieces of at most `max` characters, preferring sentence ends, then commas, then spaces. Mirrors VoiceText.split in Swift. */
export function splitText(text, max) {
  const clean = String(text ?? '').trim();
  if (!clean) return [];
  if (!(max > 0) || clean.length <= max) return [clean];
  const parts = []; let rest = clean;
  while (rest.length > max) {
    const window = rest.slice(0, max);
    const cut = (marks, minimum) => { let at = -1; for (const mark of marks) at = Math.max(at, window.lastIndexOf(mark)); return at >= 0 && at + 1 >= minimum ? at + 1 : -1; };
    let end = cut('.!?', Math.floor(max / 3));
    if (end < 0) end = cut(',;:', Math.floor(max / 3));
    if (end < 0) end = cut(' ', 1);
    if (end < 0) end = max;
    const piece = rest.slice(0, end).trim();
    if (piece) parts.push(piece);
    rest = rest.slice(end).trimStart();
  }
  if (rest) parts.push(rest);
  return parts;
}

/** 16-bit mono PCM WAV at 16 kHz, accepted by every transcription provider. */
export function encodeWav(samples, sampleRate) {
  const target = 16000, ratio = Math.max(1, sampleRate / target);
  const count = Math.floor(samples.length / ratio);
  const bytes = new Uint8Array(44 + count * 2), view = new DataView(bytes.buffer);
  const text = (offset, value) => { for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i)); };
  text(0, 'RIFF'); view.setUint32(4, 36 + count * 2, true); text(8, 'WAVEfmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, target, true); view.setUint32(28, target * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  text(36, 'data'); view.setUint32(40, count * 2, true);
  for (let i = 0; i < count; i++) {
    const start = Math.floor(i * ratio), end = Math.min(samples.length, Math.max(start + 1, Math.floor((i + 1) * ratio)));
    let sum = 0; for (let j = start; j < end; j++) sum += samples[j];
    const value = Math.max(-1, Math.min(1, sum / (end - start)));
    view.setInt16(44 + i * 2, Math.round(value * 32767), true);
  }
  return bytes;
}

export function rms(samples) {
  if (!samples.length) return 0;
  let sum = 0; for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
  return Math.sqrt(sum / samples.length);
}

/** Voice-activity detector. Time is measured in samples, so it behaves the same at any sample rate. */
export class Vad {
  constructor({ sampleRate, speechThreshold = 0.012, bargeThreshold = 0.08, silenceMs = 500, bargeMs = 400, maxSeconds = 60 }) {
    Object.assign(this, { sampleRate, speechThreshold, bargeThreshold, silenceMs, bargeMs, maxSeconds });
    this.reset();
  }
  reset() { this.inSpeech = false; this.preRoll = []; this.preRollLength = 0; this.utterance = []; this.utteranceLength = 0; this.silent = 0; this.barge = 0; this.voiced = 0; }
  get speaking() { return this.inSpeech; }
  roll(chunk) {
    this.preRoll.push(chunk); this.preRollLength += chunk.length;
    const max = Math.floor(this.sampleRate * 0.4);
    while (this.preRollLength > max && this.preRoll.length > 1) this.preRollLength -= this.preRoll.shift().length;
  }
  begin(chunk) {
    this.inSpeech = true; this.utterance = [...this.preRoll, chunk];
    this.utteranceLength = this.utterance.reduce((n, c) => n + c.length, 0);
    this.preRoll = []; this.preRollLength = 0; this.silent = 0; this.barge = 0; this.voiced = chunk.length;
  }
  finish() {
    const out = new Float32Array(this.utteranceLength); let offset = 0;
    for (const chunk of this.utterance) { out.set(chunk, offset); offset += chunk.length; }
    const long = this.voiced / this.sampleRate >= 0.3;
    this.reset();
    return long ? { type: 'utterance', samples: out } : null;
  }
  /** mode is 'listening' or 'speaking' (the Bot is talking). Returns null, {type:'barge'} or {type:'utterance',samples}. */
  push(chunk, mode) {
    const level = rms(chunk);
    if (mode === 'speaking') {
      if (level > this.bargeThreshold) {
        this.barge += chunk.length;
        if ((this.barge / this.sampleRate) * 1000 >= this.bargeMs) { this.roll(chunk); this.begin(new Float32Array(0)); this.voiced = this.barge || chunk.length * 4; return { type: 'barge' }; }
        this.roll(chunk);
      } else { this.barge = 0; this.roll(chunk); }
      return null;
    }
    if (level > this.speechThreshold) {
      if (!this.inSpeech) this.begin(chunk); else { this.utterance.push(chunk); this.utteranceLength += chunk.length; this.voiced += chunk.length; }
      this.silent = 0;
      if (this.utteranceLength > this.sampleRate * this.maxSeconds) return this.finish();
      return null;
    }
    if (this.inSpeech) {
      this.utterance.push(chunk); this.utteranceLength += chunk.length; this.silent += chunk.length;
      if ((this.silent / this.sampleRate) * 1000 >= this.silenceMs) return this.finish();
      return null;
    }
    this.roll(chunk);
    return null;
  }
}

// ---- 0.9.3: turn-taking that waits for you, and something to hear while a Bot works. Mirrors VoiceTurns in Swift. ----

/** Milliseconds of quiet before what you said is sent, by the patience setting. */
export function silenceFor(patience) { return patience === 'quick' ? 550 : patience === 'relaxed' ? 1300 : 800; }

const TRAILING = new Set(['and', 'or', 'but', 'so', 'because', 'cause', 'um', 'uh', 'er', 'like', 'the', 'a', 'an', 'to', 'of', 'for', 'with', 'my', 'your', 'if', 'then', 'that', 'which', 'when', 'about', 'also', 'actually', 'is', 'are', 'was', 'i', "i'm", 'we', 'and,', 'in', 'on', 'at', 'just', 'maybe', 'could', 'can', 'should', 'would', 'what', 'how', 'where']);

/** True when what you said so far sounds unfinished (a trailing "and", "um", a comma), so the app keeps listening a little longer. */
export function continuesThought(text) {
  const clean = String(text ?? '').trim().toLowerCase();
  if (!clean) return false;
  if (/[,;:\-–—]$/.test(clean) || clean.endsWith('...') || clean.endsWith('…')) return true;
  if (/[.?!]$/.test(clean)) return false;
  const last = clean.split(/\s+/).pop().replace(/[^a-z']/g, '');
  return TRAILING.has(last);
}

/** Resamples microphone audio to 16 kHz mono for Whisper. */
export function resample16k(samples, sampleRate) {
  const ratio = Math.max(1, sampleRate / 16000), count = Math.floor(samples.length / ratio), out = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const start = Math.floor(i * ratio), end = Math.min(samples.length, Math.max(start + 1, Math.floor((i + 1) * ratio)));
    let sum = 0; for (let j = start; j < end; j++) sum += samples[j];
    out[i] = sum / (end - start);
  }
  return out;
}

const ACKS = ['Mm-hm, one sec.', 'Okay, give me a moment.', 'Sure, let me check.', 'Got it. One moment.', 'Okay, thinking.'];
/** A short spoken acknowledgement while the Bot is still starting its answer. */
export function acknowledgement(seed = Math.random()) { return ACKS[Math.floor(Math.abs(seed) * ACKS.length) % ACKS.length]; }

/** What to say out loud for a tool step, or '' to stay quiet. Takes the step's chat text. */
export function stepPhrase(text) {
  const first = String(text ?? '').split('\n').find(line => line.trim()) || '';
  const lower = first.toLowerCase();
  if (!first || /couldn|could not|failed|declined|not sent|stopped/.test(lower)) return '';
  if (lower.startsWith('linux vm result')) return 'Running that on the computer.';
  const asked = /^queued message · (.+)$/i.exec(first.trim());
  if (asked) return `Asking ${asked[1]}.`;
  if (lower.startsWith('read ')) return 'Reading a page.';
  if (lower.includes('search')) return 'Searching the web.';
  if (lower.includes('calendar') || lower.includes('event')) return 'Checking your calendar.';
  if (lower.includes('mail') || lower.includes('email')) return 'Looking at your email.';
  return '';
}
