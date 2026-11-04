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
