// OpenGrokBot local voice engine (0.9.3).
// Runs open-source models on this computer: Kokoro-82M for speaking and Whisper for listening.
// Built into local-voice-engine.js by scripts/build-local-voice.cjs. Loaded by a hidden window (Windows)
// or a hidden web view (Mac). Every model and runtime file is fetched through the app's own ogb-models:
// scheme, which downloads it once from Hugging Face (models) or a pinned, hash-checked copy (runtime), then serves it offline.
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
const directFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = (input, init) => {
  const url = typeof input === 'string' ? input : input?.url;
  if (typeof url === 'string' && url.startsWith('https://huggingface.co/')) return directFetch(BASE + 'hf/' + url.slice('https://huggingface.co/'.length), init);
  return directFetch(input, init);
};

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

async function loadTTS({ dtype = 'q8', device = 'wasm' } = {}) {
  const key = dtype + '|' + device;
  if (state.tts && state.ttsKey === key) return true;
  state.tts = null;
  state.tts = await KokoroTTS.from_pretrained(TTS_MODEL, { dtype, device, progress_callback: info => report('tts', info) });
  state.ttsKey = key;
  return true;
}

async function loadSTT({ model = 'onnx-community/whisper-base', device = 'wasm', dtype } = {}) {
  const key = model + '|' + device + '|' + (dtype || '');
  if (state.stt && state.sttKey === key) return true;
  state.stt = null;
  const options = { device, progress_callback: info => report('stt', info) };
  if (dtype) options.dtype = dtype;
  else options.dtype = device === 'webgpu' ? { encoder_model: 'fp32', decoder_model_merged: 'q4' } : 'q8';
  state.stt = await pipeline('automatic-speech-recognition', model, options);
  state.sttKey = key;
  return true;
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

/** Speaks `text` with a Kokoro voice. Returns a 24 kHz mono WAV, as bytes or base64. */
async function speak(text, { voice = 'af_heart', speed = 1, encoding = 'bytes' } = {}) {
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

globalThis.OGBLocalVoice = { capabilities, loadTTS, loadSTT, speak, transcribe, voices, version: '0.9.3' };
