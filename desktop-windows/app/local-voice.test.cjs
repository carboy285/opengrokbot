const test = require('node:test'), assert = require('node:assert/strict');
const os = require('node:os'), path = require('node:path'), fs = require('node:fs/promises'), crypto = require('node:crypto');
const lv = require('./local-voice.cjs');

test('recommends models that fit the machine', () => {
  assert.equal(lv.recommend({ memoryGB: 32, cores: 12, webgpu: true }).stt.model, 'onnx-community/whisper-small.en');
  assert.equal(lv.recommend({ memoryGB: 32, cores: 12, webgpu: true }).tts.device, 'webgpu');
  assert.equal(lv.recommend({ memoryGB: 16, cores: 8, webgpu: false }).stt.model, 'onnx-community/whisper-base.en');
  assert.equal(lv.recommend({ memoryGB: 4, cores: 2, webgpu: false }).stt.model, 'onnx-community/whisper-tiny.en');
  assert.equal(lv.recommend({ memoryGB: 4, cores: 2, webgpu: false, language: 'de-DE' }).stt.model, 'onnx-community/whisper-tiny');
  assert.equal(lv.recommend({ memoryGB: 4, cores: 2 }).tts.dtype, 'q8');
});

test('only approved model repositories and the pinned runtime can be fetched', () => {
  assert.ok(lv.source('/hf/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/onnx/model_quantized.onnx'));
  assert.ok(lv.source('/hf/onnx-community/whisper-base.en/resolve/main/config.json'));
  assert.equal(lv.source('/hf/someone/else/resolve/main/model.onnx'), null);
  assert.equal(lv.source('/hf/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/../../x'), null);
  assert.equal(lv.source('/ort/evil.wasm'), null);
  assert.equal(lv.source('/ort/ort-wasm-simd-threaded.jsep.wasm').sha256, lv.RUNTIME['ort-wasm-simd-threaded.jsep.wasm']);
});

test('downloads once, caches, and rejects a runtime file with the wrong checksum', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'ogb-lv-'));
  let calls = 0;
  const store = lv.createStore({ root, fetchImpl: async () => { calls++; return { ok: true, status: 200, arrayBuffer: async () => new TextEncoder().encode('{"a":1}').buffer }; } });
  const first = await store.file('/hf/onnx-community/whisper-tiny.en/resolve/main/config.json');
  const second = await store.file('/hf/onnx-community/whisper-tiny.en/resolve/main/config.json');
  assert.equal(first.status, 200); assert.equal(second.body.toString(), '{"a":1}'); assert.equal(calls, 1);
  assert.equal(second.type, 'application/json');
  await assert.rejects(store.file('/ort/ort-wasm-simd-threaded.jsep.mjs'), /checksum/);
  assert.equal((await store.file('/hf/x/y/resolve/main/z.onnx')).status, 404);
  assert.deepEqual((await store.installed()).models, ['onnx-community/whisper-tiny.en']);
  await fs.rm(root, { recursive: true, force: true });
});
