'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { transcribe, synthesize, nimURL, VoiceError } = require('./voice.cjs');

const wav = Buffer.alloc(2000, 1);

test('groq transcription posts multipart audio with a bearer key', async () => {
  let seen;
  const text = await transcribe({ provider: 'groq', key: 'gsk_test', wav, fetchImpl: async (url, init) => { seen = { url, init }; return new Response(JSON.stringify({ text: ' hello there ' })); } });
  assert.equal(text, 'hello there');
  assert.equal(seen.url, 'https://api.groq.com/openai/v1/audio/transcriptions');
  assert.equal(seen.init.headers.Authorization, 'Bearer gsk_test');
  assert.equal(seen.init.body.get('model'), 'whisper-large-v3-turbo');
  assert.ok(seen.init.body.get('file') instanceof Blob);
});

test('elevenlabs transcription uses xi-api-key and model_id', async () => {
  let seen;
  await transcribe({ provider: 'elevenLabs', key: 'k', wav, fetchImpl: async (url, init) => { seen = { url, init }; return new Response('{"text":"x"}'); } });
  assert.equal(seen.init.headers['xi-api-key'], 'k');
  assert.equal(seen.init.body.get('model_id'), 'scribe_v1');
});

test('maps provider failures to friendly errors', async () => {
  await assert.rejects(transcribe({ provider: 'openAI', key: 'k', wav, fetchImpl: async () => new Response('', { status: 401 }) }), /rejected the key/);
  await assert.rejects(transcribe({ provider: 'openAI', key: 'k', wav, fetchImpl: async () => new Response('', { status: 429 }) }), /quota/);
  await assert.rejects(transcribe({ provider: 'apple', key: 'k', wav }), VoiceError);
  await assert.rejects(transcribe({ provider: 'groq', key: '', wav }), VoiceError);
  await assert.rejects(transcribe({ provider: 'groq', key: 'k', wav: Buffer.alloc(10) }), VoiceError);
});

test('speech synthesis returns audio bytes and validates input', async () => {
  const audio = await synthesize({ provider: 'openAI', key: 'k', text: 'hi', fetchImpl: async (_url, init) => { assert.equal(JSON.parse(init.body).input, 'hi'); return new Response(new Uint8Array([1, 2, 3])); } });
  assert.deepEqual([...audio], [1, 2, 3]);
  await assert.rejects(synthesize({ provider: 'elevenLabs', key: 'k', text: 'hi', voiceID: '../evil' }), /voice ID/);
  await assert.rejects(synthesize({ provider: 'apple', key: 'k', text: 'hi' }), VoiceError);
  await assert.rejects(synthesize({ provider: 'groq', key: '', text: 'hi' }), VoiceError);
  await assert.rejects(synthesize({ provider: 'openAI', key: 'k', text: '' }), VoiceError);
});

test('groq speaks with Orpheus, a known voice and WAV output', async () => {
  let seen;
  const audio = await synthesize({ provider: 'groq', key: 'gsk_k', text: 'Hello there.', groqVoice: 'diana', fetchImpl: async (url, init) => { seen = { url, init }; return new Response(new Uint8Array([82, 73, 70, 70])); } });
  assert.deepEqual([...audio], [82, 73, 70, 70]);
  assert.equal(seen.url, 'https://api.groq.com/openai/v1/audio/speech');
  assert.equal(seen.init.headers.Authorization, 'Bearer gsk_k');
  assert.deepEqual(JSON.parse(seen.init.body), { model: 'canopylabs/orpheus-v1-english', voice: 'diana', input: 'Hello there.', response_format: 'wav' });
  await synthesize({ provider: 'groq', key: 'k', text: 'x', groqVoice: '../evil', fetchImpl: async (_url, init) => { assert.equal(JSON.parse(init.body).voice, 'autumn'); return new Response(new Uint8Array([1])); } });
});

test('nvidia NIM posts a form to the synthesize endpoint and needs no key', async () => {
  let seen;
  const audio = await synthesize({ provider: 'nvidiaNIM', key: '', text: 'Hello', nimBase: 'http://localhost:9000/', nimVoice: 'Magpie-Multilingual.EN-US.Aria', fetchImpl: async (url, init) => { seen = { url, init }; return new Response(new Uint8Array([9, 8])); } });
  assert.deepEqual([...audio], [9, 8]);
  assert.equal(seen.url, 'http://localhost:9000/v1/audio/synthesize');
  assert.equal(seen.init.body.get('text'), 'Hello');
  assert.equal(seen.init.body.get('voice'), 'Magpie-Multilingual.EN-US.Aria');
  assert.equal(seen.init.body.get('language'), 'en-US');
  assert.equal(seen.init.headers.Authorization, undefined);
  await synthesize({ provider: 'nvidiaNIM', key: 'secret', text: 'x', nimBase: 'https://nim.example.com/base', fetchImpl: async (url, init) => { assert.equal(url, 'https://nim.example.com/base/v1/audio/synthesize'); assert.equal(init.headers.Authorization, 'Bearer secret'); return new Response(new Uint8Array([1])); } });
  await assert.rejects(synthesize({ provider: 'nvidiaNIM', text: 'x', nimBase: 'ftp://host' }), /address/);
  await assert.rejects(synthesize({ provider: 'nvidiaNIM', text: 'x', nimBase: 'http://localhost:9000', nimVoice: 'bad voice!', fetchImpl: async () => new Response('') }), /voice name/);
  await assert.rejects(synthesize({ provider: 'nvidiaNIM', text: 'x', nimBase: 'http://localhost:9000', fetchImpl: async () => { throw new TypeError('fetch failed'); } }), /Couldn’t reach your NVIDIA NIM/);
  await assert.rejects(synthesize({ provider: 'nvidiaNIM', text: 'x', nimBase: 'http://localhost:9000', fetchImpl: async () => new Response('', { status: 500 }) }), /NVIDIA NIM returned an error \(500\)/);
});

test('NIM addresses must be plain http(s) server addresses', () => {
  assert.equal(nimURL('http://localhost:9000'), 'http://localhost:9000/v1/audio/synthesize');
  assert.equal(nimURL(' http://gpu-box.lan:9000/ '), 'http://gpu-box.lan:9000/v1/audio/synthesize');
  for (const bad of ['', 'localhost:9000', 'ftp://host', 'http://user:pw@host:9000', 'http://host?x=1', 'file:///etc/passwd', null]) assert.equal(nimURL(bad), null, String(bad));
});
