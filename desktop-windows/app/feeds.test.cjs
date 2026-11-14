const test = require('node:test');
const assert = require('node:assert/strict');
const feeds = require('./feeds.cjs');

const rss = `<?xml version="1.0"?><rss><channel><title>News</title>
<item><title><![CDATA[Chips &amp; more]]></title><link>https://news.example/a</link><description>&lt;p&gt;Hello &lt;b&gt;world&lt;/b&gt;&lt;/p&gt;</description><pubDate>Fri, 14 Nov 2026 10:00:00 GMT</pubDate></item>
<item><title>Bad link</title><link>http://insecure.example/x</link></item>
<item><title>Local</title><link>https://192.168.1.5/admin</link></item>
</channel></rss>`;
const atom = `<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Entry one</title><link rel="alternate" href="https://blog.example/1"/><summary>Short</summary><updated>2026-11-14T10:00:00Z</updated></entry></feed>`;

test('RSS and Atom items become titled, linked, cleaned entries; unsafe links are dropped', () => {
  const items = feeds.parseXML(rss);
  assert.equal(items.length, 1);
  assert.deepEqual([items[0].title, items[0].url, items[0].snippet], ['Chips & more', 'https://news.example/a', 'Hello world']);
  assert.deepEqual(feeds.parseXML(atom).map(x => [x.title, x.url, x.snippet]), [['Entry one', 'https://blog.example/1', 'Short']]);
});

test('only public https addresses are fetched', () => {
  for (const bad of ['http://a.example/f', 'https://localhost/f', 'https://127.0.0.1/f', 'https://10.0.0.2/f', 'https://192.168.0.9/f', 'https://169.254.169.254/latest', 'https://[::1]/f', 'https://printer/f', 'https://user:pw@a.example/f', 'file:///etc/passwd', 'nonsense'])
    assert.equal(feeds.publicURL(bad), null, bad);
  assert.equal(feeds.publicURL('https://a.example/feed.xml').href, 'https://a.example/feed.xml');
});

test('subreddits and Bluesky accounts resolve to their public feeds', () => {
  assert.equal(feeds.resolve('r/technology').url.href, 'https://www.reddit.com/r/technology/.rss');
  assert.equal(feeds.resolve('https://www.reddit.com/r/news').label, 'r/news');
  const bsky = feeds.resolve('@someone.bsky.social');
  assert.equal(bsky.url.host, 'public.api.bsky.app');
  assert.equal(bsky.url.searchParams.get('actor'), 'someone.bsky.social');
  assert.equal(feeds.resolve('http://insecure.example'), null);
});

test('read returns items, follows only safe redirects and reports plain errors', async () => {
  const response = (status, body, headers = {}) => ({ status, ok: status < 300, headers: new Headers(headers), text: async () => body });
  const ok = await feeds.read('https://news.example/feed', { fetcher: async url => url.endsWith('/feed') ? response(302, '', { location: '/real.xml' }) : response(200, rss) });
  assert.equal(ok.items[0].title, 'Chips & more');
  await assert.rejects(feeds.read('https://news.example/feed', { fetcher: async () => response(302, '', { location: 'https://127.0.0.1/x' }) }), /not a public https/);
  await assert.rejects(feeds.read('https://news.example/feed', { fetcher: async () => response(404, '') }), /HTTP 404/);
  await assert.rejects(feeds.read('https://news.example/feed', { fetcher: async () => { throw new Error('secret internal detail'); } }), /could not be reached/);
  await assert.rejects(feeds.read('r/x'), /read_feed needs/);
  const post = { feed: [{ post: { uri: 'at://did:plc:1/app.bsky.feed.post/3kabc', author: { handle: 'a.bsky.social' }, record: { text: 'Hello Bluesky', createdAt: '2026-11-14T10:00:00Z' } } }] };
  const sky = await feeds.read('@a.bsky.social', { fetcher: async () => response(200, JSON.stringify(post)) });
  assert.equal(sky.items[0].url, 'https://bsky.app/profile/a.bsky.social/post/3kabc');
});
