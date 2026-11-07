'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const bundle = require('./settings-bundle.cjs');

test('sanitize keeps only well-formed keys for known providers', () => {
  const clean = bundle.sanitize({ format: bundle.FORMAT, version: 1, sourceName: 'Bens-Mac\nx', cliKeys: { codex: 'sk-abcdef123', claude: 'short', evil: 'sk-abcdef123', grok: 'has space here' }, voiceKeys: { groq: 'gsk_abcdef123', unknown: 'abcdefgh1', gemini: '   ' },
    composio: { key: 'ck_abcdef', userID: 'opengrokbot-1234-abcd', toolkits: ['gmail', 'Bad Slug', 'notion'] } });
  assert.deepEqual(clean.cliKeys, { codex: 'sk-abcdef123' });
  assert.deepEqual(clean.voiceKeys, { groq: 'gsk_abcdef123' });
  assert.deepEqual(clean.composio, { key: 'ck_abcdef', userID: 'opengrokbot-1234-abcd', toolkits: ['gmail', 'notion'] });
  assert.equal(clean.sourceName, 'Bens-Mac x');
  assert.match(bundle.summary(clean), /1 AI provider key, 1 voice key, connectors \(2 apps\)/);
  assert.ok(!bundle.summary(clean).includes('sk-abcdef123'));
});

test('sanitize rejects other formats, bad connectors and empties', () => {
  assert.throws(() => bundle.sanitize({ format: 'x' }), /not a settings bundle/);
  const clean = bundle.sanitize({ format: bundle.FORMAT, version: 1, composio: { key: 'has space', userID: 'x', toolkits: [] } });
  assert.equal(clean.composio, undefined);
  assert.ok(bundle.isEmpty(clean));
  assert.equal(bundle.summary(clean), 'nothing');
});
