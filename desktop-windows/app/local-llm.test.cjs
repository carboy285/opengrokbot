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

test('Ollama manager lists, downloads with progress and picks a quick voice model', async () => {
  const fetchImpl = async (url, options = {}) => {
    if (url.endsWith('/api/tags')) return { ok: true, json: async () => ({ models: [{ name: 'llama3.1:8b', size: 5e9 }, { name: 'qwen3:4b', size: 2.6e9 }, { name: 'bad name!', size: 1 }] }) };
    if (url.endsWith('/api/pull')) return { ok: true, body: (async function* () { yield new TextEncoder().encode('{"status":"pulling","completed":5,"total":10}\n{"status":"success"}\n'); })() };
    return { ok: true };
  };
  const models = await llm.ollamaModels(undefined, { fetchImpl });
  assert.deepEqual(models.map(m => m.name), ['llama3.1:8b', 'qwen3:4b']);
  assert.equal(llm.voicePick(models), 'qwen3:4b');
  const seen = []; await llm.ollamaPull(undefined, 'llama3.2:3b', { fetchImpl, onProgress: p => seen.push(p.status) });
  assert.deepEqual(seen, ['pulling', 'success']);
  await assert.rejects(llm.ollamaPull(undefined, 'rm -rf /', { fetchImpl }), /valid model name/);
});

test('local models get one native tool; streamed tool calls become app action blocks', async () => {
  const sse = lines => new Response(lines.map(x => 'data: ' + JSON.stringify(x) + '\n').join('') + 'data: [DONE]\n', { headers: { 'content-type': 'text/event-stream' } });
  const bodies = [];
  const fetchImpl = async (url, options) => {
    bodies.push(JSON.parse(options.body));
    return sse([
      { choices: [{ delta: { content: 'Adding it now.' } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { name: 'app_action', arguments: '{"action":"apple_add_re' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: 'minder","text":"Call the plumber"}' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 1, function: { name: 'something_else', arguments: '{"action":"x"}' } }] } }] }
    ]);
  };
  const events = [];
  const text = await llm.run({ provider: 'ollama', base: 'http://127.0.0.1:11434', prompt: 'remind me', model: 'qwen3:8b', fetchImpl, onEvent: e => events.push(e) }).done;
  assert.equal(bodies[0].tools[0].function.name, 'app_action');
  assert.equal(text, 'Adding it now.\n```opengrokbot-action\n{"action":"apple_add_reminder","text":"Call the plumber"}\n```');
  assert.equal(events.at(-1).text, text, 'the final text with the action block is shown');
  assert.equal(llm.actionBlocks([{ name: 'app_action', arguments: '{"action":"Bad Action!"}' }, { name: 'app_action', arguments: 'not json' }]), '');
});

test('a model without tool support is asked again without tools', async () => {
  const bodies = [];
  const fetchImpl = async (url, options) => {
    const body = JSON.parse(options.body); bodies.push(body);
    if (body.tools) return new Response('{"error":"registry.ollama.ai/library/gemma3 does not support tools"}', { status: 400 });
    return new Response('data: {"choices":[{"delta":{"content":"Plain answer"}}]}\ndata: [DONE]\n');
  };
  assert.equal(await llm.run({ provider: 'ollama', base: 'http://127.0.0.1:11434', prompt: 'hi', model: 'gemma3:4b', fetchImpl }).done, 'Plain answer');
  assert.equal(bodies.length, 2);
  assert.equal(bodies[1].tools, undefined);
});
