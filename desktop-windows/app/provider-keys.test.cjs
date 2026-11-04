'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { normalized, environmentFor, PROVIDERS, VARIABLES } = require('./provider-keys.cjs');
const { command } = require('./local-cli.cjs');

test('keys are trimmed and bad pastes are rejected', () => {
  assert.equal(normalized('  sk-ant-abcdef123456\n'), 'sk-ant-abcdef123456');
  for (const bad of ['short', 'two words in a key', 'sk-abcdef\n123456', 'sk-abcdef123456🔑', '', null, 'x'.repeat(513)]) assert.equal(normalized(bad), null, String(bad));
});

test('each CLI gets only its own variables, and nothing without a key', () => {
  assert.deepEqual(environmentFor('claude', 'sk-ant-1234567890'), { ANTHROPIC_API_KEY: 'sk-ant-1234567890' });
  assert.deepEqual(environmentFor('codex', 'sk-1234567890'), { CODEX_API_KEY: 'sk-1234567890', OPENAI_API_KEY: 'sk-1234567890' });
  assert.deepEqual(environmentFor('grok', 'xai-1234567890'), { XAI_API_KEY: 'xai-1234567890' });
  assert.deepEqual(environmentFor('gemini', 'AIza1234567890'), { GEMINI_API_KEY: 'AIza1234567890' });
  assert.deepEqual(environmentFor('opencode', 'whatever-key-123'), {});
  assert.deepEqual(environmentFor('claude', ''), {});
  assert.ok(PROVIDERS.has('codex') && !PROVIDERS.has('opencode'));
  assert.equal(Object.keys(VARIABLES).length, 4);
});

test('a key never appears in the CLI arguments', () => {
  for (const id of PROVIDERS) assert.ok(!command(id, 'session-1', '/tmp/prompt.txt', 'model-x').some(arg => /sk-|xai-|AIza/.test(arg)));
});
