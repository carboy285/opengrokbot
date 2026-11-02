const test = require('node:test');
const assert = require('node:assert/strict');
const { HermesGateway } = require('./hermes-gateway.cjs');
const bot = 'ba14c93b-1cb6-46f9-a0d6-6cf153eb4949';
const requestID = 'ba14c93b-1cb6-46f9-a0d6-6cf153eb4950';

test('Hermes requests use a local authenticated endpoint, bot session, and stable retry key', async () => {
  const calls = [];
  const client = new HermesGateway({ port: 8642, key: 'a'.repeat(32), fetchImpl: async (url, init) => { calls.push({ url, init }); return Response.json({ run_id: 'run_abc123' }); } });
  assert.equal(await client.start({ botID: bot, input: 'private message', requestID }), 'run_abc123');
  assert.equal(calls[0].url, 'http://127.0.0.1:8642/v1/runs');
  assert.equal(calls[0].init.headers['X-Hermes-Session-Key'], `opengrokbot-${bot}`);
  assert.equal(calls[0].init.headers['Idempotency-Key'], requestID);
  assert.equal(JSON.parse(calls[0].init.body).input, 'private message');
  assert.equal(calls[0].init.redirect, 'error');
});

test('Hermes streaming handles split frames and rejects events from another run', async () => {
  const frames = [': open\n\ndata: {"event":"message.delta",', '"run_id":"run_abc","delta":"Hello"}\n\n', 'data: {"event":"run.completed","run_id":"run_abc"}\n\n'];
  const stream = () => new ReadableStream({ start(controller) { for (const f of frames) controller.enqueue(new TextEncoder().encode(f)); controller.close(); } });
  const client = new HermesGateway({ port: 8642, key: 'a'.repeat(32), fetchImpl: async () => new Response(stream()) });
  const received = []; await client.events('run_abc', event => received.push(event));
  assert.deepEqual(received.map(x => x.event), ['message.delta', 'run.completed']);
  await assert.rejects(client.events('run_other', () => {}), /another run/);
});

test('approval is explicit and limited to a single request; errors do not expose server content', async () => {
  let body;
  const client = new HermesGateway({ port: 8642, key: 'a'.repeat(32), fetchImpl: async (_, options) => { body = JSON.parse(options.body); return Response.json({ ok: true }); } });
  await client.approve('run_abc', 'request-1', 'deny');
  assert.deepEqual(body, { request_id: 'request-1', choice: 'deny' });
  await assert.rejects(client.approve('run_abc', 'request-1', 'always'), /Invalid approval/);
  const failed = new HermesGateway({ port: 8642, key: 'a'.repeat(32), fetchImpl: async () => new Response('secret server detail', { status: 500 }) });
  await assert.rejects(failed.status('run_abc'), error => !error.message.includes('secret'));
});

test('a bot profile is addressed explicitly and unsafe profile paths are refused', async () => {
  let target;
  const client = new HermesGateway({ port: 8642, key: 'a'.repeat(32), profile: 'bot_123', fetchImpl: async url => { target = url; return Response.json({ status: 'running' }); } });
  await client.status('run_abc');
  assert.equal(target, 'http://127.0.0.1:8642/p/bot_123/v1/runs/run_abc');
  assert.throws(() => new HermesGateway({ port: 8642, key: 'a'.repeat(32), profile: '../other' }), /Invalid Hermes profile/);
});
