const test = require('node:test');
const assert = require('node:assert/strict');
const modes = require('./answer-modes.cjs');
const teamwork = require('./teamwork.cjs');

test('only known modes are accepted and each adds its own instructions', () => {
  assert.equal(modes.normalize('think'), 'think');
  assert.equal(modes.normalize('deep'), 'deep');
  for (const bad of ['', 'THINK', '__proto__', 'constructor', null, 7, {}]) assert.equal(modes.normalize(bad), null);
  assert.match(modes.noteFor('think'), /step by step/);
  assert.match(modes.noteFor('deep'), /search_web/);
  assert.equal(modes.noteFor('nope'), '');
});

test('numbered sources match the numbers the Bot is told to cite', () => {
  const text = modes.numbered([{ title: 'A', url: 'https://a.example/', snippet: 'one' }, { title: 'B', url: 'https://b.example/', snippet: '' }]);
  assert.equal(text, '1. A — https://a.example/ — one\n2. B — https://b.example/');
  assert.match(modes.CITATION_RULE, /\[1\]/);
});

test('every Bot is told to cite web and feed sources', () => {
  const state = { bots: [{ id: 'b1', name: 'Grok Bot', purpose: 'Helps' }], sharedMemory: [] };
  const text = teamwork.instructions(state.bots[0], state, false, []);
  assert.match(text, /Citations:/);
  assert.match(text, /read_feed/);
});
