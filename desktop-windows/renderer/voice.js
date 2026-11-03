import { Vad, encodeWav, rms, speakable } from './voice-core.mjs';

// Hands-free voice mode for Windows.
// Listening needs a cloud key (Groq has a free tier) because Electron has no built-in speech recognition.
// Speaking uses the free Windows voices unless you pick OpenAI or ElevenLabs in Settings → Voice.

const el = (tag, className = '', text = '') => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };
const toBase64 = bytes => { let binary = ''; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(binary); };

export function createVoice({ bridge, result, toast, currentBot, latestReply, sendText, openSettings }) {
  let session = null;

  async function start() {
    if (session) return;
    const bot = currentBot();
    if (!bot) return;
    const settings = await result(bridge.voiceSettings());
    if (!settings.keys[settings.transcriber]) {
      toast('Voice needs a listening key. Add a free Groq key in Settings → Voice.');
      openSettings?.(); return;
    }
    let stream;
    try { stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }); }
    catch { toast('The microphone is blocked. Allow microphone access in Windows privacy settings.'); return; }

    const overlay = el('div', 'voice-overlay'); overlay.setAttribute('role', 'dialog'); overlay.setAttribute('aria-label', 'Voice mode');
    const orb = el('div', 'voice-orb'), status = el('div', 'voice-status', 'Listening…'), caption = el('div', 'voice-caption'), note = el('div', 'voice-note');
    const end = el('button', 'voice-end', 'End voice mode'); end.type = 'button';
    const gear = el('button', 'voice-gear', '⚙'); gear.type = 'button'; gear.setAttribute('aria-label', 'Voice settings');
    overlay.append(gear, el('strong', 'voice-title', bot.name), orb, status, caption, note, end);
    document.body.append(overlay); end.focus();

    const audio = new AudioContext();
    const source = audio.createMediaStreamSource(stream);
    const processor = audio.createScriptProcessor(2048, 1, 1);
    const vad = new Vad({ sampleRate: audio.sampleRate });
    const state = { mode: 'listening', alive: true, cancelSpeech: null };
    session = { stop };

    const set = (mode, text) => { state.mode = mode; status.textContent = text; overlay.dataset.mode = mode; };
    set('listening', 'Listening…');

    processor.onaudioprocess = event => {
      if (!state.alive || state.mode === 'thinking') return;
      const chunk = new Float32Array(event.inputBuffer.getChannelData(0));
      orb.style.transform = `scale(${1 + Math.min(1, rms(chunk) * 8) * 0.25})`;
      const heard = vad.push(chunk, state.mode === 'speaking' ? 'speaking' : 'listening');
      if (!heard) return;
      if (heard.type === 'barge') { if (settings.talkOver) { state.cancelSpeech?.(); set('listening', 'Listening…'); } else vad.reset(); return; }
      handleUtterance(heard.samples);
    };
    source.connect(processor); processor.connect(audio.destination);

    async function handleUtterance(samples) {
      set('thinking', 'Transcribing…');
      try {
        const wav = toBase64(encodeWav(samples, audio.sampleRate));
        const text = await result(bridge.voiceTranscribe(wav));
        if (!state.alive) return;
        if (!text) { resume(); return; }
        caption.textContent = text; set('thinking', 'Thinking…');
        const before = latestReply(bot)?.id;
        await sendText(bot, text);
        for (let waited = 0; state.alive && waited < 180000; waited += 300) {
          await new Promise(done => setTimeout(done, 300));
          const reply = latestReply(bot);
          if (reply && reply.id !== before && reply.finished) { await speak(reply.text); return; }
        }
        resume();
      } catch (error) { note.textContent = error.message; resume(); }
    }

    function resume() { if (!state.alive) return; vad.reset(); set('listening', 'Listening…'); }

    async function speak(raw) {
      const text = speakable(raw);
      if (!text || !state.alive) { resume(); return; }
      vad.reset(); set('speaking', 'Speaking · click the orb to interrupt'); caption.textContent = '';
      try {
        if (settings.speaker === 'system' || !settings.keys[settings.speaker]) await speakSystem(text);
        else {
          let bytes;
          try { bytes = Uint8Array.from(atob(await result(bridge.voiceSpeak(text))), c => c.charCodeAt(0)); }
          catch (error) { note.textContent = `${error.message} Using the Windows voice instead.`; await speakSystem(text); resume(); return; }
          await playAudio(bytes);
        }
      } finally { if (state.mode === 'speaking') resume(); }
    }

    function speakSystem(text) {
      return new Promise(done => {
        const synth = window.speechSynthesis, voices = synth.getVoices();
        const language = (navigator.language || 'en-US').slice(0, 2);
        const voice = voices.find(v => v.lang.startsWith(language) && /natural|online/i.test(v.name)) || voices.find(v => v.lang.startsWith(language));
        const parts = text.match(/[^.!?]+[.!?]*\s*/g) || [text];
        let finished = false; const finish = () => { if (!finished) { finished = true; state.cancelSpeech = null; done(); } };
        state.cancelSpeech = () => { synth.cancel(); finish(); };
        parts.forEach((part, index) => {
          const utterance = new SpeechSynthesisUtterance(part.trim()); if (voice) utterance.voice = voice;
          if (index === parts.length - 1) { utterance.onend = finish; utterance.onerror = finish; }
          synth.speak(utterance);
        });
      });
    }

    function playAudio(bytes) {
      return new Promise(done => {
        const url = URL.createObjectURL(new Blob([bytes], { type: 'audio/mpeg' }));
        const player = new Audio(url);
        const finish = () => { URL.revokeObjectURL(url); state.cancelSpeech = null; done(); };
        state.cancelSpeech = () => { player.pause(); finish(); };
        player.onended = finish; player.onerror = finish;
        player.play().catch(finish);
      });
    }

    orb.addEventListener('click', () => { if (state.mode === 'speaking') { state.cancelSpeech?.(); resume(); } });
    end.addEventListener('click', stop);
    gear.addEventListener('click', () => { stop(); openSettings?.(); });
    overlay.addEventListener('keydown', event => { if (event.key === 'Escape') stop(); });

    function stop() {
      if (!session) return;
      session = null; state.alive = false; state.cancelSpeech?.();
      window.speechSynthesis.cancel();
      processor.disconnect(); source.disconnect(); stream.getTracks().forEach(track => track.stop()); audio.close().catch(() => {});
      overlay.remove();
    }
  }

  function stop() { session?.stop(); }

  async function renderSettings(page) {
    const settings = await result(bridge.voiceSettings());
    const form = el('div', 'voice-settings');
    const row = (label, control) => { const wrap = el('label', 'voice-row'); wrap.append(el('span', '', label), control); return wrap; };
    const select = (options, value, change) => {
      const control = el('select'); for (const [id, title] of options) { const option = el('option', '', title); option.value = id; control.append(option); }
      control.value = value; control.addEventListener('change', () => change(control.value)); return control;
    };
    const save = patch => result(bridge.voiceSave(patch)).catch(error => toast(error.message));
    form.append(
      el('p', 'muted', 'Listening needs a cloud key because Windows has no offline recognizer here; Groq has a free tier. Speaking is free using Windows voices. Audio and reply text go only to the provider you choose. Keys are encrypted on this PC.'),
      row('Listening', select([['groq', 'Groq (Whisper)'], ['openAI', 'OpenAI (Whisper)'], ['elevenLabs', 'ElevenLabs (Scribe)']], settings.transcriber, value => save({ transcriber: value }))),
      row('Speaking', select([['system', 'Windows voice (free)'], ['openAI', 'OpenAI'], ['elevenLabs', 'ElevenLabs']], settings.speaker, value => save({ speaker: value }))),
    );
    const talk = el('input'); talk.type = 'checkbox'; talk.checked = settings.talkOver; talk.addEventListener('change', () => save({ talkOver: talk.checked }));
    form.append(row('Allow talking over replies', talk));
    for (const [id, title] of [['groq', 'Groq'], ['openAI', 'OpenAI'], ['elevenLabs', 'ElevenLabs']]) {
      const input = el('input'); input.type = 'password'; input.autocomplete = 'off'; input.placeholder = settings.keys[id] ? 'Saved — paste a new key to replace' : 'Paste API key';
      const keep = el('button', '', 'Save key'); keep.type = 'button';
      keep.addEventListener('click', async () => { try { await result(bridge.voiceKey(id, input.value.trim())); input.value = ''; input.placeholder = 'Saved — paste a new key to replace'; toast(`${title} key saved.`); } catch (error) { toast(error.message); } });
      const clear = el('button', '', 'Remove'); clear.type = 'button';
      clear.addEventListener('click', async () => { try { await result(bridge.voiceKey(id, '')); input.placeholder = 'Paste API key'; toast(`${title} key removed.`); } catch (error) { toast(error.message); } });
      const line = el('div', 'voice-key'); line.append(input, keep, clear); form.append(row(`${title} key`, line));
    }
    const voiceID = el('input'); voiceID.value = settings.voiceID; voiceID.addEventListener('change', () => save({ voiceID: voiceID.value.trim() }));
    form.append(row('ElevenLabs voice ID', voiceID));
    page.append(form);
  }

  return { start, stop, renderSettings, get active() { return !!session; } };
}
