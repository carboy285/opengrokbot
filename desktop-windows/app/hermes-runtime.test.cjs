const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { mkdtemp, rm, writeFile } = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { HermesRuntime } = require('./hermes-runtime.cjs');

test('each bot starts in its own home with a fresh gateway key and no inherited bypass settings', async t => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'hermes-runtime-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const executable = path.join(root, 'hermes'); await writeFile(executable, 'fixture');
  const children = [], launches = [];
  const runtime = new HermesRuntime({ executable, dataDirectory: path.join(root, 'bots'),
    spawnImpl: (file, args, options) => { launches.push({ file, args, options }); const child = new EventEmitter(); child.kill = () => { child.killed = true; child.emit('exit', 0); }; children.push(child); return child; },
    fetchImpl: async () => Response.json({ status: 'ok' }) });
  const first = 'ba14c93b-1cb6-46f9-a0d6-6cf153eb4949', second = 'ba14c93b-1cb6-46f9-a0d6-6cf153eb4950';
  const [a, same] = await Promise.all([runtime.start(first), runtime.start(first)]);
  assert.equal(a, same); assert.equal(launches.length, 1);
  await runtime.start(second);
  assert.equal(launches.length, 2);
  assert.notEqual(launches[0].options.env.HERMES_HOME, launches[1].options.env.HERMES_HOME);
  assert.notEqual(launches[0].options.env.API_SERVER_KEY, launches[1].options.env.API_SERVER_KEY);
  assert.equal(launches[0].options.env.API_SERVER_HOST, '127.0.0.1');
  assert.equal(launches[0].options.env.HERMES_YOLO_MODE, undefined);
  assert.equal(launches[0].options.env.HERMES_ACCEPT_HOOKS, undefined);
  assert.equal(launches[0].options.shell, false);
  await runtime.stopAll(); assert.ok(children.every(child => child.killed));
});
