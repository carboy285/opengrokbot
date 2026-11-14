const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const canvas = require('./canvas.cjs');

test('file names lose directories, dots and control characters, and gain an extension from the language', () => {
  assert.equal(canvas.safeName('notes.md'), 'notes.md');
  assert.equal(canvas.safeName('../../etc/passwd', 'python'), 'passwd.py');
  assert.equal(canvas.safeName('C:\\Windows\\hosts'), 'hosts.txt');
  assert.equal(canvas.safeName('.bashrc', 'bash'), 'bashrc.sh');
  assert.equal(canvas.safeName('', 'js'), 'canvas.js');
  assert.equal(canvas.safeName('a\u0000b<c>.txt'), 'abc.txt');
  assert.equal(canvas.safeName('setup.exe'), null);
  assert.equal(canvas.safeName('x.ps1'), null);
  assert.equal(canvas.safeName('weird.extension-too-long'), null);
});

test('saving stays inside the folder, never overwrites, and refuses huge files', async () => {
  const dir = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'canvas-')), 'bot');
  assert.equal(await canvas.save(dir, 'plan.md', 'one'), 'plan.md');
  assert.equal(await canvas.save(dir, 'plan.md', 'two'), 'plan (2).md');
  assert.equal(fs.readFileSync(path.join(dir, 'plan.md'), 'utf8'), 'one');
  assert.equal(await canvas.save(dir, '../../escape.txt', 'x'), 'escape.txt');
  assert.deepEqual(fs.readdirSync(dir).sort(), ['escape.txt', 'plan (2).md', 'plan.md']);
  assert.equal(fs.existsSync(path.join(dir, '..', 'escape.txt')), false);
  await assert.rejects(canvas.save(dir, 'big.txt', 'x'.repeat(canvas.MAX_BYTES + 1)), /too large/);
  await assert.rejects(canvas.save(dir, 'run.exe', 'x'), /normal extension/);
  await assert.rejects(canvas.save(dir, 'a.txt', 42), /Nothing to save/);
});
