'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtemp, mkdir, writeFile, rm } = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const da = require('./device-actions.cjs');
// local-browser.cjs imports electron at load time; stub it so its pure helpers can be tested under plain Node.
const Module = require('node:module');
const original = Module._load;
Module._load = function (request, ...rest) { return request === 'electron' ? {} : original.call(this, request, ...rest); };
const { hostMatches } = require('./local-browser.cjs');
Module._load = original;

test('risky clicks need approval and harmless ones do not', () => {
  for (const label of ['Place order', 'Buy now', 'Send', 'Draft', 'Delete account', 'Confirm payment', 'Submit lineup', 'Unsubscribe', 'Accept trade']) assert.ok(da.clickNeedsApproval({ label }), label);
  for (const label of ['Home', 'Next', 'Scores', 'Roster', 'Show more']) assert.ok(!da.clickNeedsApproval({ label }), label);
  assert.ok(da.clickNeedsApproval({ label: 'Go', submits: true }));
});

test('typing never touches passwords or payment fields; submit needs approval except in searches', () => {
  assert.match(da.typeDecision({ type: 'password' }).refuse, /secure_login/);
  assert.match(da.typeDecision({ type: 'text', hint: 'cc-number card number' }).refuse, /payment/);
  assert.match(da.typeDecision({ type: 'text', hint: 'social security number' }).refuse, /identity/);
  assert.equal(da.typeDecision({ type: 'text', hint: 'player name' }), 'allow');
  assert.equal(da.typeDecision({ type: 'search', hint: 'search', isSearch: true, submit: true }), 'allow');
  assert.equal(da.typeDecision({ type: 'text', hint: 'comment', submit: true }), 'approve');
});

test('browser requests are validated', () => {
  assert.deepEqual(da.parseRequest({ action: 'browser_click', text: 'Scores' }), { kind: 'click', target: 'Scores' });
  assert.equal(da.parseRequest({ action: 'browser_click', text: '  ' }), null);
  assert.deepEqual(da.parseRequest({ action: 'browser_type', name: 'search', text: 'x', submit: true }), { kind: 'type', field: 'search', text: 'x', submit: true });
  assert.deepEqual(da.parseRequest({ action: 'browser_scroll' }), { kind: 'scroll', direction: 'down' });
  assert.equal(da.parseRequest({ action: 'browser_scroll', direction: 'sideways' }), null);
  assert.deepEqual(da.parseRequest({ action: 'browser_back' }), { kind: 'back' });
});

const fakeBrowsers = (overrides = {}) => ({
  inspectClick: async () => ({ ok: true, label: 'Scores', tag: 'a', submits: false }), click: async () => {}, snapshot: async () => '{"title":"T"}',
  inspectField: async () => ({ ok: true, type: 'text', hint: 'search', isSearch: true }), type: async () => {}, scroll: async () => {}, back: async () => {},
  search: async () => [{ title: 'A', url: 'https://a.example', snippet: 's' }], fillLogin: async () => 'filled', ...overrides
});
const memoryStore = () => { let data = []; return { storage: { load: async () => structuredClone(data), save: async list => { data = structuredClone(list); } }, crypto: { encrypt: v => 'enc:' + Buffer.from(v).toString('base64'), decrypt: v => Buffer.from(v.slice(4), 'base64').toString() }, randomUUID: (() => { let n = 0; return () => `id-${++n}`; })() }; };

test('a risky click asks first, declining stops it, and unattended runs skip it', async () => {
  const asked = []; let clicked = 0;
  const logins = da.createLoginStore(memoryStore());
  const make = approveResult => da.create({ browsers: fakeBrowsers({ inspectClick: async () => ({ ok: true, label: 'Place order', tag: 'button', submits: true }), click: async () => { clicked++; } }), approve: async (t, d) => { asked.push(t); return approveResult; }, logins, directory: () => os.tmpdir() });
  const ctx = { botID: 'b', botName: 'Fantasy', unattended: false };
  assert.match(await make(false).run({ action: 'browser_click', text: 'Place order' }, ctx), /declined/);
  assert.equal(clicked, 0);
  assert.match(await make(true).run({ action: 'browser_click', text: 'Place order' }, ctx), /^Clicked “Place order”\./);
  assert.equal(clicked, 1);
  assert.match(await make(true).run({ action: 'browser_click', text: 'Place order' }, { ...ctx, unattended: true }), /unattended/);
  assert.equal(clicked, 1); assert.equal(asked.length, 2);
});

test('an always-ask rule for a site forces approval of an ordinary click there, and only there', async () => {
  const asked = []; let clicked = 0;
  const rules = async (tool, target) => (tool === 'browser_click' && target.includes('shop.example') ? 'ask' : 'noRule');
  const make = host => da.create({ rules, browsers: fakeBrowsers({ pageHost: () => host, click: async () => { clicked++; } }), approve: async (t) => { asked.push(t); return false; }, logins: da.createLoginStore(memoryStore()), directory: () => os.tmpdir() });
  const ctx = { botID: 'b', botName: 'Fantasy', unattended: false };
  assert.match(await make('www.shop.example').run({ action: 'browser_click', text: 'Scores' }, ctx), /declined/);
  assert.equal(asked.length, 1); assert.equal(clicked, 0);
  assert.match(await make('news.example').run({ action: 'browser_click', text: 'Scores' }, ctx), /^Clicked/);
  assert.equal(asked.length, 1); assert.equal(clicked, 1, 'No rule for that site, so the harmless click goes through');
  assert.match(await make('www.shop.example').run({ action: 'browser_click', text: 'Scores' }, { ...ctx, unattended: true }), /unattended/);
});

test('web search uses Composio when it is set up and only falls back to the browser when it is not or it fails', async () => {
  let browserSearches = 0;
  const browsers = fakeBrowsers({ search: async () => { browserSearches++; return [{ title: 'Browser hit', url: 'https://b.example', snippet: 'x' }]; } });
  const make = composioSearch => da.create({ browsers, composioSearch, approve: async () => true, logins: da.createLoginStore(memoryStore()), directory: () => os.tmpdir() });
  const ctx = { botID: 'b', botName: 'Fantasy', unattended: false };
  const viaComposio = await make(async () => [{ title: 'Composio hit', url: 'https://c.example', snippet: 'y' }]).run({ action: 'search_web', text: 'nfl' }, ctx);
  assert.match(viaComposio, /via Composio/); assert.match(viaComposio, /Composio hit/); assert.equal(browserSearches, 0);
  assert.match(await make(async () => []).run({ action: 'search_web', text: 'nothing' }, ctx), /no results/); assert.equal(browserSearches, 0);
  assert.match(await make(async () => null).run({ action: 'search_web', text: 'nfl' }, ctx), /Browser hit/); assert.equal(browserSearches, 1);
  const failed = await make(async () => { throw new Error('offline'); }).run({ action: 'search_web', text: 'nfl' }, ctx);
  assert.match(failed, /Composio search failed: offline/); assert.match(failed, /Browser hit/); assert.equal(browserSearches, 2);
});

test('harmless actions run without prompting and results summarize for the chat', async () => {
  let asked = 0;
  const devices = da.create({ browsers: fakeBrowsers(), approve: async () => { asked++; return true; }, logins: da.createLoginStore(memoryStore()), directory: () => os.tmpdir() });
  const ctx = { botID: 'b', botName: 'Fantasy', unattended: false };
  const click = await devices.run({ action: 'browser_click', text: 'Scores' }, ctx);
  assert.equal(da.summary(click), 'Clicked “Scores”.');
  assert.match(await devices.run({ action: 'browser_scroll', direction: 'bottom' }, ctx), /^Scrolled bottom\./);
  assert.match(await devices.run({ action: 'browser_type', name: 'search', text: 'Mahomes', submit: true }, ctx), /^Typed into the “search” field and submitted\./);
  const search = await devices.run({ action: 'search_web', text: 'nfl' }, ctx);
  assert.equal(da.summary(search), 'Searched the web for “nfl” · 1 results');
  assert.equal(asked, 0);
  assert.match(await devices.run({ action: 'browser_click' }, ctx), /was not understood/);
  assert.match(await devices.run({ action: 'search_web' }, ctx), /needs a query/);
  assert.ok(da.isFailure('That browser action was not understood.'));
});

test('secure logins never expose passwords, need approval, and only match their own site', async () => {
  const logins = da.createLoginStore(memoryStore());
  await logins.add({ label: 'ESPN', url: 'https://www.espn.com/login', username: 'me@example.com', password: 'correct-horse-battery' });
  assert.deepEqual(await logins.list(), [{ id: 'id-1', label: 'ESPN', host: 'www.espn.com', username: 'me@example.com' }]);
  await assert.rejects(logins.add({ label: 'espn', url: 'https://www.espn.com', username: 'x', password: 'y' }), /already exists/);
  await assert.rejects(logins.add({ label: 'Bad', url: 'http://insecure.example.com', username: 'x', password: 'y' }), /https/);
  const asked = []; let filled;
  const devices = da.create({ browsers: fakeBrowsers({ fillLogin: async (_id, args) => { filled = args; return 'Entered the saved username and password.'; } }), approve: async (title, detail) => { asked.push({ title, detail }); return true; }, logins, directory: () => os.tmpdir() });
  const ctx = { botID: 'b', botName: 'Fantasy', unattended: false };
  const ok = await devices.run({ action: 'secure_login', name: 'ESPN', url: 'https://www.espn.com/login' }, ctx);
  assert.match(ok, /^Secure login:/); assert.ok(!ok.includes('correct-horse-battery'));
  assert.equal(filled.password, 'correct-horse-battery'); assert.equal(filled.loginHost, 'www.espn.com');
  assert.ok(!asked[0].detail.includes('correct-horse-battery')); assert.match(asked[0].detail, /me@example.com/);
  assert.match(await devices.run({ action: 'secure_login', name: 'ESPN', url: 'https://www.espn.com.evil.example/login' }, ctx), /No saved secure login matches/);
  assert.match(await devices.run({ action: 'secure_login', name: 'ESPN', url: 'http://www.espn.com/login' }, ctx), /https/);
  assert.match(await devices.run({ action: 'secure_login', name: 'ESPN', url: 'https://www.espn.com/login' }, { ...ctx, unattended: true }), /unattended/);
  assert.equal(asked.length, 1);
});

test('login hosts match only exactly or as subdomains', () => {
  assert.equal(da.loginHost('https://Secure.ESPN.com/x?y=1'), 'secure.espn.com');
  for (const bad of ['http://espn.com', 'https://user:pw@espn.com', 'https://localhost', 'javascript:alert(1)', '']) assert.equal(da.loginHost(bad), null, bad);
  assert.ok(da.hostMatches('espn.com', 'www.espn.com') && da.hostMatches('espn.com', 'espn.com'));
  assert.ok(!da.hostMatches('espn.com', 'espn.com.evil.example') && !da.hostMatches('espn.com', 'notespn.com'));
  assert.ok(hostMatches('espn.com', 'www.espn.com') && !hostMatches('espn.com', 'notespn.com') && !hostMatches('', 'x'));
});

test('knowledge search ranks passages from text files', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'grok-know-'));
  try {
    const folder = path.join(root, 'bot', 'Knowledge'); await mkdir(folder, { recursive: true });
    await writeFile(path.join(folder, 'rules.txt'), 'League rules\n\nThe waiver wire opens Wednesday at noon. Claims process at 3 AM.\n\nPlayoffs start in week 15.');
    await writeFile(path.join(folder, 'soup.md'), 'Unrelated recipe for soup');
    await writeFile(path.join(folder, 'program.exe'), 'binary');
    const devices = da.create({ browsers: fakeBrowsers(), approve: async () => true, logins: da.createLoginStore(memoryStore()), directory: () => path.join(root, 'bot') });
    const found = await devices.run({ action: 'search_knowledge', text: 'when does the waiver wire open' }, { botID: 'b', botName: 'F' });
    assert.match(found, /\[rules\.txt\]/); assert.match(found, /Wednesday at noon/); assert.ok(!found.includes('soup'));
    assert.equal(da.summary(found), 'Searched this Bot’s knowledge files for “when does the waiver wire open” · 1 passage');
    assert.match(await devices.run({ action: 'search_knowledge', text: 'zzzzqq' }, { botID: 'b', botName: 'F' }), /No passages matched/);
    assert.match(await devices.run({ action: 'search_knowledge', text: '' }, { botID: 'b', botName: 'F' }), /Knowledge files: rules\.txt, soup\.md/);
    assert.match(await devices.run({ action: 'search_knowledge', text: 'x' }, { botID: 'b2', botName: 'F' }), /Searched/);
  } finally { await rm(root, { recursive: true, force: true }); }
  assert.equal(da.rank([{ file: 'a', text: 'one two' }, { file: 'b', text: 'goat goat farm' }, { file: 'c', text: 'goat' }], 'goat farm').map(x => x.file).join(), 'b,c');
});

test('1Password items: names are validated and op output is parsed', () => {
  assert.ok(da.isValidItemName('ESPN'));
  assert.ok(!da.isValidItemName('--vault'));
  assert.ok(!da.isValidItemName('a\nb'));
  assert.ok(!da.isValidItemName(''));
  const json = JSON.stringify({ fields: [{ id: 'username', purpose: 'USERNAME', value: 'me@example.com' }, { id: 'password', purpose: 'PASSWORD', value: 'pw-123' }] });
  assert.deepEqual(da.parseOnePassword(json), { username: 'me@example.com', password: 'pw-123' });
  assert.equal(da.parseOnePassword('{"fields":[]}'), null);
  assert.equal(da.parseOnePassword('not json'), null);
});

test('a 1Password login stores only the item name and signs in without exposing the password', async () => {
  let records = [];
  const logins = da.createLoginStore({ storage: { load: async () => records, save: async list => { records = list; } }, crypto: { encrypt: x => x, decrypt: x => x }, randomUUID: () => 'id-1' });
  await logins.addOnePassword({ label: 'ESPN', url: 'https://www.espn.com/login', item: 'ESPN login' });
  assert.deepEqual(records[0], { id: 'id-1', label: 'ESPN', host: 'www.espn.com', username: '1Password', onePassword: 'ESPN login' });
  await assert.rejects(logins.addOnePassword({ label: 'espn', url: 'https://www.espn.com', item: 'x' }), /already exists/);
  await assert.rejects(logins.addOnePassword({ label: 'Bad', url: 'http://www.espn.com', item: 'x' }), /https/);
  const filled = [];
  const devices = da.create({
    browsers: { fillLogin: async (id, details) => { filled.push(details); return 'Signed in.'; } },
    approve: async (title, detail) => { assert.ok(detail.includes('1Password item')); assert.ok(!detail.includes('pw-123')); return true; },
    logins, directory: () => os.tmpdir(), onePassword: async item => { assert.equal(item, 'ESPN login'); return { username: 'me@example.com', password: 'pw-123' }; }
  });
  const result = await devices.run({ action: 'secure_login', url: 'https://www.espn.com/login', name: 'ESPN' }, { botID: 'b', botName: 'Fantasy', unattended: false });
  assert.match(result, /Signed in/);
  assert.equal(filled[0].password, 'pw-123');
  assert.ok(!result.includes('pw-123'));
});

test('Knowledge reads whole files in parts and PDFs by page', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'knowledge-'));
  try {
    await mkdir(path.join(dir, 'Knowledge'));
    await writeFile(path.join(dir, 'Knowledge', 'Notes.txt'), 'a'.repeat(12000) + 'b'.repeat(50));
    await writeFile(path.join(dir, 'Knowledge', 'Book.pdf'), 'fake');
    const pdfPages = async () => ['first page words', 'second page words'];
    const first = await da.knowledgeRead(dir, 'notes', 1, pdfPages);
    assert.match(first, /part 1 of 2/); assert.match(first, /ask for page 2/);
    assert.ok((await da.knowledgeRead(dir, 'Notes.txt', 2, pdfPages)).endsWith('b'.repeat(50)));
    assert.match(await da.knowledgeRead(dir, 'book', 2, pdfPages), /page 2 of 2:\nsecond page words/);
    assert.match(await da.knowledgeRead(dir, 'missing', 1, pdfPages), /No Knowledge file matches/);
    assert.match(await da.knowledgeSearch(dir, 'second page', pdfPages), /\[Book.pdf\] first page words second page words/);
    const run = await da.create({ browsers: {}, approve: async () => false, logins: {}, directory: () => dir, pdfPages }).run({ action: 'read_knowledge', name: 'book', page: 1 }, { botID: 'b', botName: 'x' });
    assert.match(run, /Knowledge search results/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('pdf.js reads real PDF text on this machine', async () => {
  const { pdfPages } = require('./pdf-text.cjs');
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'];
  const stream = 'BT /F1 18 Tf 20 100 Td (Hello Knowledge) Tj ET';
  objects.push(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  let out = '%PDF-1.4\n'; const offsets = [];
  objects.forEach((o, i) => { offsets.push(out.length); out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` + offsets.map(o => `${String(o).padStart(10, '0')} 00000 n \n`).join('') + `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  assert.deepEqual(await pdfPages(Buffer.from(out)), ['Hello Knowledge']);
});
