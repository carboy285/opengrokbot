const test = require('node:test');
const assert = require('node:assert/strict');
const { hitsFrom, search, TOOLS } = require('./composio-search.cjs');

test('results are found in common response shapes and cleaned', () => {
  const nested = { data: { response_data: { organic_results: [
    { title: 'Result One', link: 'https://one.example/a', snippet: 'First  snippet\nwith   spaces' },
    { title: 'Result Two', url: 'https://two.example/b', description: 'Second' },
    { title: 'Bad scheme', url: 'javascript:alert(1)' },
    { title: 'Credentials', url: 'https://user:pw@evil.example/' },
    { title: 'Duplicate', url: 'https://one.example/a' }
  ] } } };
  const hits = hitsFrom(nested);
  assert.deepEqual(hits.map(h => h.url), ['https://one.example/a', 'https://two.example/b']);
  assert.equal(hits[0].snippet, 'First snippet with spaces');
  assert.equal(hitsFrom({ results: [{ name: 'Named', href: 'https://x.example', content: 'c' }] })[0].title, 'Named');
  assert.deepEqual(hitsFrom('nothing'), []);
  assert.equal(hitsFrom({ items: Array.from({ length: 30 }, (_, i) => ({ title: `T${i}`, url: `https://e${i}.example` })) }).length, 8);
});

test('the first tool is used, a missing tool is skipped, and the key goes only in the header', async () => {
  const calls = [];
  const fetcher = async (url, options) => {
    calls.push({ url, options });
    if (url.includes(TOOLS[0])) return { ok: false, status: 404, text: async () => '{}' };
    return { ok: true, status: 200, text: async () => JSON.stringify({ successful: true, data: { results: [{ title: 'Hit', url: 'https://hit.example', snippet: 's' }] } }) };
  };
  const hits = await search({ key: 'secret-key', userID: 'u1', query: 'weather today', fetcher });
  assert.equal(hits[0].url, 'https://hit.example/');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.headers['x-api-key'], 'secret-key');
  assert.ok(!calls[0].options.body.includes('secret-key'));
  assert.deepEqual(JSON.parse(calls[0].options.body).arguments, { query: 'weather today' });
  assert.equal(JSON.parse(calls[0].options.body).user_id, 'u1');
  assert.ok(calls.every(c => c.url.startsWith('https://backend.composio.dev/')));
});

test('a rejected key stops at once, nothing found is an empty list, and total failure throws', async () => {
  let count = 0;
  await assert.rejects(search({ key: 'k', userID: 'u', query: 'q', fetcher: async () => { count++; return { ok: false, status: 401, text: async () => '' }; } }), /rejected/);
  assert.equal(count, 1);
  const empty = await search({ key: 'k', userID: 'u', query: 'q', fetcher: async () => ({ ok: true, status: 200, text: async () => JSON.stringify({ successful: true, data: { results: [] } }) }) });
  assert.deepEqual(empty, []);
  await assert.rejects(search({ key: 'k', userID: 'u', query: 'q', fetcher: async () => { throw new Error('offline'); } }), /could not be reached/);
  await assert.rejects(search({ key: 'k', userID: 'u', query: 'q', fetcher: async () => ({ ok: true, status: 200, text: async () => JSON.stringify({ successful: false, error: 'tool unavailable' }) }) }), /unavailable/);
});
