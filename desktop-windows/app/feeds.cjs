'use strict';
// Reads public feeds for a Bot: RSS and Atom, a subreddit, or a Bluesky account. Read-only and public only.
// It fetches nothing private: https only, no addresses on this computer or local network, no redirects off the web, and a size cap.

const MAX_BYTES = 1_000_000;
const MAX_ITEMS = 10;

const clip = (value, length) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, length);
const decode = text => String(text ?? '')
  .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
  .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Math.min(Number(n), 0x10ffff)))
  .replace(/&amp;/g, '&');
const strip = html => decode(html).replace(/<[^>]*>/g, ' ');

function privateHost(host) {
  const h = host.toLowerCase().replace(/^\[|\]$/g, '');
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || !h.includes('.') && !h.includes(':')) return true;
  const v4 = h.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) { const [a, b] = [Number(v4[1]), Number(v4[2])]; return a === 0 || a === 10 || a === 127 || a === 169 && b === 254 || a === 172 && b >= 16 && b <= 31 || a === 192 && b === 168 || a === 100 && b >= 64 && b <= 127 || a >= 224; }
  if (h.includes(':')) return h === '::1' || h === '::' || /^f[cd]/.test(h) || h.startsWith('fe80') || h.startsWith('::ffff:');
  return false;
}

/** The URL if it is a public https address, otherwise null. */
function publicURL(value) {
  try {
    const url = new URL(String(value).trim());
    if (url.protocol !== 'https:' || url.username || url.password || String(value).length > 2000 || privateHost(url.hostname)) return null;
    return url;
  } catch { return null; }
}

/** Turns a friendly source into a feed address. */
function resolve(source) {
  const text = String(source ?? '').trim();
  const reddit = text.match(/^(?:r\/|https:\/\/(?:www\.|old\.)?reddit\.com\/r\/)([A-Za-z0-9_]{2,21})\/?$/);
  if (reddit) return { kind: 'rss', url: new URL(`https://www.reddit.com/r/${reddit[1]}/.rss`), label: `r/${reddit[1]}` };
  const bluesky = text.match(/^(?:@|https:\/\/bsky\.app\/profile\/)([A-Za-z0-9.-]{3,253})\/?$/);
  if (bluesky) {
    const url = new URL('https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed');
    url.searchParams.set('actor', bluesky[1]); url.searchParams.set('limit', String(MAX_ITEMS)); url.searchParams.set('filter', 'posts_no_replies');
    return { kind: 'bluesky', url, label: '@' + bluesky[1], actor: bluesky[1] };
  }
  const url = publicURL(text);
  return url ? { kind: 'rss', url, label: url.hostname } : null;
}

const tag = (block, name) => { const m = block.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`, 'i')); return m ? m[1] : ''; };
function parseXML(xml) {
  const items = [];
  const blocks = xml.match(/<(item|entry)[\s>][\s\S]*?<\/\1>/gi) || [];
  for (const block of blocks.slice(0, 40)) {
    let link = decode(tag(block, 'link')).trim();
    if (!link) { const atom = block.match(/<link\b[^>]*?href="([^"]+)"[^>]*>/i); link = atom ? decode(atom[1]) : ''; }
    const target = publicURL(link);
    const title = clip(strip(tag(block, 'title')), 160);
    if (!target || !title) continue;
    const body = tag(block, 'description') || tag(block, 'summary') || tag(block, 'content');
    items.push({ title, url: target.href, snippet: clip(strip(body), 240), date: clip(decode(tag(block, 'pubDate') || tag(block, 'updated') || tag(block, 'published')), 40) });
    if (items.length >= MAX_ITEMS) break;
  }
  return items;
}

function parseBluesky(json, actor) {
  const feed = Array.isArray(json?.feed) ? json.feed : [];
  return feed.slice(0, MAX_ITEMS).map(entry => {
    const post = entry?.post, text = clip(post?.record?.text, 300), id = String(post?.uri ?? '').split('/').pop();
    const handle = post?.author?.handle || actor;
    if (!text || !id || !/^[A-Za-z0-9]+$/.test(id)) return null;
    return { title: text.slice(0, 120), url: `https://bsky.app/profile/${handle}/post/${id}`, snippet: text.length > 120 ? text : '', date: clip(post?.record?.createdAt, 40) };
  }).filter(Boolean);
}

async function download(url, fetcher) {
  let current = url;
  for (let hop = 0; hop < 4; hop++) {
    const response = await fetcher(current.href, { redirect: 'manual', signal: AbortSignal.timeout(20000), headers: { 'User-Agent': 'OpenGrokBot-feed-reader', Accept: 'application/rss+xml, application/atom+xml, application/xml, application/json, text/xml;q=0.9' } });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const next = publicURL(new URL(response.headers.get('location') || '', current).href);
      if (!next) throw new Error('The feed redirected somewhere that is not a public https address.');
      current = next; continue;
    }
    if (!response.ok) throw new Error(`The feed answered HTTP ${response.status}.`);
    const text = await response.text();
    if (text.length > MAX_BYTES) throw new Error('The feed is too large.');
    return text;
  }
  throw new Error('The feed redirected too many times.');
}

/** Items from a public feed. Throws an Error with a plain message when it cannot be read. */
async function read(source, { fetcher = fetch } = {}) {
  const target = resolve(source);
  if (!target) throw new Error('read_feed needs a public https feed address, a subreddit like r/technology, or a Bluesky account like @name.bsky.social.');
  let body;
  try { body = await download(target.url, fetcher); } catch (error) { throw new Error(error.message.startsWith('The feed') ? error.message : 'The feed could not be reached.'); }
  let items;
  if (target.kind === 'bluesky') { try { items = parseBluesky(JSON.parse(body), target.actor); } catch { throw new Error('Bluesky returned an unsupported response.'); } }
  else items = parseXML(body);
  return { label: target.label, items };
}

module.exports = { publicURL, privateHost, resolve, parseXML, parseBluesky, read, MAX_ITEMS };
