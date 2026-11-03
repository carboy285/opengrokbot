'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { transcribe, synthesize, VoiceError } = require('./voice.cjs');

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
  await assert.rejects(synthesize({ provider: 'groq', key: 'k', text: 'hi' }), VoiceError);
  await assert.rejects(synthesize({ provider: 'openAI', key: 'k', text: '' }), VoiceError);
});
