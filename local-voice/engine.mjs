// OpenGrokBot local voice engine (0.9.3).
// Runs open-source models on this computer: Kokoro-82M for speaking and Whisper for listening.
// Built into local-voice-engine.js by scripts/build-local-voice.cjs. Loaded by a hidden window (Windows)
// or a hidden web view (Mac). Every model and runtime file is fetched through the app's own ogb-models:
// scheme, which downloads it once from Hugging Face (models) or a pinned, hash-checked copy (runtime), then serves it offline.
import './polyfills.mjs';
import { KokoroTTS } from 'kokoro-js';
import { pipeline, env } from '@huggingface/transformers';

// The apps serve models through ogb-models:; scripts/diagnose-local-voice.mjs points this at a local test server instead.
const BASE = globalThis.OGB_MODELS_BASE || 'ogb-models://local/';
env.allowLocalModels = false;
env.allowRemoteModels = true;
env.remoteHost = BASE + 'hf/';
env.remotePathTemplate = '{model}/resolve/{revision}/';
env.useBrowserCache = false;
env.backends.onnx.wasm.wasmPaths = BASE + 'ort/';
env.backends.onnx.wasm.numThreads = globalThis.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 2) : 1;

// kokoro-js fetches voice files from huggingface.co directly; send those through the app's scheme too.
// Files that could not be fetched, so a failed load can say which file was missing instead of a vague error.
const failedFiles = new Set();
const directFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = async (input, init) => {
  let url = typeof input === 'string' ? input : input?.url;
  if (typeof url === 'string' && url.startsWith('https://huggingface.co/')) { url = BASE + 'hf/' + url.slice('https://huggingface.co/'.length); input = url; }
  const response = await directFetch(input, init);
  if (!response.ok && typeof url === 'string' && url.startsWith(BASE)) failedFiles.add(url.slice(BASE.length).replace(/^hf\//, '').replace(/\/resolve\/main\//, '/'));
  return response;
};
function explain(error) {
  const message = String(error?.message || error);
  const missing = [...failedFiles].filter(file => /\.(onnx|bin|json)$/.test(file));
  failedFiles.clear();
  if (missing.length && /Unsupported model type|Could not locate file|404|Failed to fetch/i.test(message)) return new Error(`Missing model file${missing.length === 1 ? '' : 's'}: ${missing.slice(0, 3).join(', ')}. Download the voice models again in Settings → Voice.`);
  return error instanceof Error ? error : new Error(message);
}

const TTS_MODEL = 'onnx-community/Kokoro-82M-v1.0-ONNX';
const state = { tts: null, ttsKey: '', stt: null, sttKey: '', progress: {} };

function report(kind, info) {
  if (info?.status === 'progress' && info.file) state.progress[kind + ':' + info.file] = { loaded: info.loaded || 0, total: info.total || 0 };
  const parts = Object.entries(state.progress).filter(([key]) => key.startsWith(kind + ':')).map(([, value]) => value);
  const total = parts.reduce((sum, x) => sum + x.total, 0), loaded = parts.reduce((sum, x) => sum + x.loaded, 0);
  globalThis.ogbVoiceProgress?.({ kind, loaded, total });
}

async function hasWebGPU() {
  try { return !!(navigator.gpu && await navigator.gpu.requestAdapter()); } catch { return false; }
}

/** Describes what this computer can run, for the model recommendation. */
async function capabilities() {
  return { webgpu: await hasWebGPU(), cores: navigator.hardwareConcurrency || 2, memoryGB: navigator.deviceMemory || 0, isolated: !!globalThis.crossOriginIsolated };
}

/** Loads Kokoro. A graphics-chip load that fails falls back to the processor (small q8 model), which works everywhere. */
async function loadTTS({ dtype = 'q8', device = 'wasm' } = {}) {
  const key = dtype + '|' + device;
  if (state.tts && state.ttsKey === key) return { dtype, device };
  state.tts = null; failedFiles.clear();
  try {
    state.tts = await KokoroTTS.from_pretrained(TTS_MODEL, { dtype, device, progress_callback: info => report('tts', info) });
    state.ttsKey = key;
    return { dtype, device };
  } catch (error) {
    if (device === 'wasm') throw explain(error);
    state.tts = await KokoroTTS.from_pretrained(TTS_MODEL, { dtype: 'q8', device: 'wasm', progress_callback: info => report('tts', info) }).catch(next => { throw explain(next); });
    state.ttsKey = key; // Asked-for key, so the next call does not retry the failing device.
    return { dtype: 'q8', device: 'wasm', fellBack: String(error?.message || error).slice(0, 200) };
  }
}

/** Loads Whisper. Same fallback as speaking. */
async function loadSTT({ model = 'onnx-community/whisper-base.en', device = 'wasm', dtype } = {}) {
  const key = model + '|' + device + '|' + (dtype || '');
  if (state.stt && state.sttKey === key) return { model, device };
  state.stt = null; failedFiles.clear();
  const make = (useDevice, useDtype) => pipeline('automatic-speech-recognition', model, {
    device: useDevice, progress_callback: info => report('stt', info),
    dtype: useDtype || (useDevice === 'webgpu' ? { encoder_model: 'fp32', decoder_model_merged: 'q4' } : 'q8')
  });
  try {
    state.stt = await make(device, dtype);
    state.sttKey = key;
    return { model, device };
  } catch (error) {
    if (device === 'wasm') throw explain(error);
    state.stt = await make('wasm', 'q8').catch(next => { throw explain(next); });
    state.sttKey = key;
    return { model, device: 'wasm', fellBack: String(error?.message || error).slice(0, 200) };
  }
}

/**
 * Times the loaded models on this computer: Kokoro speaks a sentence, then Whisper listens to that audio.
 * Returns real-time factors (below 1 = faster than real time) and the words Whisper heard.
 */
async function benchmark() {
  const result = { threads: env.backends.onnx.wasm.numThreads, isolated: !!globalThis.crossOriginIsolated };
  const sentence = 'The cheapest cruise leaves on Friday morning from Galveston.';
  if (state.tts) {
    const started = performance.now();
    const audio = await state.tts.generate(sentence, { voice: 'af_heart', speed: 1 });
    const seconds = audio.audio.length / audio.sampling_rate;
    result.tts = { ms: Math.round(performance.now() - started), seconds: +seconds.toFixed(2), realTimeFactor: +((performance.now() - started) / 1000 / seconds).toFixed(2) };
    if (state.stt) {
      // Resample 24 kHz speech to 16 kHz for Whisper.
      const ratio = audio.sampling_rate / 16000, samples = new Float32Array(Math.floor(audio.audio.length / ratio));
      for (let i = 0; i < samples.length; i++) samples[i] = audio.audio[Math.floor(i * ratio)];
      const begin = performance.now();
      const heard = await transcribe(samples);
      result.stt = { ms: Math.round(performance.now() - begin), seconds: +seconds.toFixed(2), realTimeFactor: +((performance.now() - begin) / 1000 / seconds).toFixed(2), heard };
    }
  }
  return result;
}

function wav(samples, rate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2), view = new DataView(buffer);
  const text = (offset, value) => { for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i)); };
  text(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); text(8, 'WAVE'); text(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); text(36, 'data'); view.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) { const s = Math.max(-1, Math.min(1, samples[i])); view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true); }
  return new Uint8Array(buffer);
}

function base64(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 0x8000) out += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(out);
}

/**
 * Speaks `text` with a Kokoro voice. Returns a 24 kHz mono WAV, as bytes or base64.
 * Requests run one after another: the apps ask for the next sentence while the current one plays, and one model
 * session must not run two generations at once.
 */
let speaking = Promise.resolve();
function speak(text, options = {}) {
  const run = speaking.then(() => speakNow(text, options));
  speaking = run.catch(() => {});
  return run;
}
async function speakNow(text, { voice = 'af_heart', speed = 1, encoding = 'bytes' } = {}) {
  if (!state.tts) throw new Error('The local voice is not loaded yet.');
  const audio = await state.tts.generate(String(text).slice(0, 1000), { voice, speed });
  const bytes = wav(audio.audio, audio.sampling_rate);
  return encoding === 'base64' ? base64(bytes) : bytes;
}

/** Turns 16 kHz mono samples (Float32Array, or base64 of little-endian float32) into text. */
async function transcribe(input, { language = 'en' } = {}) {
  if (!state.stt) throw new Error('Local listening is not loaded yet.');
  let samples = input;
  if (typeof input === 'string') { const raw = atob(input), bytes = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i); samples = new Float32Array(bytes.buffer); }
  const multilingual = !/\.en$/.test(state.sttKey.split('|')[0]);
  const result = await state.stt(samples, multilingual ? { language, task: 'transcribe' } : {});
  return String(result?.text || '').trim();
}

function voices() { return state.tts ? Object.keys(state.tts.voices || {}) : []; }

globalThis.OGBLocalVoice = { capabilities, loadTTS, loadSTT, speak, transcribe, voices, benchmark, version: '0.9.4' };
