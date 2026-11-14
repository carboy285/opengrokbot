const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const plugins = require('./plugins.cjs');

function folder(name, manifest, code = "module.exports={async run(a,args){return a+':'+JSON.stringify(args)}}") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'plugins-'));
  fs.mkdirSync(path.join(root, name));
  fs.writeFileSync(path.join(root, name, 'plugin.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(root, name, 'index.cjs'), code);
  return root;
}
const good = { name: 'weather', version: '1.0', description: 'Weather', actions: [{ name: 'forecast', description: 'Get a forecast' }, { name: 'radar', description: 'Open radar', approval: false }] };

test('manifests must match their folder and have valid, unique actions', () => {
  assert.ok(plugins.readManifest(good, 'weather'));
  assert.equal(plugins.readManifest(good, 'other'), null);
  assert.equal(plugins.readManifest({ ...good, name: '../x' }, '../x'), null);
  assert.equal(plugins.readManifest({ ...good, actions: [] }, 'weather'), null);
  assert.equal(plugins.readManifest({ ...good, actions: [{ name: 'a_b' }, { name: 'a_b' }] }, 'weather'), null);
  assert.equal(plugins.readManifest({ ...good, actions: [{ name: 'Bad Name' }] }, 'weather'), null);
  assert.equal(plugins.readManifest({ ...good, actions: Array.from({ length: 21 }, (_, i) => ({ name: 'act_' + i })) }, 'weather'), null);
  assert.equal(plugins.readManifest(good, 'weather').actions[0].approval, true, 'actions ask first unless the manifest opts out');
});

test('nothing loads unless its name is allowed, and broken plugins are reported, not thrown', () => {
  const root = folder('weather', good);
  assert.equal(plugins.load(root, []).plugins.size, 0);
  assert.equal(plugins.load(root, undefined).plugins.size, 0);
  assert.equal(plugins.load(root, ['../../etc']).plugins.size, 0);
  assert.equal(plugins.load(root, ['weather']).plugins.size, 1);
  const missing = plugins.load(root, ['nope']);
  assert.equal(missing.plugins.size, 0); assert.equal(missing.problems.length, 1);
  const broken = folder('weather', good, 'module.exports={}');
  assert.match(plugins.load(broken, ['weather']).problems[0], /must export run/);
  const bad = folder('weather', { name: 'weather' });
  assert.match(plugins.load(bad, ['weather']).problems[0], /not valid/);
});

test('the Bot is told about loaded plugins and which actions ask first', () => {
  const registry = plugins.load(folder('weather', good), ['weather']);
  const text = plugins.note(registry);
  assert.match(text, /weather\.forecast \(asks the human first\)/);
  assert.match(text, /weather\.radar: Open radar/);
  assert.equal(plugins.note(plugins.load(folder('weather', good), [])), '');
});

test('actions that ask are skipped unattended, declined, or run after approval; results are bounded and untrusted', async () => {
  const registry = plugins.load(folder('weather', good), ['weather']);
  const asked = [];
  const ctx = (approved, unattended = false) => ({ botID: 'b', botName: 'Bot', unattended, approve: async (...x) => { asked.push(x); return approved; } });
  assert.match(await plugins.run(registry, { plugin: 'weather', name: 'forecast', arguments: { city: 'Oslo' } }, ctx(true, true)), /unattended/);
  assert.equal(asked.length, 0);
  assert.match(await plugins.run(registry, { plugin: 'weather', name: 'forecast' }, ctx(false)), /declined/);
  const ok = await plugins.run(registry, { plugin: 'weather', name: 'forecast', arguments: { city: 'Oslo' } }, ctx(true));
  assert.match(ok, /untrusted/); assert.match(ok, /forecast:\{"city":"Oslo"\}/);
  assert.equal(asked.length, 2);
  asked.length = 0;
  assert.match(await plugins.run(registry, { plugin: 'weather', name: 'radar' }, ctx(false)), /radar:\{\}/);
  assert.equal(asked.length, 0, 'approval: false skips the prompt');
  assert.match(await plugins.run(registry, { plugin: 'weather', name: 'nope' }, ctx(true)), /not installed/);
  assert.match(await plugins.run(registry, { plugin: 'other', name: 'x' }, ctx(true)), /not installed/);
  assert.match(await plugins.run(registry, { plugin: 'weather', name: 'radar', arguments: { x: 'y'.repeat(30000) } }, ctx(true)), /too large/);
});

test('a plugin that throws or returns a huge answer cannot break the app', async () => {
  const boom = plugins.load(folder('weather', good, "module.exports={async run(){throw new Error('secret path /home/x')}}"), ['weather']);
  assert.match(await plugins.run(boom, { plugin: 'weather', name: 'radar' }, { botName: 'B', approve: async () => true }), /failed: secret path/);
  const big = plugins.load(folder('weather', good, "module.exports={run(){return 'x'.repeat(50000)}}"), ['weather']);
  const text = await plugins.run(big, { plugin: 'weather', name: 'radar' }, { botName: 'B', approve: async () => true });
  assert.ok(text.length < 12200);
});
