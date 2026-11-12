const test = require('node:test'), assert = require('node:assert/strict');
const load = () => import('../renderer/markdown-core.mjs');

test('parses the blocks Bots use', async () => {
  const md = await load();
  const blocks = md.parseMarkdown('# Plan\n\nHello **there** and `code`.\n\n1. One\n2. Two\n   - nested\n\n| City | Price |\n|---|--:|\n| Miami | $1 |\n\n```js\nconst a = 1;\n```\n> quote');
  assert.deepEqual(blocks.map(b => b.type), ['heading', 'paragraph', 'list', 'table', 'code', 'quote']);
  assert.equal(blocks[2].ordered, true); assert.equal(blocks[2].items.length, 2); assert.equal(blocks[2].items[1].sub[0].type, 'list');
  assert.deepEqual(blocks[3].align, ['left', 'right']); assert.equal(blocks[3].rows.length, 1);
  assert.equal(blocks[4].lang, 'js'); assert.equal(blocks[4].text, 'const a = 1;');
  assert.deepEqual(blocks[1].children.map(s => s.type), ['text', 'strong', 'text', 'code', 'text']);
});

test('only http(s) links become links; markup is never raw HTML', async () => {
  const md = await load();
  const spans = md.parseInline('see [docs](https://example.com) and [bad](javascript:alert(1)) <img src=x onerror=alert(1)>');
  assert.equal(spans.filter(s => s.type === 'link').length, 1);
  assert.equal(spans.filter(s => s.type === 'link')[0].href, 'https://example.com');
  assert.ok(spans.some(s => s.type === 'text' && s.text.includes('<img src=x')));
});

test('an unfinished code block while streaming stays code', async () => {
  const md = await load();
  assert.equal(md.parseMarkdown('```py\nprint(1)').at(-1).type, 'code');
  const tokens = md.highlight('const x = "hi"; // note');
  assert.deepEqual(tokens.filter(t => t.type !== 'plain').map(t => t.type), ['keyword', 'string', 'comment']);
});

test('tables accept short and centred separators', async () => {
  const md = await load();
  const [table] = md.parseMarkdown('| Ship | Nights | Price |\n|---|:-:|--:|\n| A | 7 | $1 |');
  assert.equal(table.type, 'table'); assert.deepEqual(table.align, ['left', 'center', 'right']);
});
