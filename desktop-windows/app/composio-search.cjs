'use strict';
/**
 * Web search through Composio's own search toolkit, so a Bot never has to open a browser window to look something up.
 * The project key stays in this process; only the search text is sent, and only to Composio.
 */
const TOOLKIT = 'composio_search';
// Tried in order. The first that returns results wins; a tool Composio does not know is skipped.
const TOOLS = ['COMPOSIO_SEARCH_DUCK_DUCK_GO_SEARCH', 'COMPOSIO_SEARCH_WEB'];
const MAX_HITS = 8;

const clip = (value, length) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, length);
const first = (object, names) => { for (const name of names) if (typeof object[name] === 'string' && object[name].trim()) return object[name]; return ''; };
const webURL = value => { try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password && value.length <= 2000 ? url.href : null; } catch { return null; } };

/** Finds result-like objects (a link plus a title) anywhere in a response, whatever shape the tool used. */
function hitsFrom(value) {
  const hits = [], seen = new Set();
  const visit = (node, depth) => {
    if (hits.length >= MAX_HITS || depth > 8 || node === null || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const item of node) visit(item, depth + 1); return; }
    const link = webURL(first(node, ['url', 'link', 'href']));
    const title = first(node, ['title', 'name', 'heading']);
    if (link && title && !seen.has(link)) {
      seen.add(link);
      hits.push({ title: clip(title, 140), url: link, snippet: clip(first(node, ['snippet', 'description', 'content', 'text', 'body', 'summary', 'excerpt']), 240) });
      return;
    }
    for (const child of Object.values(node)) visit(child, depth + 1);
  };
  visit(value, 0);
  return hits.slice(0, MAX_HITS);
}

class SearchError extends Error { constructor(message, status) { super(message); this.status = status; } }

async function execute({ key, userID, tool, query, fetcher }) {
  let response;
  try {
    response = await fetcher(`https://backend.composio.dev/api/v3/tools/execute/${encodeURIComponent(tool)}`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { 'x-api-key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: userID, arguments: { query }, version: 'latest' })
    });
  } catch { throw new SearchError('Composio could not be reached.', 0); }
  if ([401, 403].includes(response.status)) throw new SearchError('Composio rejected this project key.', response.status);
  if (response.status === 429) throw new SearchError('Composio’s rate limit was reached.', 429);
  const text = await response.text();
  if (!response.ok) throw new SearchError(`Composio search failed (HTTP ${response.status}).`, response.status);
  if (text.length > 4_000_000) throw new SearchError('Composio returned an unsupported response.', 200);
  let body; try { body = JSON.parse(text); } catch { throw new SearchError('Composio returned an unsupported response.', 200); }
  if (body?.successful === false) throw new SearchError(clip(body?.error, 160) || 'Composio search did not succeed.', 200);
  return hitsFrom(body?.data ?? body);
}

/** Returns hits, or throws a SearchError saying why none could be had. An empty array means the search ran and found nothing. */
async function search({ key, userID, query, fetcher = fetch }) {
  let lastError = null, ran = false;
  for (const tool of TOOLS) {
    try {
      const hits = await execute({ key, userID, tool, query, fetcher });
      ran = true;
      if (hits.length) return hits;
    } catch (error) {
      if ([401, 403, 429].includes(error.status)) throw error;
      lastError = error;
    }
  }
  if (ran) return [];
  throw lastError || new SearchError('Composio search is not available.', 0);
}

module.exports = { TOOLKIT, TOOLS, hitsFrom, search, SearchError };
