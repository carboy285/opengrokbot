const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateWorkspace, previewWorkspace } = require('./workspace.cjs');

test('preview fixtures are valid and contain no live connection state', () => {
  const value = previewWorkspace();
  assert.equal(validateWorkspace(value), value);
  assert.equal(value.bots.length, 5);
  assert.equal(value.connected, undefined);
  assert.notEqual(value.bots[0].id, previewWorkspace().bots[0].id);
});
test('reject duplicate identifiers, orphan messages, unknown kinds and oversized notes', () => {
  for (const mutate of [
    x => x.bots.push(x.bots[0]),
    x => x.entries[0].botID = 'missing',
    x => x.entries[0].kind = 'executed',
    x => x.entries[0].text = 'x'.repeat(100001),
    x => x.bots[0].name = '',
    x => x.bots[0].color = 'invalid'
  ]) {
    const value = previewWorkspace(); mutate(value);
    assert.throws(() => validateWorkspace(value));
  }
});
