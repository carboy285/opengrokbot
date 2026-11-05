'use strict';
// Optional cloud speech for the Windows app. Network calls run here in the main process (the renderer CSP blocks them).
// Keys are stored encrypted by main.cjs; this module only receives them for a single request.

const PROVIDERS = new Set(['groq', 'openAI', 'elevenLabs']);
// Providers that can speak replies. NVIDIA NIM is a speech server you run yourself, so its key is optional.
const SPEAKERS = new Set(['openAI', 'elevenLabs', 'groq', 'nvidiaNIM', 'nvidiaCloud', 'gemini']);
const GEMINI_VOICES = ['Kore', 'Puck', 'Zephyr', 'Charon', 'Fenrir', 'Aoede', 'Leda', 'Orus', 'Callirrhoe', 'Enceladus'];
const GROQ_VOICES = ['autumn', 'diana', 'hannah', 'austin', 'daniel', 'troy'];

/** The synthesize endpoint for a NIM base address, or null unless it is a plain http(s) server address. */
function nimURL(base) {
  const text = String(base ?? '').trim();
  if (!text || text.length > 300) return null;
  let url; try { url = new URL(text); } catch { return null; }
  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) return null;
  return `${url.origin}${url.pathname.replace(/\/$/, '')}/v1/audio/synthesize`;
}

class VoiceError extends Error {}

async function check(response, provider) {
  if (response.ok) return response;
  if (response.status === 401 || response.status === 403) throw new VoiceError(`${provider} rejected the key. Check it in Settings → Voice.`);
  if (response.status === 429) throw new VoiceError(`${provider} free quota or rate limit reached.`);
  throw new VoiceError(`${provider} returned an error (${response.status}).`);
}


/** The generateContent address for a Gemini model, or null unless the base is a plain https address and the model a simple identifier. */
function geminiURL(base, model) {
  const name = String(model ?? '').trim();
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(name)) return null;
  let url; try { url = new URL(String(base ?? '').trim()); } catch { return null; }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.search || url.hash) return null;
  return `${url.origin}${url.pathname.replace(/\/$/, '')}/v1beta/models/${name}:generateContent`;
}

/** host and port for an NVIDIA Cloud gRPC server such as grpc.nvcf.nvidia.com:443 (an https:// prefix is accepted), or null. */
function nvidiaCloudTarget(server) {
  let text = String(server ?? '').trim().replace(/^https:\/\//i, '').replace(/\/$/, '');
  if (!/^[A-Za-z0-9.-]{1,200}(:[0-9]{1,5})?$/.test(text) || !text.includes('.')) return null;
  const [host, port] = text.split(':');
  return { host, port: Number(port || 443) };
}
const isFunctionID = id => /^[A-Za-z0-9-]{8,64}$/.test(String(id ?? '').trim());

/** 16-bit mono PCM to a playable WAV. */
function wrapWav(pcm, sampleRate) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(36 + pcm.length, 4); header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24); header.writeUInt32LE(sampleRate * 2, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}
const isWav = buffer => buffer.length > 4 && buffer.toString('latin1', 0, 4) === 'RIFF';

/** Gemini answers with JSON whose first part carries base64 audio (raw PCM, usually 24 kHz). */
function decodeGemini(json) {
  const inline = (json?.candidates?.[0]?.content?.parts || []).map(part => part.inlineData || part.inline_data).find(Boolean);
  const pcm = inline && typeof inline.data === 'string' ? Buffer.from(inline.data, 'base64') : null;
  if (!pcm || !pcm.length) throw new VoiceError('Google AI Studio returned no audio. Check the model name and that it supports speech.');
  const mime = String(inline.mimeType || inline.mime_type || ''); const rate = Number((/rate=(\d+)/.exec(mime) || [])[1]) || 24000;
  return isWav(pcm) ? pcm : wrapWav(pcm, rate >= 8000 && rate <= 48000 ? rate : 24000);
}

// Minimal Riva (NVIDIA speech) gRPC messages.
function varint(value) { const out = []; let rest = BigInt(value); while (rest >= 0x80n) { out.push(Number(rest & 0x7fn) | 0x80); rest >>= 7n; } out.push(Number(rest)); return Buffer.from(out); }
const stringField = (number, text) => { const bytes = Buffer.from(text, 'utf8'); return Buffer.concat([varint(number << 3 | 2), varint(bytes.length), bytes]); };
const intField = (number, value) => Buffer.concat([varint(number << 3), varint(value)]);
/** SynthesizeSpeechRequest: text (1), language_code (2), encoding (3, 1 = linear PCM), sample_rate_hz (4), voice_name (5). */
function rivaRequest({ text, language = 'en-US', sampleRate = 22050, voice }) { return Buffer.concat([stringField(1, text), stringField(2, language), intField(3, 1), intField(4, sampleRate), stringField(5, voice)]); }
function grpcFrame(message) { const head = Buffer.alloc(5); head.writeUInt32BE(message.length, 1); return Buffer.concat([head, message]); }
function grpcUnframe(buffer) { if (buffer.length < 5 || buffer[0] !== 0) return null; const length = buffer.readUInt32BE(1); return length > 0 && buffer.length >= 5 + length ? buffer.subarray(5, 5 + length) : null; }
/** SynthesizeSpeechResponse: the audio is field 1 (bytes). */
function rivaAudio(message) {
  let index = 0;
  const read = () => { let value = 0n, shift = 0n; while (index < message.length && shift < 64n) { const byte = message[index++]; value |= BigInt(byte & 0x7f) << shift; if (!(byte & 0x80)) return value; shift += 7n; } return null; };
  while (index < message.length) {
    const key = read(); if (key === null) return null;
    const wire = Number(key & 7n);
    if (wire === 0) { if (read() === null) return null; }
    else if (wire === 1) index += 8; else if (wire === 5) index += 4;
    else if (wire === 2) { const length = read(); if (length === null || index + Number(length) > message.length) return null; if (key >> 3n === 1n) return message.subarray(index, index + Number(length)); index += Number(length); }
    else return null;
  }
  return null;
}
function decodeNVIDIACloud(buffer, sampleRate = 22050) {
  const message = grpcUnframe(buffer), audio = message && rivaAudio(message);
  if (!audio || !audio.length) throw new VoiceError('NVIDIA Cloud returned no audio. Check the API key, function ID and server address in Settings → Voice.');
  return isWav(audio) ? Buffer.from(audio) : wrapWav(Buffer.from(audio), sampleRate);
}
/** One unary gRPC call over HTTP/2. `http2` is injectable for tests. */
function nvidiaCloudCall({ target, key, functionID, text, voice, http2 = require('node:http2'), timeout = 30000 }) {
  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${target.host}:${target.port}`);
    const chunks = []; let done = false;
    const finish = (error, value) => { if (done) return; done = true; clearTimeout(timer); try { client.close(); } catch {} error ? reject(error) : resolve(value); };
    const timer = setTimeout(() => finish(new VoiceError('NVIDIA Cloud did not answer in time.')), timeout);
    client.on('error', () => finish(new VoiceError(`Couldn’t reach NVIDIA Cloud at ${target.host}:${target.port}. Check your connection and the server address in Settings → Voice.`)));
    const request = client.request({ ':method': 'POST', ':path': '/riva.tts.RivaSpeechSynthesis/Synthesize', 'content-type': 'application/grpc', te: 'trailers', authorization: `Bearer ${key}`, 'function-id': functionID });
    let status = 0, grpcStatus = '0';
    request.on('response', headers => { status = Number(headers[':status']); if (headers['grpc-status'] !== undefined) grpcStatus = String(headers['grpc-status']); });
    request.on('trailers', headers => { if (headers['grpc-status'] !== undefined) grpcStatus = String(headers['grpc-status']); });
    request.on('data', chunk => chunks.push(chunk));
    request.on('error', () => finish(new VoiceError('NVIDIA Cloud closed the connection. Check the API key and function ID in Settings → Voice.')));
    request.on('end', () => {
      if (status === 401 || status === 403 || grpcStatus === '16' || grpcStatus === '7') return finish(new VoiceError('NVIDIA Cloud rejected the key. Check it in Settings → Voice.'));
      if (grpcStatus === '8' || status === 429) return finish(new VoiceError('NVIDIA Cloud free quota or rate limit reached.'));
      if (status && status !== 200 || grpcStatus !== '0') return finish(new VoiceError(`NVIDIA Cloud returned an error (${status !== 200 ? status : 'gRPC ' + grpcStatus}). Check the function ID and voice.`));
      finish(null, Buffer.concat(chunks));
    });
    request.end(grpcFrame(rivaRequest({ text, voice })));
  });
}

async function transcribe({ provider, key, wav, fetchImpl = fetch }) {
  if (!PROVIDERS.has(provider) || !key) throw new VoiceError('Choose a speech provider and add its key in Settings → Voice.');
  if (!Buffer.isBuffer(wav) || wav.length < 1000 || wav.length > 10_000_000) throw new VoiceError('Invalid audio.');
  const form = new FormData();
  form.append('file', new Blob([wav], { type: 'audio/wav' }), 'speech.wav');
  let url, headers;
  if (provider === 'elevenLabs') { url = 'https://api.elevenlabs.io/v1/speech-to-text'; headers = { 'xi-api-key': key }; form.append('model_id', 'scribe_v1'); }
  else {
    url = provider === 'groq' ? 'https://api.groq.com/openai/v1/audio/transcriptions' : 'https://api.openai.com/v1/audio/transcriptions';
    headers = { Authorization: `Bearer ${key}` };
    form.append('model', provider === 'groq' ? 'whisper-large-v3-turbo' : 'whisper-1'); form.append('response_format', 'json');
  }
  const response = await check(await fetchImpl(url, { method: 'POST', headers, body: form, signal: AbortSignal.timeout(30000) }), provider);
  const body = await response.json();
  return typeof body.text === 'string' ? body.text.trim() : '';
}

async function synthesize({ provider, key, text, voiceID, groqVoice, nimBase, nimVoice, geminiModel, geminiVoice, geminiBase, nvcServer, nvcFunction, nvcVoice, fetchImpl = fetch, http2 }) {
  if (!SPEAKERS.has(provider) || (!key && provider !== 'nvidiaNIM')) throw new VoiceError('This provider cannot speak replies.');
  if (typeof text !== 'string' || !text.trim() || text.length > 4500) throw new VoiceError('Invalid text.');
  if (provider === 'nvidiaCloud') {
    const target = nvidiaCloudTarget(nvcServer);
    if (!target) throw new VoiceError('The NVIDIA Cloud server address in Settings → Voice looks invalid. Use something like grpc.nvcf.nvidia.com:443.');
    if (!isFunctionID(nvcFunction)) throw new VoiceError('The NVIDIA Cloud function (model) ID in Settings → Voice looks invalid.');
    const voice = String(nvcVoice || 'Magpie-Multilingual.EN-US.Aria');
    if (!/^[A-Za-z0-9._-]{1,80}$/.test(voice)) throw new VoiceError('The NVIDIA Cloud voice name looks invalid.');
    return decodeNVIDIACloud(await nvidiaCloudCall({ target, key, functionID: String(nvcFunction).trim(), text, voice, ...(http2 ? { http2 } : {}) }));
  }
  let url, headers, body, timeout = 45000;
  if (provider === 'openAI') {
    url = 'https://api.openai.com/v1/audio/speech'; headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    body = JSON.stringify({ model: 'tts-1', voice: 'alloy', input: text, response_format: 'mp3' });
  } else if (provider === 'groq') {
    const voice = GROQ_VOICES.includes(groqVoice) ? groqVoice : 'autumn';
    url = 'https://api.groq.com/openai/v1/audio/speech'; headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }; timeout = 30000;
    body = JSON.stringify({ model: 'canopylabs/orpheus-v1-english', voice, input: text, response_format: 'wav' });
  } else if (provider === 'gemini') {
    url = geminiURL(geminiBase || 'https://generativelanguage.googleapis.com', geminiModel || 'gemini-2.5-flash-preview-tts');
    if (!url) throw new VoiceError('The Google AI Studio model name or address in Settings → Voice looks invalid.');
    const voice = GEMINI_VOICES.includes(geminiVoice) ? geminiVoice : 'Kore';
    headers = { 'x-goog-api-key': key, 'Content-Type': 'application/json' };
    body = JSON.stringify({ contents: [{ parts: [{ text }] }], generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } } } });
  } else if (provider === 'nvidiaNIM') {
    url = nimURL(nimBase);
    if (!url) throw new VoiceError('The NVIDIA NIM address in Settings → Voice looks invalid. Use something like http://localhost:9000.');
    const voice = String(nimVoice || 'Magpie-Multilingual.EN-US.Aria');
    if (!/^[A-Za-z0-9._-]{1,80}$/.test(voice)) throw new VoiceError('The NVIDIA NIM voice name looks invalid.');
    headers = key ? { Authorization: `Bearer ${key}` } : {}; timeout = 30000;
    const form = new FormData(); form.append('language', 'en-US'); form.append('text', text); form.append('voice', voice); body = form;
  } else {
    const id = String(voiceID || '21m00Tcm4TlvDq8ikWAM');
    if (!/^[A-Za-z0-9]{8,40}$/.test(id)) throw new VoiceError('The ElevenLabs voice ID looks invalid.');
    url = `https://api.elevenlabs.io/v1/text-to-speech/${id}?output_format=mp3_44100_64`; headers = { 'xi-api-key': key, 'Content-Type': 'application/json' };
    body = JSON.stringify({ text, model_id: 'eleven_flash_v2_5' });
  }
  let response;
  try { response = await fetchImpl(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(timeout) }); }
  catch (error) {
    if (provider === 'nvidiaNIM') throw new VoiceError(`Couldn’t reach your NVIDIA NIM at ${nimBase}. Is the container running?`);
    throw error;
  }
  response = await check(response, provider === 'nvidiaNIM' ? 'NVIDIA NIM' : provider === 'gemini' ? 'Google AI Studio' : provider);
  if (provider === 'gemini') return decodeGemini(await response.json());
  return Buffer.from(await response.arrayBuffer());
}

module.exports = { transcribe, synthesize, nimURL, geminiURL, nvidiaCloudTarget, isFunctionID, wrapWav, decodeGemini, decodeNVIDIACloud, rivaRequest, grpcFrame, grpcUnframe, rivaAudio, VoiceError, PROVIDERS, SPEAKERS, GROQ_VOICES, GEMINI_VOICES };
