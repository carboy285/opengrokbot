#!/usr/bin/env node
// Diagnoses OpenGrokBot's open-source voice (Kokoro speaking, Whisper listening) on a real computer.
// It runs the exact engine the apps ship (desktop-windows/renderer/local-voice-engine.js) in Chromium and in WebKit
// (WebKit is what the Mac app's hidden web view uses), against the models the app already downloaded.
// It never changes the app's files. It writes a report (JSON + Markdown) and the spoken samples to --out.
//
// Usage (from the repository root):
//   npm install --no-save playwright@1.56.1 && npx playwright install chromium webkit
//   node scripts/diagnose-local-voice.mjs [--cache <dir>] [--out <dir>] [--browsers chromium,webkit]
//        [--tts q8,fp32] [--stt onnx-community/whisper-base.en,...] [--download] [--timeout 600]
//
// --cache    The app's model folder. Default: Mac ~/Library/Application Support/OpenGrokBot/LocalVoice,
//            Windows %APPDATA%/OpenGrokBot/local-voice.
// --download Fetch files the cache does not have (from Hugging Face / the pinned runtime) into --out/download-cache,
//            never into the app's folder. Without it, missing files are reported.
import http from 'node:http';
import fs from 'node:fs/promises';
import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).reduce((list, value, index, all) => {
  if (value.startsWith('--')) list.push([value.slice(2), all[index + 1] && !all[index + 1].startsWith('--') ? all[index + 1] : true]);
  return list;
}, []));
const defaultCache = process.platform === 'win32'
  ? path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'OpenGrokBot', 'local-voice')
  : path.join(os.homedir(), 'Library', 'Application Support', 'OpenGrokBot', 'LocalVoice');
const cache = path.resolve(args.cache || defaultCache);
const out = path.resolve(args.out || path.join(os.tmpdir(), 'opengrokbot-voice-diagnosis-' + Date.now()));
const browsers = String(args.browsers || 'chromium,webkit').split(',').filter(Boolean);
const timeoutMs = Number(args.timeout || 600) * 1000;
const download = args.download === true;
const downloadCache = path.join(out, 'download-cache');
await fs.mkdir(out, { recursive: true });

const RUNTIME_BASE = 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.7.6/dist/';
const RUNTIME = {
  'ort-wasm-simd-threaded.jsep.mjs': '08fb86ec433c78bfb032c5d84a68b8e8e5a8d81268fa39e24314179a5767a5b9',
  'ort-wasm-simd-threaded.jsep.wasm': 'c46655e8a94afc45338d4cb2b840475f88e5012d524509916e505079c00bfa39'
};
const TTS_REPO = 'onnx-community/Kokoro-82M-v1.0-ONNX';

// ---- What is in the app's cache ----
async function walk(dir) {
  const files = [];
  async function go(current) {
    let entries = [];
    try { entries = await fs.readdir(current, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) await go(full); else { const info = await fs.stat(full); files.push({ path: path.relative(dir, full).split(path.sep).join('/'), bytes: info.size }); }
    }
  }
  await go(dir); return files;
}
const cacheFiles = await walk(cache);
const runtimeChecks = {};
for (const [name, hash] of Object.entries(RUNTIME)) {
  const file = path.join(cache, 'runtime', name);
  try { runtimeChecks[name] = crypto.createHash('sha256').update(await fs.readFile(file)).digest('hex') === hash ? 'ok' : 'checksum mismatch'; }
  catch { runtimeChecks[name] = 'missing'; }
}
const cachedSTT = [...new Set(cacheFiles.map(f => /^hf\/(onnx-community\/whisper-[^/]+)\//.exec(f.path)?.[1]).filter(Boolean))];
const sttModels = args.stt ? String(args.stt).split(',') : (cachedSTT.length ? cachedSTT : ['onnx-community/whisper-base.en']);
const ttsDtypes = args.tts ? String(args.tts).split(',') : ['q8'];

// ---- A server that serves the engine and the models exactly where the engine asks for them ----
const requests = [];
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://local');
  const send = (status, body = '', type = 'text/plain') => { res.writeHead(status, { 'Content-Type': type, 'Access-Control-Allow-Origin': '*', 'Cross-Origin-Resource-Policy': 'cross-origin' }); res.end(body); };
  if (url.pathname === '/' || url.pathname === '/index.html') return send(200, `<!doctype html><meta charset="utf-8"><script>globalThis.OGB_MODELS_BASE=location.origin+'/m/';</script><script src="/engine.js"></script>`, 'text/html');
  if (url.pathname === '/engine.js') return send(200, await fs.readFile(path.join(root, 'desktop-windows/renderer/local-voice-engine.js')), 'text/javascript');
  if (!url.pathname.startsWith('/m/')) return send(404);
  const rel = decodeURIComponent(url.pathname.slice(3));
  const started = Date.now();
  const local = rel.startsWith('ort/') ? path.join('runtime', rel.slice(4)) : rel;
  const type = rel.endsWith('.mjs') ? 'text/javascript' : rel.endsWith('.wasm') ? 'application/wasm' : rel.endsWith('.json') ? 'application/json' : 'application/octet-stream';
  for (const base of [cache, downloadCache]) {
    try { const body = await fs.readFile(path.join(base, local)); requests.push({ path: rel, status: 200, from: base === cache ? 'app cache' : 'download', bytes: body.length, ms: Date.now() - started }); return send(200, body, type); } catch {}
  }
  if (!download) { requests.push({ path: rel, status: 404, from: 'missing in app cache' }); return send(404); }
  try {
    const upstream = rel.startsWith('ort/') ? RUNTIME_BASE + rel.slice(4) : 'https://huggingface.co/' + rel.slice(3);
    const response = await fetch(upstream);
    if (!response.ok) { requests.push({ path: rel, status: response.status, from: 'upstream' }); return send(response.status); }
    const body = Buffer.from(await response.arrayBuffer());
    await fs.mkdir(path.dirname(path.join(downloadCache, local)), { recursive: true });
    await fs.writeFile(path.join(downloadCache, local), body);
    requests.push({ path: rel, status: 200, from: 'downloaded now', bytes: body.length, ms: Date.now() - started });
    send(200, body, type);
  } catch (error) { requests.push({ path: rel, status: 502, from: 'download failed: ' + error.message }); send(502); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;

// ---- Test speech for listening: spoken by the OS, with known text ----
const PHRASES = [
  'What is on my calendar for Tuesday afternoon?',
  'Ask the Calendar Agent to move soccer practice to six thirty.',
  'Book me a cruise from Galveston for spring break, and keep it under two thousand dollars.'
];
function wavSamples(buffer) {
  // 16-bit PCM WAV → Float32Array (first channel).
  const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  let offset = 12, rate = 16000, channels = 1, bits = 16, data = null;
  while (offset + 8 <= buffer.length) {
    const id = buffer.toString('ascii', offset, offset + 4), size = view.getUint32(offset + 4, true);
    if (id === 'fmt ') { channels = view.getUint16(offset + 10, true); rate = view.getUint32(offset + 12, true); bits = view.getUint16(offset + 22, true); }
    if (id === 'data') { data = [offset + 8, size]; break; }
    offset += 8 + size + (size % 2);
  }
  if (!data || bits !== 16) throw new Error('Unsupported WAV');
  const count = Math.floor(data[1] / 2 / channels), samples = new Float32Array(count);
  for (let i = 0; i < count; i++) samples[i] = view.getInt16(data[0] + i * 2 * channels, true) / 32768;
  return { samples, rate };
}
async function spoken(text, index) {
  const file = path.join(out, `phrase-${index + 1}.wav`);
  try {
    if (process.platform === 'darwin') {
      const aiff = path.join(out, `phrase-${index + 1}.aiff`);
      execFileSync('say', ['-o', aiff, text]);
      execFileSync('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', aiff, file]);
    } else if (process.platform === 'win32') {
      const script = `Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $f = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono); $s.SetOutputToWaveFile('${file.replace(/'/g, "''")}', $f); $s.Speak('${text.replace(/'/g, "''")}'); $s.Dispose()`;
      execFileSync('powershell', ['-NoProfile', '-Command', script]);
    } else return null;
    const { samples, rate } = wavSamples(await fs.readFile(file));
    if (rate !== 16000) return null;
    return samples;
  } catch { return null; }
}
const words = text => String(text).toLowerCase().replace(/[^a-z0-9' ]+/g, ' ').split(/\s+/).filter(Boolean);
function wordErrorRate(reference, hypothesis) {
  const r = words(reference), h = words(hypothesis), d = Array.from({ length: r.length + 1 }, (_, i) => [i, ...Array(h.length).fill(0)]);
  for (let j = 1; j <= h.length; j++) d[0][j] = j;
  for (let i = 1; i <= r.length; i++) for (let j = 1; j <= h.length; j++) d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1));
  return r.length ? +(d[r.length][h.length] / r.length).toFixed(3) : 0;
}
function audioStats(base64) {
  const bytes = Buffer.from(base64, 'base64'), { samples, rate } = wavSamples(bytes);
  let peak = 0, sum = 0, lead = 0; for (let i = 0; i < samples.length; i++) { const v = Math.abs(samples[i]); peak = Math.max(peak, v); sum += v * v; }
  while (lead < samples.length && Math.abs(samples[lead]) < 0.01) lead++;
  return { bytes, seconds: +(samples.length / rate).toFixed(2), rate, peak: +peak.toFixed(3), rms: +Math.sqrt(sum / Math.max(1, samples.length)).toFixed(4), leadingSilenceMs: Math.round(lead / rate * 1000), clipped: peak >= 0.999 };
}
const phraseAudio = [];
for (const [index, text] of PHRASES.entries()) phraseAudio.push(await spoken(text, index));

// ---- Run the engine ----
let playwright;
try { playwright = await import('playwright'); }
catch { console.error('Playwright is missing. Run: npm install --no-save playwright@1.56.1 && npx playwright install chromium webkit'); process.exit(2); }

const SAY = ['Hi! I found three cruises from Galveston.', 'The cheapest leaves March fourteenth, and it is about twelve hundred dollars for two people.', 'Want me to hold a cabin while you check the dates with your family, or should I keep looking for something with a balcony?'];
const report = { generated: new Date().toISOString(), platform: { os: `${os.type()} ${os.release()}`, arch: os.arch(), cpu: os.cpus()[0]?.model, cores: os.cpus().length, memoryGB: Math.round(os.totalmem() / 2 ** 30) }, cache: { dir: cache, files: cacheFiles.length, totalMB: Math.round(cacheFiles.reduce((n, f) => n + f.bytes, 0) / 1e6), runtime: runtimeChecks, whisperModels: cachedSTT, kokoro: cacheFiles.some(f => f.path.startsWith('hf/' + TTS_REPO)) }, runs: [] };

for (const name of browsers) {
  const run = { browser: name, console: [], errors: [], capabilities: null, tts: [], stt: [] };
  report.runs.push(run);
  let browser;
  try {
    browser = await playwright[name].launch({ ...(name === 'chromium' ? { args: ['--enable-unsafe-webgpu'] } : {}), ...(process.env.OGB_BROWSER_PATH && name === 'chromium' ? { executablePath: process.env.OGB_BROWSER_PATH } : {}) });
    const page = await browser.newPage();
    page.setDefaultTimeout(timeoutMs);
    page.on('console', message => { if (run.console.length < 200) run.console.push(`${message.type()}: ${message.text().slice(0, 400)}`); });
    page.on('pageerror', error => run.errors.push(String(error.message).slice(0, 400)));
    await page.goto(origin + '/index.html');
    await page.waitForFunction(() => typeof globalThis.OGBLocalVoice === 'object', null, { timeout: 30000 });
    run.capabilities = await page.evaluate(() => OGBLocalVoice.capabilities());
    const devices = run.capabilities.webgpu ? ['wasm', 'webgpu'] : ['wasm'];
    for (const device of devices) for (const dtype of ttsDtypes) {
      const entry = { device, dtype, samples: [] };
      run.tts.push(entry);
      try {
        const started = Date.now();
        await page.evaluate(options => OGBLocalVoice.loadTTS(options), { dtype, device });
        entry.loadMs = Date.now() - started;
        for (const [index, text] of SAY.entries()) {
          const begin = Date.now();
          const base64 = await page.evaluate(([value, voice]) => OGBLocalVoice.speak(value, { voice, encoding: 'base64' }), [text, 'af_heart']);
          const ms = Date.now() - begin, stats = audioStats(base64);
          const file = path.join(out, `kokoro-${name}-${device}-${dtype}-${index + 1}.wav`);
          await fs.writeFile(file, stats.bytes);
          entry.samples.push({ text, ms, ...{ ...stats, bytes: undefined }, realTimeFactor: +(ms / 1000 / Math.max(stats.seconds, 0.01)).toFixed(2), file });
        }
      } catch (error) { entry.error = String(error.message || error).slice(0, 500); }
    }
    for (const model of sttModels) for (const device of devices) {
      const entry = { model, device, phrases: [] };
      run.stt.push(entry);
      try {
        const started = Date.now();
        await page.evaluate(options => OGBLocalVoice.loadSTT(options), { model, device });
        entry.loadMs = Date.now() - started;
        for (const [index, reference] of PHRASES.entries()) {
          const samples = phraseAudio[index];
          if (!samples) { entry.phrases.push({ reference, skipped: 'Could not make test speech on this OS' }); continue; }
          const begin = Date.now();
          const heard = await page.evaluate(([b64]) => OGBLocalVoice.transcribe(b64, { language: 'en' }), [Buffer.from(samples.buffer).toString('base64')]);
          entry.phrases.push({ reference, heard, ms: Date.now() - begin, audioSeconds: +(samples.length / 16000).toFixed(2), wordErrorRate: wordErrorRate(reference, heard) });
        }
      } catch (error) { entry.error = String(error.message || error).slice(0, 500); }
    }
  } catch (error) { run.errors.push('Run failed: ' + String(error.message || error).slice(0, 400)); }
  finally { await browser?.close(); }
}
server.close();
report.requests = { total: requests.length, missing: requests.filter(r => r.status !== 200).slice(0, 80), downloadedMB: Math.round(requests.filter(r => r.from === 'downloaded now').reduce((n, r) => n + (r.bytes || 0), 0) / 1e6) };

await fs.writeFile(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
const lines = [`# OpenGrokBot local voice diagnosis`, '', `${report.platform.os} · ${report.platform.arch} · ${report.platform.cpu} · ${report.platform.cores} cores · ${report.platform.memoryGB} GB`, '',
  `App cache: ${cache} — ${report.cache.files} files, ${report.cache.totalMB} MB · runtime ${JSON.stringify(runtimeChecks)} · Kokoro ${report.cache.kokoro ? 'present' : 'missing'} · Whisper ${cachedSTT.join(', ') || 'none'}`, ''];
for (const run of report.runs) {
  lines.push(`## ${run.browser}${run.browser === 'webkit' ? ' (closest to the Mac app)' : ''}`, `Capabilities: ${JSON.stringify(run.capabilities)}`);
  for (const t of run.tts) lines.push(t.error ? `- Kokoro ${t.dtype}/${t.device}: ERROR ${t.error}` : `- Kokoro ${t.dtype}/${t.device}: load ${t.loadMs} ms; ` + t.samples.map(s => `${s.seconds}s audio in ${s.ms} ms (RTF ${s.realTimeFactor}, peak ${s.peak}, lead silence ${s.leadingSilenceMs} ms${s.clipped ? ', CLIPPED' : ''})`).join('; '));
  for (const s of run.stt) lines.push(s.error ? `- ${s.model}/${s.device}: ERROR ${s.error}` : `- ${s.model}/${s.device}: load ${s.loadMs} ms; ` + s.phrases.map(p => p.skipped ? p.skipped : `WER ${p.wordErrorRate} in ${p.ms} ms for ${p.audioSeconds}s → “${p.heard}”`).join(' | '));
  if (run.errors.length) lines.push(`Errors: ${run.errors.join(' | ')}`);
  const noisy = run.console.filter(line => /^(error|warning)/.test(line)).slice(0, 15);
  if (noisy.length) lines.push('Console:', ...noisy.map(line => '    ' + line));
  lines.push('');
}
if (report.requests.missing.length) lines.push('Files the engine asked for but could not get:', ...report.requests.missing.map(r => `- ${r.status} ${r.path} (${r.from})`), '');
await fs.writeFile(path.join(out, 'report.md'), lines.join('\n'));
console.log(lines.join('\n'));
console.log(`\nFull report: ${path.join(out, 'report.json')}\nSpoken samples (listen to these): ${out}`);
