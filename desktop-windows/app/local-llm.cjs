// Self-hosted models (0.9.3): Ollama and LM Studio both serve an OpenAI-compatible API on this computer.
// A Bot that uses one gets the same prompt a CLI would (instructions + recent chat), streamed back over HTTP.
// Only loopback and private-network addresses are accepted, so a Bot's chat never goes to an arbitrary host.
const SERVERS = {
  ollama: { name: 'Ollama', url: 'http://127.0.0.1:11434', guide: 'https://ollama.com/download', pull: 'ollama pull llama3.2' },
  lmstudio: { name: 'LM Studio', url: 'http://127.0.0.1:1234', guide: 'https://lmstudio.ai/', pull: 'Load a model in LM Studio (Developer tab → Start server)' }
};

/** A server address: http(s) on localhost or a private network, no credentials, path ignored. */
function serverURL(value) {
  let url;
  try { url = new URL(String(value || '').trim()); } catch { return null; }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
  const host = url.hostname.replace(/^\[|\]$/g, '');
  const privateHost = host === 'localhost' || host === '::1' || host.endsWith('.local') || /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host)
    || /^172\.(1[6-9]|2\d|3[01])\./.test(host) || /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(host) || /^f[cd][0-9a-f]{2}:/i.test(host);
  return privateHost ? url.origin : null;
}

/** Removes the private reasoning some local models print before their answer. */
function visibleText(text) {
  return String(text || '').replace(/<think>[\s\S]*?(<\/think>|$)/g, '').replace(/^\s+/, '');
}

async function getJSON(url, fetchImpl, timeout) {
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), timeout);
  try { const response = await fetchImpl(url, { signal: controller.signal }); if (!response.ok) throw new Error('HTTP ' + response.status); return await response.json(); }
  finally { clearTimeout(timer); }
}

/** Model IDs the server offers, or null when nothing answers at that address. */
async function listModels(base, { fetchImpl = fetch, timeout = 2500 } = {}) {
  const origin = serverURL(base); if (!origin) return null;
  try {
    const value = await getJSON(origin + '/v1/models', fetchImpl, timeout);
    return (Array.isArray(value?.data) ? value.data : []).map(x => x?.id).filter(id => typeof id === 'string' && id.length <= 200).slice(0, 500);
  } catch { return null; }
}

function friendlyError(server, status, body) {
  if (status === 404 && /model/i.test(body)) return `That model isn’t available in ${server.name}. ${server.pull}, then choose it in the Bot’s side panel.`;
  if (status === 400 && /context|token/i.test(body)) return `The conversation is too long for this model’s context window. Start a new Bot or raise the context length in ${server.name}.`;
  return `${server.name} stopped with an error (HTTP ${status}). Check the model is loaded and try again.`;
}

/**
 * Tools for local models (0.9.7). One native tool, app_action, carries any operation the instructions describe.
 * A call is turned into the same opengrokbot-action block a CLI writes, so the app runs it exactly as it would
 * for a CLI: the same tools, the same approval cards, the same automatic continuation with the result.
 */
const APP_TOOL = {
  type: 'function',
  function: {
    name: 'app_action',
    description: 'Ask OpenGrokBot to do something for the human: any operation listed in your instructions, such as searching the web, reading a page, adding a reminder, scheduling a task, making an image, finding or running a connected-app tool, or messaging another Bot. Put the operation name in "action" and its fields next to it, exactly as the instructions show. The result comes back in the next turn.',
    parameters: {
      type: 'object',
      properties: {
        action: { type: 'string', description: 'The operation, for example search_web, browse_web, apple_add_reminder, schedule_task, generate_image, composio_find, composio_run, remember or message_bot.' },
        query: { type: 'string' }, url: { type: 'string' }, text: { type: 'string' }, prompt: { type: 'string' }, name: { type: 'string' },
        at: { type: 'string' }, to: { type: 'string' }, tool: { type: 'string' }, arguments: { type: 'object' }
      },
      required: ['action'],
      additionalProperties: true
    }
  }
};
/** Turns finished tool calls into action blocks. Calls that are not valid app actions are dropped. */
function actionBlocks(calls) {
  const fence = '```';
  return calls.map(call => {
    if (call.name && call.name !== 'app_action') return '';
    let value; try { value = typeof call.arguments === 'string' ? JSON.parse(call.arguments || '{}') : call.arguments; } catch { return ''; }
    if (!value || typeof value !== 'object' || Array.isArray(value) || typeof value.action !== 'string' || !/^[a-z_]{2,40}$/.test(value.action)) return '';
    const json = JSON.stringify(value); if (json.length > 16000) return '';
    return `\n${fence}opengrokbot-action\n${json}\n${fence}`;
  }).join('');
}

/** Same shape as a CLI run: { done: Promise<text>, cancel(immediately) }. Calls onEvent({type:'text', text}) as text streams in. */
function run({ provider, base, prompt, model = '', onEvent = () => {}, timeout = 600000, fetchImpl = fetch, maxTokens, tools = true }) {
  const server = SERVERS[provider];
  const controller = new AbortController();
  let cancelled = false, timedOut = false;
  const cancel = () => { cancelled = true; controller.abort(); };
  const done = (async () => {
    if (!server) throw new Error('Unknown local model server.');
    const origin = serverURL(base || server.url); if (!origin) throw new Error(`The ${server.name} address must be on this computer or your local network.`);
    let chosen = model;
    if (!chosen) {
      const models = await listModels(origin, { fetchImpl });
      if (models === null) throw new Error(`${server.name} isn’t running at ${origin}. Open ${server.name} and start its server, then retry.`);
      chosen = models[0];
      if (!chosen) throw new Error(`${server.name} has no models yet. ${server.pull}, then retry.`);
    }
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeout); timer.unref?.();
    let response, withTools = tools;
    const send = async () => {
      const body = { model: chosen, stream: true, messages: [{ role: 'user', content: prompt }] };
      if (maxTokens) body.max_tokens = maxTokens;
      if (withTools) body.tools = [APP_TOOL];
      return fetchImpl(origin + '/v1/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: controller.signal });
    };
    try {
      response = await send();
      // Models without tool support reject the request; they still read the instructions and can write action blocks.
      if (withTools && response.status === 400) { const text = await response.text().catch(() => ''); if (/tool/i.test(text)) { withTools = false; response = await send(); } else response = new Response(text, { status: 400 }); }
    } catch (error) {
      clearTimeout(timer);
      if (cancelled) throw new Error('Response stopped.');
      if (timedOut) throw new Error(`${server.name} did not finish within ten minutes.`);
      throw new Error(`${server.name} isn’t running at ${origin}. Open ${server.name} and start its server, then retry.`);
    }
    if (!response.ok) { clearTimeout(timer); const text = await response.text().catch(() => ''); throw new Error(friendlyError(server, response.status, text.slice(0, 2000))); }
    let raw = '', pending = '';
    const calls = [];
    const decoder = new TextDecoder();
    const consume = line => {
      const data = line.replace(/^data:\s*/, '').trim();
      if (!data || data === '[DONE]' || !line.startsWith('data:')) return;
      let value; try { value = JSON.parse(data); } catch { return; }
      const piece = value?.choices?.[0]?.delta?.content ?? value?.choices?.[0]?.message?.content;
      if (typeof piece === 'string' && piece) { raw += piece; if (raw.length > 400000) controller.abort(); onEvent({ type: 'text', text: visibleText(raw) }); }
      // Tool calls stream in pieces: a name first, then the arguments a few characters at a time.
      for (const delta of value?.choices?.[0]?.delta?.tool_calls || value?.choices?.[0]?.message?.tool_calls || []) {
        const index = Number.isInteger(delta?.index) ? delta.index : calls.length;
        const call = calls[index] ||= { name: '', arguments: '' };
        if (typeof delta?.function?.name === 'string') call.name += delta.function.name;
        const args = delta?.function?.arguments;
        if (typeof args === 'string') call.arguments += args; else if (args && typeof args === 'object') call.arguments = args;
        if (calls.length > 8) controller.abort();
      }
    };
    try {
      for await (const chunk of response.body) {
        pending += decoder.decode(chunk, { stream: true });
        let index; while ((index = pending.indexOf('\n')) >= 0) { consume(pending.slice(0, index)); pending = pending.slice(index + 1); }
      }
      if (pending) consume(pending);
    } catch {
      if (cancelled) throw new Error('Response stopped.');
      if (timedOut) throw new Error(`${server.name} did not finish within ten minutes.`);
      throw new Error(`The connection to ${server.name} was lost. Retry.`);
    } finally { clearTimeout(timer); }
    const blocks = actionBlocks(calls.filter(Boolean));
    const text = (visibleText(raw).trim() + blocks).trim();
    if (!text) throw new Error(`${server.name} returned an empty reply. Try another model.`);
    if (blocks) onEvent({ type: 'text', text });
    return text;
  })();
  return { done, cancel };
}

// ---- 0.9.5: Ollama model manager ----
/** Models worth downloading, smallest first. `voice` marks the quick ones that suit voice mode. */
const OLLAMA_RECOMMENDED = [
  { name: 'llama3.2:3b', sizeGB: 2.0, minMemoryGB: 8, voice: true, about: 'Meta Llama 3.2 · quick, good for voice' },
  { name: 'qwen3:4b', sizeGB: 2.6, minMemoryGB: 8, voice: true, about: 'Qwen 3 · quick and capable' },
  { name: 'gemma3:4b', sizeGB: 3.3, minMemoryGB: 8, voice: true, about: 'Google Gemma 3 · quick, understands images' },
  { name: 'llama3.1:8b', sizeGB: 4.9, minMemoryGB: 16, voice: false, about: 'Meta Llama 3.1 · stronger answers' },
  { name: 'qwen3:8b', sizeGB: 5.2, minMemoryGB: 16, voice: false, about: 'Qwen 3 · stronger answers and tools' },
  { name: 'gemma3:12b', sizeGB: 8.1, minMemoryGB: 24, voice: false, about: 'Google Gemma 3 · best quality here' }
];
const MODEL_NAME = /^[a-z0-9][a-z0-9._:\/-]{0,100}$/i;
/** Installed Ollama models with sizes, or null when Ollama is not running. */
async function ollamaModels(base, { fetchImpl = fetch } = {}) {
  const origin = serverURL(base || SERVERS.ollama.url); if (!origin) return null;
  try {
    const value = await getJSON(origin + '/api/tags', fetchImpl, 3000);
    return (value?.models || []).filter(m => typeof m?.name === 'string' && MODEL_NAME.test(m.name)).map(m => ({ name: m.name, bytes: Number(m.size) || 0, parameters: m.details?.parameter_size || '' }));
  } catch { return null; }
}
/** Downloads a model, calling onProgress({status, completed, total}). Resolves when done. */
async function ollamaPull(base, name, { fetchImpl = fetch, onProgress = () => {}, signal } = {}) {
  const origin = serverURL(base || SERVERS.ollama.url);
  if (!origin || !MODEL_NAME.test(String(name))) throw new Error('Choose a valid model name, like llama3.2:3b.');
  let response;
  try { response = await fetchImpl(origin + '/api/pull', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: name, stream: true }), signal }); }
  catch { throw new Error(`Ollama isn’t running at ${origin}. Open Ollama, then try again.`); }
  if (!response.ok) throw new Error(`Ollama could not download ${name} (HTTP ${response.status}). Check the name on ollama.com/library.`);
  const decoder = new TextDecoder(); let pending = '';
  for await (const chunk of response.body) {
    pending += decoder.decode(chunk, { stream: true });
    let index; while ((index = pending.indexOf('\n')) >= 0) {
      const line = pending.slice(0, index); pending = pending.slice(index + 1);
      let value; try { value = JSON.parse(line); } catch { continue; }
      if (value.error) throw new Error(`Ollama: ${String(value.error).slice(0, 200)}`);
      onProgress({ status: String(value.status || ''), completed: Number(value.completed) || 0, total: Number(value.total) || 0 });
    }
  }
  return true;
}
async function ollamaDelete(base, name, { fetchImpl = fetch } = {}) {
  const origin = serverURL(base || SERVERS.ollama.url);
  if (!origin || !MODEL_NAME.test(String(name))) throw new Error('Invalid model name.');
  const response = await fetchImpl(origin + '/api/delete', { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: name }) });
  if (!response.ok) throw new Error(`Ollama could not remove ${name} (HTTP ${response.status}).`);
  return true;
}
/** The quickest installed model for voice: a recommended voice model if present, else the smallest. */
function voicePick(models) {
  const quick = OLLAMA_RECOMMENDED.filter(x => x.voice).map(x => x.name);
  return models.find(m => quick.includes(m.name))?.name || [...models].sort((a, b) => a.bytes - b.bytes)[0]?.name || '';
}

module.exports = { SERVERS, serverURL, visibleText, listModels, run, APP_TOOL, actionBlocks, OLLAMA_RECOMMENDED, ollamaModels, ollamaPull, ollamaDelete, voicePick };
