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

const voice = require('./voice.cjs');
const { EventEmitter } = require('node:events');

test('gemini speaks through generateContent and returns a WAV at the reported rate', async () => {
  let seen;
  const reply = mime => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ inlineData: { mimeType: mime, data: 'AQIDBA==' } }] } }] }));
  const wav = await synthesize({ provider: 'gemini', key: 'AIza-test', text: 'Hello', geminiModel: 'gemini-2.5-flash-preview-tts', geminiVoice: 'Puck', fetchImpl: async (url, init) => { seen = { url, init }; return reply('audio/L16;codec=pcm;rate=24000'); } });
  assert.equal(seen.url, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent');
  assert.equal(seen.init.headers['x-goog-api-key'], 'AIza-test');
  const body = JSON.parse(seen.init.body);
  assert.equal(body.contents[0].parts[0].text, 'Hello');
  assert.deepEqual(body.generationConfig.responseModalities, ['AUDIO']);
  assert.equal(body.generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Puck');
  assert.equal(wav.toString('latin1', 0, 4), 'RIFF'); assert.equal(wav.length, 48); assert.equal(wav.readUInt32LE(24), 24000); assert.deepEqual([...wav.subarray(44)], [1, 2, 3, 4]);
  const other = await synthesize({ provider: 'gemini', key: 'k', text: 'x', geminiVoice: '../evil', fetchImpl: async (_u, init) => { assert.equal(JSON.parse(init.body).generationConfig.speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName, 'Kore'); return reply('audio/L16;rate=16000'); } });
  assert.equal(other.readUInt32LE(24), 16000);
  await assert.rejects(synthesize({ provider: 'gemini', key: 'k', text: 'x', geminiModel: '../x' }), /model name/);
  await assert.rejects(synthesize({ provider: 'gemini', key: '', text: 'x' }), VoiceError);
  await assert.rejects(synthesize({ provider: 'gemini', key: 'k', text: 'x', fetchImpl: async () => new Response('', { status: 400 }) }), /Google AI Studio returned an error \(400\)/);
  await assert.rejects(synthesize({ provider: 'gemini', key: 'k', text: 'x', fetchImpl: async () => new Response('{"candidates":[]}') }), /no audio/);
});

test('gemini addresses and models are validated', () => {
  const base = 'https://generativelanguage.googleapis.com';
  assert.equal(voice.geminiURL(base, 'gemini-3.1-flash-tts-preview'), base + '/v1beta/models/gemini-3.1-flash-tts-preview:generateContent');
  for (const [b, m] of [['http://x.example', 'm'], [base, '../x'], [base, ''], [base, 'two words'], ['', 'm'], ['https://u:p@x.example', 'm'], [base + '?k=1', 'm']]) assert.equal(voice.geminiURL(b, m), null, `${b} ${m}`);
});

test('NVIDIA Cloud requests and gRPC frames are built and read correctly', () => {
  assert.deepEqual([...voice.rivaRequest({ text: 'hi', voice: 'V' })], [0x0a, 0x02, 0x68, 0x69, 0x12, 0x05, 0x65, 0x6e, 0x2d, 0x55, 0x53, 0x18, 0x01, 0x20, 0xa2, 0xac, 0x01, 0x2a, 0x01, 0x56]);
  const request = voice.rivaRequest({ text: 'hi', voice: 'V' }), framed = voice.grpcFrame(request);
  assert.deepEqual([...framed.subarray(0, 5)], [0, 0, 0, 0, request.length]);
  assert.deepEqual(voice.grpcUnframe(framed), request);
  assert.equal(voice.grpcUnframe(Buffer.from([1, 0, 0, 0, 1, 9])), null); assert.equal(voice.grpcUnframe(Buffer.from([0, 0, 0, 0, 9, 1])), null);
  const response = Buffer.from([0x10, 0x05, 0x0a, 0x04, 1, 2, 3, 4]);
  assert.deepEqual([...voice.rivaAudio(response)], [1, 2, 3, 4]);
  assert.equal(voice.rivaAudio(Buffer.from([0x0a, 0x09, 1])), null);
  const wav = voice.decodeNVIDIACloud(voice.grpcFrame(response));
  assert.equal(wav.toString('latin1', 0, 4), 'RIFF'); assert.equal(wav.length, 48); assert.equal(wav.readUInt32LE(24), 22050);
  assert.throws(() => voice.decodeNVIDIACloud(Buffer.alloc(0)), /no audio/);
  assert.deepEqual(voice.nvidiaCloudTarget('grpc.nvcf.nvidia.com:443'), { host: 'grpc.nvcf.nvidia.com', port: 443 });
  assert.deepEqual(voice.nvidiaCloudTarget(' https://grpc.nvcf.nvidia.com/ '), { host: 'grpc.nvcf.nvidia.com', port: 443 });
  for (const bad of ['', 'localhost', 'evil.example/path', 'a b.example', 'http://x.example']) assert.equal(voice.nvidiaCloudTarget(bad), null, bad);
  assert.ok(voice.isFunctionID('877104f7-e885-42b9-8de8-f6e4c6303969')); for (const bad of ['', 'short', 'bad id!', '../../x']) assert.ok(!voice.isFunctionID(bad), bad);
});

const fakeHttp2 = ({ status = 200, trailers = { 'grpc-status': '0' }, audio = Buffer.from([0x0a, 0x04, 1, 2, 3, 4]), failConnect = false } = {}) => {
  const seen = {};
  return { seen, connect(url) {
    seen.url = url;
    const client = new EventEmitter(); client.close = () => {};
    if (failConnect) setImmediate(() => client.emit('error', new Error('ECONNREFUSED')));
    client.request = headers => {
      seen.headers = headers;
      const stream = new EventEmitter();
      stream.end = body => { seen.body = body; setImmediate(() => { stream.emit('response', { ':status': status }); if (status === 200) stream.emit('data', voice.grpcFrame(audio)); stream.emit('trailers', trailers); stream.emit('end'); }); };
      return stream;
    };
    return client;
  } };
};

test('NVIDIA Cloud calls the Riva gRPC method with the key and function ID, and maps errors', async () => {
  const ok = fakeHttp2();
  const wav = await synthesize({ provider: 'nvidiaCloud', key: 'nvapi-test', text: 'Hello', nvcServer: 'grpc.nvcf.nvidia.com:443', nvcFunction: '877104f7-e885-42b9-8de8-f6e4c6303969', nvcVoice: 'Magpie-Multilingual.EN-US.Aria', http2: ok });
  assert.equal(ok.seen.url, 'https://grpc.nvcf.nvidia.com:443');
  assert.equal(ok.seen.headers[':path'], '/riva.tts.RivaSpeechSynthesis/Synthesize');
  assert.equal(ok.seen.headers.authorization, 'Bearer nvapi-test'); assert.equal(ok.seen.headers['function-id'], '877104f7-e885-42b9-8de8-f6e4c6303969');
  assert.equal(ok.seen.headers['content-type'], 'application/grpc');
  assert.deepEqual(voice.grpcUnframe(ok.seen.body), voice.rivaRequest({ text: 'Hello', voice: 'Magpie-Multilingual.EN-US.Aria' }));
  assert.equal(wav.toString('latin1', 0, 4), 'RIFF'); assert.deepEqual([...wav.subarray(44)], [1, 2, 3, 4]);
  const base = { provider: 'nvidiaCloud', key: 'k', text: 'x', nvcServer: 'grpc.nvcf.nvidia.com:443', nvcFunction: '877104f7-e885-42b9-8de8-f6e4c6303969' };
  await assert.rejects(synthesize({ ...base, http2: fakeHttp2({ status: 401 }) }), /rejected the key/);
  await assert.rejects(synthesize({ ...base, http2: fakeHttp2({ trailers: { 'grpc-status': '16' } }) }), /rejected the key/);
  await assert.rejects(synthesize({ ...base, http2: fakeHttp2({ trailers: { 'grpc-status': '8' } }) }), /quota/);
  await assert.rejects(synthesize({ ...base, http2: fakeHttp2({ trailers: { 'grpc-status': '5' } }) }), /gRPC 5/);
  await assert.rejects(synthesize({ ...base, http2: fakeHttp2({ failConnect: true }) }), /Couldn’t reach NVIDIA Cloud/);
  await assert.rejects(synthesize({ ...base, key: '', http2: fakeHttp2() }), VoiceError);
  await assert.rejects(synthesize({ ...base, nvcServer: 'localhost', http2: fakeHttp2() }), /server address/);
  await assert.rejects(synthesize({ ...base, nvcFunction: '../x', http2: fakeHttp2() }), /function/);
  await assert.rejects(synthesize({ ...base, nvcVoice: 'bad voice!', http2: fakeHttp2() }), /voice name/);
});
