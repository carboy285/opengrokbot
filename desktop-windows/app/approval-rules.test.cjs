const test = require('node:test');
const assert = require('node:assert/strict');
const { sanitize, decide, MAX_RULES } = require('./approval-rules.cjs');

test('rules keep only always-ask rules for known tools, once each', () => {
  const clean = sanitize({ enabled: true, rules: [
    { kind: 'ask', tool: 'browser_click', pattern: ' shop.example ' },
    { kind: 'ask', tool: 'browser_click', pattern: 'SHOP.example' },
    { kind: 'allow', tool: 'browser_click', pattern: 'x' },
    { kind: 'ask', tool: 'secure_login', pattern: '' },
    { kind: 'ask', tool: 'browser_click', pattern: 'a'.repeat(300) },
    null, 'bad'
  ] });
  assert.equal(clean.rules.length, 2);
  assert.equal(clean.rules[0].pattern, 'shop.example');
  assert.equal(clean.rules[1].pattern.length, 120);
  assert.ok(clean.rules.every(rule => rule.kind === 'ask' && rule.id));
  assert.equal(sanitize(undefined).enabled, true);
  assert.deepEqual(sanitize({ enabled: false, rules: [] }), { enabled: false, rules: [] });
});

test('an always-ask rule matches the page address and turning rules off ignores them', () => {
  const config = { enabled: true, rules: [{ kind: 'ask', tool: 'browser_click', pattern: 'shop.example' }, { kind: 'ask', tool: 'browser_click', pattern: '' }] };
  assert.equal(decide({ enabled: true, rules: [config.rules[0]] }, 'browser_click', 'www.Shop.example.com'), 'ask');
  assert.equal(decide({ enabled: true, rules: [config.rules[0]] }, 'browser_click', 'news.example.com'), 'noRule');
  assert.equal(decide({ enabled: true, rules: [config.rules[1]] }, 'browser_click', 'anything'), 'ask');
  assert.equal(decide({ ...config, enabled: false }, 'browser_click', 'shop.example.com'), 'noRule');
  assert.equal(decide(config, 'secure_login', 'shop.example.com'), 'noRule');
});

test('there is a cap on the number of rules', () => {
  const rules = Array.from({ length: MAX_RULES + 20 }, (_, i) => ({ kind: 'ask', tool: 'browser_click', pattern: `site${i}.example` }));
  assert.equal(sanitize({ rules }).rules.length, MAX_RULES);
});
