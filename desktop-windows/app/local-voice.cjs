// Open-source voice on this PC (0.9.3): Whisper for listening and Kokoro-82M for speaking, run by
// renderer/local-voice-engine.js in a hidden window. Models download once from Hugging Face into the app's
// data folder (only the repositories listed here), and the WebAssembly runtime is a pinned file checked by SHA-256.
const path = require('node:path');
const fsp = require('node:fs/promises');
const crypto = require('node:crypto');

const TTS_REPO = 'onnx-community/Kokoro-82M-v1.0-ONNX';
const STT_REPOS = ['onnx-community/whisper-tiny.en', 'onnx-community/whisper-tiny', 'onnx-community/whisper-base.en', 'onnx-community/whisper-base', 'onnx-community/whisper-small.en', 'onnx-community/whisper-small'];
const RUNTIME_BASE = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.7.6/dist/';
const RUNTIME = {
  'ort-wasm-simd-threaded.jsep.mjs': '08fb86ec433c78bfb032c5d84a68b8e8e5a8d81268fa39e24314179a5767a5b9',
  'ort-wasm-simd-threaded.jsep.wasm': 'c46655e8a94afc45338d4cb2b840475f88e5012d524509916e505079c00bfa39'
};
/** Kokoro voices offered in settings (all ship with the model). */
const KOKORO_VOICES = [['af_heart', 'Heart (US, warm)'], ['af_bella', 'Bella (US)'], ['af_nicole', 'Nicole (US, soft)'], ['af_sarah', 'Sarah (US)'], ['am_michael', 'Michael (US)'], ['am_fenrir', 'Fenrir (US)'], ['am_puck', 'Puck (US)'], ['bf_emma', 'Emma (UK)'], ['bm_george', 'George (UK)'], ['bm_fable', 'Fable (UK)']];
const SIZES = { 'tts:q8': 92, 'tts:fp16': 163, 'tts:fp32': 326, 'stt:tiny': 45, 'stt:base': 80, 'stt:small': 250, runtime: 22 };

/**
 * Picks models for this machine. `memoryGB` and `cores` come from the OS; `webgpu` from the engine window.
 * Kokoro-82M is the speaking model everywhere (best quality for its speed); only its precision changes.
 */
function recommend({ memoryGB = 8, cores = 4, webgpu = false, language = 'en' } = {}) {
  // 0.9.4: the processor with the small (q8) models is the default everywhere: quick, and it works on every PC.
  // The graphics chip is used only after "Use the graphics chip if it's faster" measures it. Whisper small was too slow.
  const english = String(language || 'en').toLowerCase().startsWith('en');
  const decent = memoryGB >= 8 && cores >= 4;
  const size = decent ? 'base' : 'tiny';
  const tts = { dtype: 'q8', device: 'wasm' };
  const stt = { model: `onnx-community/whisper-${size}${english ? '.en' : ''}`, device: 'wasm' };
  const tier = decent ? (webgpu && memoryGB >= 16 ? 'fast' : 'balanced') : 'light';
  const why = decent ? 'Your PC runs Kokoro and Whisper base comfortably on the processor: natural speech and accurate listening without slowing other apps. Use “Test speed” to see how fast, and try the graphics chip if you have one.'
    : 'Your PC gets the light models, which stay quick on modest hardware. You can pick larger ones below.';
  const downloadMB = SIZES[`tts:${tts.dtype}`] + SIZES[`stt:${size}`] + SIZES.runtime;
  return { tier, tts, stt, why, downloadMB, speaker: `Kokoro-82M (${tts.dtype}, ${tts.device === 'webgpu' ? 'graphics chip' : 'processor'})`, listener: `Whisper ${size}${english ? ' (English)' : ''}` };
}

/** Maps an ogb-models:// path to a download URL, or null when it is not an approved file. */
function source(pathname) {
  const clean = decodeURIComponent(String(pathname || '')).replace(/^\/+/, '');
  if (clean.includes('..') || clean.includes('\\')) return null;
  if (clean.startsWith('ort/')) { const name = clean.slice(4); return Object.hasOwn(RUNTIME, name) ? { url: RUNTIME_BASE + name, sha256: RUNTIME[name], cache: path.join('runtime', name) } : null; }
  if (!clean.startsWith('hf/')) return null;
  const rest = clean.slice(3), repo = [TTS_REPO, ...STT_REPOS].find(r => rest.startsWith(r + '/resolve/'));
  if (!repo) return null;
  const file = rest.slice(repo.length + '/resolve/'.length);
  if (!/^[A-Za-z0-9._-]+\/[A-Za-z0-9._\/-]+$/.test(file)) return null;
  return { url: 'https://huggingface.co/' + rest, sha256: null, cache: path.join('hf', ...rest.split('/')) };
}

const contentType = name => name.endsWith('.mjs') || name.endsWith('.js') ? 'text/javascript' : name.endsWith('.wasm') ? 'application/wasm' : name.endsWith('.json') ? 'application/json' : 'application/octet-stream';

/** Serves approved model and runtime files from the cache, downloading each once. */
function createStore({ root, fetchImpl = fetch }) {
  const inflight = new Map();
  async function file(pathname) {
    const entry = source(pathname); if (!entry) return { status: 404 };
    const target = path.join(root, entry.cache);
    try { return { status: 200, body: await fsp.readFile(target), type: contentType(target) }; } catch {}
    if (!inflight.has(target)) inflight.set(target, (async () => {
      const response = await fetchImpl(entry.url, { redirect: 'follow' });
      if (response.status === 404) return { status: 404 };
      if (!response.ok) throw new Error('Download failed (HTTP ' + response.status + ').');
      const body = Buffer.from(await response.arrayBuffer());
      if (entry.sha256 && crypto.createHash('sha256').update(body).digest('hex') !== entry.sha256) throw new Error('The voice runtime download did not match its checksum.');
      await fsp.mkdir(path.dirname(target), { recursive: true });
      const temporary = target + '.' + crypto.randomUUID() + '.tmp';
      await fsp.writeFile(temporary, body); await fsp.rename(temporary, target);
      return { status: 200, body, type: contentType(target) };
    })().finally(() => inflight.delete(target)));
    return inflight.get(target);
  }
  async function installed() {
    const has = async relative => { try { await fsp.access(path.join(root, relative)); return true; } catch { return false; } };
    const sizes = {};
    for (const repo of [TTS_REPO, ...STT_REPOS]) if (await has(path.join('hf', ...repo.split('/')))) sizes[repo] = true;
    return { runtime: await has(path.join('runtime', 'ort-wasm-simd-threaded.jsep.wasm')), models: Object.keys(sizes) };
  }
  async function remove() { await fsp.rm(root, { recursive: true, force: true }); }
  return { file, installed, remove };
}

module.exports = { recommend, source, createStore, contentType, KOKORO_VOICES, TTS_REPO, STT_REPOS, RUNTIME };
