'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { encryptBackup, decryptBackup } = require('./backup.cjs');

const workspace = { version: 2, bots: [{ id: 'a', name: 'Grok Bot', isMain: true }], entries: [{ id: 'e', text: 'secret note 🌎' }] };

test('round-trips a workspace and hides its contents', () => {
  const text = encryptBackup(workspace, 'correct horse');
  assert.equal(text.includes('secret note'), false);
  const envelope = JSON.parse(text);
  assert.equal(envelope.format, 'opengrokbot-backup');
  assert.equal(envelope.platform, 'windows');
  assert.deepEqual(decryptBackup(text, 'correct horse'), { platform: 'windows', workspace });
});

test('rejects wrong passwords, tampering, short passwords and other files', () => {
  const text = encryptBackup(workspace, 'correct horse');
  assert.throws(() => decryptBackup(text, 'wrong horse'), /Wrong password/);
  const envelope = JSON.parse(text);
  const body = Buffer.from(envelope.ciphertext, 'base64'); body[0] ^= 1;
  assert.throws(() => decryptBackup(JSON.stringify({ ...envelope, ciphertext: body.toString('base64') }), 'correct horse'), /Wrong password/);
  assert.throws(() => decryptBackup(JSON.stringify({ ...envelope, iterations: 10 }), 'correct horse'), /unsupported/);
  assert.throws(() => encryptBackup(workspace, 'short'), /8 characters/);
  assert.throws(() => decryptBackup('{"hello":1}', 'x'), /not an OpenGrokBot backup/);
  assert.throws(() => decryptBackup('not json', 'x'), /not an OpenGrokBot backup/);
});
