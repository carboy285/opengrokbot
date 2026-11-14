// Web access check: the real server (desktop-windows/app/web-access.cjs) with a fake app behind it, driven over HTTP and
// from a real browser. Run: CHROMIUM_PATH=/path/to/chromium node scripts/test-web-access.cjs
const assert = require('node:assert/strict');
const path = require('node:path');
const { chromium } = require('@playwright/test');
const { WebAccess, hashPassword, checkPassword, passwordProblem, bridgeTable } = require('../desktop-windows/app/web-access.cjs');
const { previewWorkspace } = require('../desktop-windows/app/workspace.cjs');

(async () => {
  assert.equal(checkPassword('correct horse battery', hashPassword('correct horse battery')), true);
  assert.equal(checkPassword('wrong', hashPassword('correct horse battery')), false);
  assert.match(passwordProblem('short'), /at least 10/);
  const table = bridgeTable(require('node:fs').readFileSync(path.join(__dirname, '../desktop-windows/app/preload.cjs'), 'utf8'));
  assert.equal(table.invoke.send, 'chat:send');
  assert.equal(table.invoke.vaultRead, 'vault:read');
  assert.equal(table.listen.onChange, 'workspace:changed');

  let workspace = previewWorkspace();
  const calls = [];
  const web = new WebAccess({
    invoke: async (channel, args) => {
      calls.push([channel, args]);
      if (channel === 'workspace:load') return { ok: true, value: workspace };
      if (channel === 'setup:status' || channel === 'setup:scan') return { ok: true, value: { providers: [], installed: [{ id: 'codex:x', provider: 'codex', name: 'Codex', path: '/x' }], selected: 'codex:x', complete: true } };
      if (channel === 'chat:send') {
        workspace = structuredClone(workspace);
        workspace.entries.push({ id: crypto.randomUUID(), botID: args[0], kind: 'user', text: args[1] });
        setTimeout(() => { workspace.entries.push({ id: crypto.randomUUID(), botID: args[0], kind: 'bot', text: 'Hello from the host', state: 'complete' }); web.broadcast('workspace:changed', { workspace, running: [] }); }, 100);
        return { ok: true, value: workspace };
      }
      return { ok: true, value: null };
    },
    config: () => ({ username: 'ben', passwordHash: hashPassword('a long test password') }),
    rendererDir: path.join(__dirname, '../desktop-windows/renderer'),
    preloadFile: path.join(__dirname, '../desktop-windows/app/preload.cjs')
  });
  const port = await web.start({ port: 0, lan: false });
  const base = `http://127.0.0.1:${port}`;
  let browser;
  try {
    // Signed out: pages go to the login page, the API answers 401.
    let response = await fetch(base + '/', { redirect: 'manual' });
    assert.equal(response.status, 303); assert.equal(response.headers.get('location'), '/login');
    assert.equal((await fetch(base + '/api/invoke', { method: 'POST', headers: { 'X-OGB-Request': '1' }, body: '{}' })).status, 401);
    const login = (username, password, headers = {}) => fetch(base + '/login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers }, body: new URLSearchParams({ username, password }) });
    response = await login('ben', 'nope');
    assert.equal(response.status, 401);
    assert.equal((await login('ben', 'a long test password', { Origin: 'http://evil.example' })).status, 403, 'a login posted from another site is refused');
    response = await login('ben', 'a long test password');
    assert.equal(response.status, 303);
    const cookie = response.headers.get('set-cookie');
    assert.match(cookie, /^ogb_session=[A-Za-z0-9_-]{43}; HttpOnly; SameSite=Strict; Path=\//);
    const session = cookie.split(';')[0];
    const api = (channel, args = [], headers = { 'X-OGB-Request': '1' }) => fetch(base + '/api/invoke', { method: 'POST', headers: { 'Content-Type': 'application/json', Cookie: session, ...headers }, body: JSON.stringify({ channel, args }) });
    assert.equal((await (await api('workspace:load')).json()).ok, true);
    for (const channel of ['vault:read', 'cli-keys:set', 'media-keys:set', 'web:configure', 'setup:path', 'files:open-folder', 'composio:connect', 'backup:export']) {
      const result = await api(channel, ['x']);
      assert.equal(result.status, 403, channel + ' must stay on the host');
    }
    assert.equal(calls.some(([channel]) => channel === 'vault:read'), false);
    assert.equal((await api('workspace:load', [], {})).status, 403, 'API calls need the app header');
    assert.equal((await api('workspace:load', [], { 'X-OGB-Request': '1', Origin: 'http://evil.example' })).status, 403, 'cross-site API calls are refused');
    assert.equal((await fetch(base + '/../app/main.cjs', { headers: { Cookie: session } })).status, 404);
    assert.equal((await fetch(base + '/%2e%2e/app/main.cjs', { headers: { Cookie: session } })).status, 404);
    const page = await (await fetch(base + '/', { headers: { Cookie: session } })).text();
    assert.match(page, /<script src="web-bridge.js"><\/script>/);
    assert.match(page, /connect-src 'self'/);
    const bridge = await (await fetch(base + '/web-bridge.js', { headers: { Cookie: session } })).text();
    assert.doesNotMatch(bridge, /vault:read|cli-keys:set/, 'the bridge never offers host-only calls');

    // Five wrong passwords lock that device out.
    for (let i = 0; i < 5; i++) await login('ben', 'wrong');
    assert.equal((await login('ben', 'a long test password')).status, 429);
    web.failures.clear();

    // A real browser: sign in, chat, and see the host's reply arrive live.
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless: true, args: ['--no-sandbox'] });
    const tab = await browser.newPage({ viewport: { width: 420, height: 860 } });
    const errors = []; tab.on('pageerror', error => errors.push(error.message));
    await tab.goto(base + '/');
    await tab.getByLabel('Username').fill('ben'); await tab.getByLabel('Password').fill('a long test password');
    await tab.getByRole('button', { name: 'Sign in' }).click();
    await tab.locator('#chat-heading').getByText('Grok Bot', { exact: true }).waitFor({ timeout: 15000 });
    await tab.locator('#draft').fill('Hi from my phone'); await tab.locator('#draft').press('Enter');
    await tab.getByText('Hello from the host', { exact: true }).waitFor({ timeout: 15000 });
    assert.ok(calls.some(([channel, args]) => channel === 'chat:send' && args[1] === 'Hi from my phone'));
    await tab.screenshot({ path: 'artifacts/visuals-web/web-access-phone.png' });
    // On a phone the Bot list slides in from the left and closes when a Bot is chosen.
    assert.equal(await tab.locator('.sidebar').evaluate(x => x.getBoundingClientRect().right <= 1), true, 'the Bot list starts hidden on a phone');
    await tab.getByRole('button', { name: 'Show Bots' }).click();
    await tab.waitForTimeout(450);
    assert.equal(await tab.locator('.sidebar').evaluate(x => Math.round(x.getBoundingClientRect().left)), 0);
    await tab.screenshot({ path: 'artifacts/visuals-web/web-access-phone-bots.png' });
    await tab.locator('#primary-bot .primary-card').first().click();
    await tab.waitForTimeout(450);
    assert.equal(await tab.locator('#workspace').evaluate(x => x.classList.contains('show-sidebar')), false);
    assert.equal(await tab.locator('.traffic').isVisible(), false, 'no fake window buttons in a browser');
    await tab.getByRole('button', { name: 'Show Bots' }).click(); await tab.waitForTimeout(400);
    await tab.getByRole('button', { name: 'Settings', exact: true }).click();
    await tab.getByRole('button', { name: 'Web access', exact: true }).click();
    await tab.getByText('Change web access on the computer that runs it.', { exact: false }).waitFor();
    assert.deepEqual(errors, []);
    console.log('PASS: web access — login, lockout, cookies, same-origin and header checks, host-only calls blocked, path traversal blocked, browser chat with live updates.');
  } finally { if (browser) await browser.close(); await web.stop(); }
})().catch(error => { console.error(error); process.exit(1); });
