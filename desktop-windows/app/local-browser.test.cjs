'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, readdir, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
// local-browser.cjs imports electron at load time; stub it so the pure helpers can be tested under plain Node.
const Module = require('node:module');
const original = Module._load;
Module._load = function (request, ...rest) { return request === 'electron' ? {} : original.call(this, request, ...rest); };
const { settle, captureView } = require('./local-browser.cjs');
Module._load = original;

const image = (width, empty = false) => ({ isEmpty: () => empty, getSize: () => ({ width, height: 600 }), resize(o) { return image(o.width); }, toJPEG: () => jpeg, width });

test('settle returns once the page is loaded and its text stops changing', async () => {
  let calls = 0;
  const web = { isLoading: () => false, executeJavaScript: async () => `complete|${calls++ < 2 ? 100 + calls : 500}` };
  await settle(web, { interval: 1, limit: 2000 });
  assert.ok(calls >= 4 && calls < 20);
});

test('settle gives up at the limit for a page that never stops changing, and tolerates script errors', async () => {
  let n = 0;
  const started = Date.now();
  await settle({ isLoading: () => false, executeJavaScript: async () => `complete|${n++}` }, { interval: 5, limit: 60 });
  assert.ok(Date.now() - started < 1000);
  await settle({ isLoading: () => false, executeJavaScript: async () => { throw new Error('gone'); } }, { interval: 1, limit: 50 });
});

test('captureView stores a JPEG screenshot and reports a relative path', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'grok-shot-'));
  try {
    const result = await captureView({ capturePage: async () => image(1800) }, dir);
    assert.match(result.path, /^Attachments\/[0-9a-f-]{36}-Page\.jpg$/);
    assert.equal((await readdir(path.join(dir, 'Attachments'))).length, 1);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('captureView returns an error, never throws, for empty or failed captures', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'grok-shot-'));
  try {
    assert.match((await captureView({ capturePage: async () => image(100, true) }, dir)).error, /nothing to capture/);
    assert.match((await captureView({ capturePage: async () => { throw new Error('x'); } }, dir)).error, /could not be captured/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
