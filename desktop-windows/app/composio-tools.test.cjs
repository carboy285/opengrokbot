const test = require('node:test');
const assert = require('node:assert/strict');
const tools = require('./composio-tools.cjs');

const json = body => new Response(JSON.stringify(body));

test('composio_find lists matching tools in connected apps, with required fields marked', async () => {
  const urls = [];
  const fetcher = async url => { urls.push(String(url)); return json({ items: [{ slug: 'GMAIL_SEND_EMAIL', name: 'Send email', description: 'Send an email', input_parameters: { properties: { recipient_email: { type: 'string', description: 'Who gets it' }, body: { type: 'string' } }, required: ['recipient_email'] } }, { slug: 'bad slug!' }] }); };
  const found = await tools.find({ key: 'k', toolkits: ['gmail'], query: 'send an email', fetcher });
  assert.match(urls[0], /toolkit_slug=gmail&search=send%20an%20email/);
  assert.deepEqual(found, [{ tool: 'GMAIL_SEND_EMAIL', app: 'gmail', about: 'Send an email', changes: true, fields: ['recipient_email*: string — Who gets it', 'body: string'] }]);
  await assert.rejects(tools.find({ key: 'k', toolkits: [], query: 'x', fetcher }), /No apps are connected/);
});

test('reading runs without asking; anything that changes data asks first and a no stops it', async () => {
  const calls = [];
  const fetcher = async (url, options) => { calls.push({ url: String(url), body: JSON.parse(options.body) }); return json({ successful: true, data: { messages: [{ subject: 'Hi' }] } }); };
  const asked = [];
  const read = await tools.run({ key: 'k', userID: 'u', toolkits: ['gmail'], tool: 'GMAIL_FETCH_EMAILS', args: { max_results: 2 }, approve: async (...a) => { asked.push(a); return true; }, fetcher });
  assert.equal(asked.length, 0);
  assert.match(read.text, /"subject":"Hi"/);
  assert.deepEqual(calls[0].body, { user_id: 'u', arguments: { max_results: 2 }, version: 'latest' });
  const no = await tools.run({ key: 'k', userID: 'u', toolkits: ['gmail'], tool: 'GMAIL_SEND_EMAIL', args: { recipient_email: 'a@b.c' }, botName: 'Grok Bot', approve: async (title, detail) => { asked.push([title, detail]); return false; }, fetcher });
  assert.equal(no.declined, true);
  assert.equal(calls.length, 1, 'a declined write never reaches Composio');
  assert.match(asked[0][0], /Let Grok Bot use gmail send email\?/);
  assert.match(asked[0][1], /a@b\.c/);
  assert.equal(tools.isWrite('GOOGLECALENDAR_CREATE_EVENT'), true);
  assert.equal(tools.isWrite('GOOGLECALENDAR_EVENTS_LIST'), false);
});

test('tools outside connected apps and malformed names are refused', async () => {
  const fetcher = async () => { throw new Error('should not be called'); };
  await assert.rejects(tools.run({ key: 'k', userID: 'u', toolkits: ['gmail'], tool: 'SLACK_SEND_MESSAGE', args: {}, approve: async () => true, fetcher }), /not in a connected app/);
  await assert.rejects(tools.run({ key: 'k', userID: 'u', toolkits: ['gmail'], tool: 'gmail send', args: {}, approve: async () => true, fetcher }), /exact tool name/);
  const failed = async () => json({ successful: false, error: 'Missing recipient' });
  await assert.rejects(tools.run({ key: 'k', userID: 'u', toolkits: ['gmail'], tool: 'GMAIL_FETCH_EMAILS', args: {}, approve: async () => true, fetcher: failed }), /did not succeed: Missing recipient/);
});
