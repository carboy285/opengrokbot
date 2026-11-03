'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, readdir, readFile, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { saveRemoteImages, attachmentMessage } = require('./attachments.cjs');

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]);

test('stores valid images in the Attachments folder', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'grok-att-'));
  try {
    const names = await saveRemoteImages(dir, [{ name: 'a.jpg', mime: 'image/jpeg', data: jpeg.toString('base64') }, { name: 'b.png', mime: 'image/png', data: png.toString('base64') }]);
    assert.equal(names.length, 2);
    assert.deepEqual((await readdir(path.join(dir, 'Attachments'))).sort(), [...names].sort());
    assert.deepEqual(await readFile(path.join(dir, 'Attachments', names[0])), jpeg);
    assert.match(names[0], /^[0-9a-f-]{36}-Photo\.jpg$/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('rejects wrong types, fake image bytes, and too many files', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'grok-att-'));
  try {
    await assert.rejects(saveRemoteImages(dir, [{ mime: 'text/html', data: jpeg.toString('base64') }]));
    await assert.rejects(saveRemoteImages(dir, [{ mime: 'image/png', data: jpeg.toString('base64') }]));
    await assert.rejects(saveRemoteImages(dir, [{ mime: 'image/jpeg', data: Buffer.from('not an image').toString('base64') }]));
    await assert.rejects(saveRemoteImages(dir, Array(4).fill({ mime: 'image/jpeg', data: jpeg.toString('base64') })));
    assert.deepEqual(await saveRemoteImages(dir, undefined), []);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('builds the CLI message with file paths', () => {
  assert.equal(attachmentMessage('hi', []), 'hi');
  const message = attachmentMessage('', ['x-Photo.jpg']);
  assert.match(message, /^Please review the attached files\./);
  assert.match(message, /- Attachments\/x-Photo\.jpg/);
});

test('copies local files, saves pasted images, and validates stored names', async () => {
  const { copyLocalFiles, saveDataFile, existingNames } = require('./attachments.cjs');
  const { writeFile, mkdir } = require('node:fs/promises');
  const dir = await mkdtemp(path.join(os.tmpdir(), 'grok-att-'));
  try {
    const source = path.join(dir, 'my notes.txt');
    await writeFile(source, 'hello');
    const [copied] = await copyLocalFiles(dir, [source]);
    assert.match(copied, /^[0-9a-f-]{36}-my notes\.txt$/);
    assert.equal(await readFile(path.join(dir, 'Attachments', copied), 'utf8'), 'hello');
    await assert.rejects(copyLocalFiles(dir, [dir]), /regular files/);
    await assert.rejects(copyLocalFiles(dir, []));
    const pasted = await saveDataFile(dir, 'image/png', png.toString('base64'));
    assert.match(pasted, /-Pasted image\.png$/);
    await assert.rejects(saveDataFile(dir, 'text/html', 'aGk='), /Unsupported/);
    assert.deepEqual(await existingNames(dir, [copied, pasted]), [copied, pasted]);
    assert.deepEqual(await existingNames(dir, undefined), []);
    await assert.rejects(existingNames(dir, ['../secret']), /Invalid/);
    await assert.rejects(existingNames(dir, ['00000000-0000-0000-0000-000000000000-missing.txt']));
    await mkdir(path.join(dir, 'Attachments', '11111111-1111-1111-1111-111111111111-dir'));
    await assert.rejects(existingNames(dir, ['11111111-1111-1111-1111-111111111111-dir']), /Missing/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
