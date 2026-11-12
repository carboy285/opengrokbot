const test = require('node:test'), assert = require('node:assert/strict');
const llm = require('./local-llm.cjs');

test('only local and private-network servers are accepted', () => {
  assert.equal(llm.serverURL('http://127.0.0.1:11434/v1'), 'http://127.0.0.1:11434');
  assert.equal(llm.serverURL('http://localhost:1234'), 'http://localhost:1234');
  assert.equal(llm.serverURL('http://192.168.1.20:11434'), 'http://192.168.1.20:11434');
  assert.equal(llm.serverURL('http://studio.local:1234'), 'http://studio.local:1234');
  assert.equal(llm.serverURL('https://api.example.com'), null);
  assert.equal(llm.serverURL('http://user:pw@127.0.0.1:1'), null);
  assert.equal(llm.serverURL('file:///etc/passwd'), null);
});

test('reasoning blocks are hidden from the chat', () => {
  assert.equal(llm.visibleText('<think>plan</think>\n\nHello'), 'Hello');
  assert.equal(llm.visibleText('<think>still thinking'), '');
});

const stream = lines => ({ ok: true, body: (async function* () { for (const line of lines) yield new TextEncoder().encode(line); })() });

test('streams an OpenAI-compatible reply and picks the first model when none is chosen', async () => {
  const calls = [];
  const fetchImpl = async (url, options = {}) => {
    calls.push([url, options.body && JSON.parse(options.body)]);
    if (url.endsWith('/v1/models')) return { ok: true, json: async () => ({ data: [{ id: 'llama3.2' }] }) };
    return stream(['data: {"choices":[{"delta":{"content":"Hi"}}]}\n', 'data: {"choices":[{"delta":{"content":" there"}}]}\n\ndata: [DONE]\n']);
  };
  const seen = [];
  const text = await llm.run({ provider: 'ollama', prompt: 'Say hi', fetchImpl, onEvent: e => seen.push(e.text) }).done;
  assert.equal(text, 'Hi there');
  assert.deepEqual(seen, ['Hi', 'Hi there']);
  assert.equal(calls[1][1].model, 'llama3.2');
  assert.equal(calls[1][1].messages[0].content, 'Say hi');
});

test('explains a stopped server and an empty model list', async () => {
  await assert.rejects(llm.run({ provider: 'lmstudio', prompt: 'x', fetchImpl: async () => { throw new Error('ECONNREFUSED'); } }).done, /LM Studio isn’t running/);
  await assert.rejects(llm.run({ provider: 'ollama', prompt: 'x', fetchImpl: async () => ({ ok: true, json: async () => ({ data: [] }) }) }).done, /no models yet/);
});
