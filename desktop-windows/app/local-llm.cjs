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

/** Same shape as a CLI run: { done: Promise<text>, cancel(immediately) }. Calls onEvent({type:'text', text}) as text streams in. */
function run({ provider, base, prompt, model = '', onEvent = () => {}, timeout = 600000, fetchImpl = fetch, maxTokens }) {
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
    let response;
    try {
      const body = { model: chosen, stream: true, messages: [{ role: 'user', content: prompt }] };
      if (maxTokens) body.max_tokens = maxTokens;
      response = await fetchImpl(origin + '/v1/chat/completions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: controller.signal });
    } catch (error) {
      clearTimeout(timer);
      if (cancelled) throw new Error('Response stopped.');
      if (timedOut) throw new Error(`${server.name} did not finish within ten minutes.`);
      throw new Error(`${server.name} isn’t running at ${origin}. Open ${server.name} and start its server, then retry.`);
    }
    if (!response.ok) { clearTimeout(timer); const text = await response.text().catch(() => ''); throw new Error(friendlyError(server, response.status, text.slice(0, 2000))); }
    let raw = '', pending = '';
    const decoder = new TextDecoder();
    const consume = line => {
      const data = line.replace(/^data:\s*/, '').trim();
      if (!data || data === '[DONE]' || !line.startsWith('data:')) return;
      let value; try { value = JSON.parse(data); } catch { return; }
      const piece = value?.choices?.[0]?.delta?.content ?? value?.choices?.[0]?.message?.content;
      if (typeof piece === 'string' && piece) { raw += piece; if (raw.length > 400000) controller.abort(); onEvent({ type: 'text', text: visibleText(raw) }); }
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
    const text = visibleText(raw).trim();
    if (!text) throw new Error(`${server.name} returned an empty reply. Try another model.`);
    return text;
  })();
  return { done, cancel };
}

module.exports = { SERVERS, serverURL, visibleText, listModels, run };
