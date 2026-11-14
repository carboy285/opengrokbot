'use strict';
// Web access (0.9.7): use OpenGrokBot from another device's browser, over your Wi-Fi or Tailscale.
// The same interface is served with a small bridge that turns its calls into HTTPS/HTTP requests to this app.
// Only channels that are safe from another device are reachable; everything else stays on this computer.

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const { localHost } = require('./remote-host.cjs');

// Calls another device may make. Secrets (vault, API keys, saved logins), host dialogs, VMs, voice, updates,
// backups and web access settings themselves are deliberately absent.
const INVOKE = new Set([
  'workspace:load', 'workspace:save', 'chat:send', 'chat:retry', 'chat:stop', 'chat:pin', 'entry:delete', 'entry:react',
  'bot:touch', 'bot:organize', 'bots:reorder', 'bot:configure', 'bot:image', 'models:list', 'files:list', 'drafts:load', 'drafts:save',
  'setup:status', 'setup:scan', 'composio:status', 'proactive:status', 'proactive:configure', 'proactive:check', 'headsup:snooze', 'headsup:dismiss',
  'headsup:mute', 'tasks:cancel', 'tasks:pause', 'approval:answer', 'approval:pending', 'media-keys:status', 'cloud:status', 'rules:get',
  'connected-apps:allow-get', 'ollama:models'
]);
// Events another device receives.
const EVENTS = new Set(['workspace:changed', 'proactive:changed', 'approval:request', 'bot:open']);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2' };
const SESSION_DAYS = 14;
const USER = /^[A-Za-z0-9._@-]{3,64}$/;

/** "scrypt$salt$hash", base64. */
function hashPassword(password, salt = crypto.randomBytes(16)) {
  const hash = crypto.scryptSync(String(password).normalize('NFKC'), salt, 32, { N: 16384, r: 8, p: 1 });
  return `scrypt$${salt.toString('base64')}$${hash.toString('base64')}`;
}
function checkPassword(password, stored) {
  const [kind, salt, hash] = String(stored || '').split('$');
  if (kind !== 'scrypt' || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64'), actual = crypto.scryptSync(String(password).normalize('NFKC'), Buffer.from(salt, 'base64'), expected.length, { N: 16384, r: 8, p: 1 });
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}
/** A password worth having: 10+ characters. Short ones are rejected rather than stored. */
function passwordProblem(password) {
  if (typeof password !== 'string' || password.length < 10) return 'Use a password of at least 10 characters.';
  if (password.length > 200) return 'Use a password of up to 200 characters.';
  return null;
}

/** Builds the bridge script from preload.cjs, so the web version calls exactly what the desktop window calls. */
function bridgeTable(preloadSource) {
  const invoke = {}, listen = {};
  for (const match of preloadSource.matchAll(/(\w+)\s*:\s*(?:\([^)]*\)|\w+)\s*=>\s*ipcRenderer\.invoke\(\s*'([^']+)'/g)) invoke[match[1]] = match[2];
  for (const match of preloadSource.matchAll(/(\w+)\s*:\s*callback\s*=>\s*\{[^}]*?ipcRenderer\.on\(\s*'([^']+)'/g)) listen[match[1]] = match[2];
  return { invoke, listen };
}
function bridgeScript(table) {
  const invoke = Object.fromEntries(Object.entries(table.invoke).filter(([, channel]) => INVOKE.has(channel)));
  const listen = Object.fromEntries(Object.entries(table.listen).filter(([, channel]) => EVENTS.has(channel)));
  return `'use strict';
// Web access bridge: the desktop app's calls become requests to the computer that runs OpenGrokBot.
(() => {
  const invokeTable = ${JSON.stringify(invoke)}, listenTable = ${JSON.stringify(listen)};
  const listeners = {};
  const call = async (channel, args) => {
    try {
      const response = await fetch('/api/invoke', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', 'X-OGB-Request': '1' }, body: JSON.stringify({ channel, args }) });
      if (response.status === 401) { location.href = '/login'; return { ok: false, error: 'Signed out. Sign in again.' }; }
      return await response.json();
    } catch { return { ok: false, error: 'The computer running OpenGrokBot could not be reached.' }; }
  };
  const desktop = { webAccess: true };
  for (const [name, channel] of Object.entries(invokeTable)) desktop[name] = (...args) => call(channel, args);
  for (const [name, channel] of Object.entries(listenTable)) desktop[name] = callback => { (listeners[channel] ||= []).push(callback); return () => { listeners[channel] = listeners[channel].filter(x => x !== callback); }; };
  // Things that happen on this device rather than on the host.
  const open = url => { window.open(url, '_blank', 'noopener,noreferrer'); return Promise.resolve({ ok: true }); };
  desktop.openDocs = open; desktop.openLink = open; desktop.openUpdate = open; desktop.headsUpJoin = open;
  desktop.windowAction = () => Promise.resolve({ ok: true });
  desktop.export = async text => { const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' })); link.download = 'OpenGrokBot-conversation.txt'; link.click(); URL.revokeObjectURL(link.href); return { ok: true, value: true }; };
  desktop.botMedia = async (bot, file) => {
    const response = await fetch('/api/media?bot=' + encodeURIComponent(bot) + '&file=' + encodeURIComponent(file), { credentials: 'same-origin', headers: { 'X-OGB-Request': '1' } });
    if (!response.ok) return { ok: true, value: null };
    return { ok: true, value: { type: response.headers.get('content-type') || 'video/mp4', data: await response.arrayBuffer() } };
  };
  const unavailable = () => Promise.resolve({ ok: false, error: 'Open OpenGrokBot on the computer that runs it to do this.' });
  window.desktop = new Proxy(desktop, { get: (target, name) => name in target ? target[name] : (typeof name === 'string' && /^[a-z]\\w*$/.test(name) && !name.startsWith('on') ? unavailable : undefined) });
  const connect = () => {
    const events = new EventSource('/api/events');
    events.onmessage = message => { let value; try { value = JSON.parse(message.data); } catch { return; } for (const callback of listeners[value.channel] || []) try { callback(value.value); } catch {} };
    events.onerror = () => { events.close(); setTimeout(connect, 3000); };
  };
  connect();
})();
`;
}

const LOGIN_CSS = `:root{color-scheme:light dark;--bg:#0f0f10;--panel:#1c1c1e;--text:#ececee;--muted:#8e8e93;--line:#ffffff1a}
@media (prefers-color-scheme:light){:root{--bg:#fcfcfc;--panel:#f0f0f2;--text:#111;--muted:#6c6c70;--line:#0000001a}}
*{box-sizing:border-box}body{margin:0;min-height:100dvh;display:grid;place-items:center;background:var(--bg);color:var(--text);font:16px/1.45 system-ui,-apple-system,'Segoe UI',sans-serif;padding:16px}
form{width:min(380px,100%);background:var(--panel);border:1px solid var(--line);border-radius:22px;padding:28px;display:grid;gap:14px}
h1{margin:0 0 4px;font-size:24px;font-weight:600;letter-spacing:-.02em}p{margin:0;color:var(--muted);font-size:14px}
label{display:grid;gap:6px;font-size:14px;color:var(--muted)}input{font:inherit;color:var(--text);background:var(--bg);border:1px solid var(--line);border-radius:12px;padding:11px 13px}
button{font:inherit;font-weight:600;border:0;border-radius:99px;padding:12px;background:var(--text);color:var(--bg);cursor:pointer}button:active{transform:scale(.98)}
.error{color:#ff453a}`;
function loginPage(message = '') {
  const escape = value => String(value).replace(/[&<>"']/g, ch => `&#${ch.charCodeAt(0)};`);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OpenGrokBot · Sign in</title><link rel="stylesheet" href="/login.css"></head>
<body><form method="post" action="/login"><h1>OpenGrokBot</h1><p>Sign in with the username and password set in Settings → Web access on the computer that runs it.</p>${message ? `<p class="error" role="alert">${escape(message)}</p>` : ''}
<label>Username<input name="username" autocomplete="username" required autofocus></label><label>Password<input name="password" type="password" autocomplete="current-password" required></label><button type="submit">Sign in</button></form></body></html>`;
}

class WebAccess {
  /**
   * deps: invoke(channel, args) → {ok, value|error} · config() → {username, passwordHash} · rendererDir · preloadFile
   */
  constructor(deps) {
    this.deps = deps;
    this.server = null;
    this.sessions = new Map();
    this.failures = new Map();
    this.clients = new Set();
    this.secure = false;
  }
  get active() { return !!this.server; }

  async start({ port = 8765, lan = false, secure = false } = {}) {
    if (this.server) await this.stop();
    this.secure = secure; this.lan = lan;
    this.bridge = bridgeScript(bridgeTable(await fs.readFile(this.deps.preloadFile, 'utf8')));
    const server = http.createServer({ maxHeaderSize: 16384 }, (req, res) => this.route(req, res).catch(() => this.send(res, 500, 'text/plain', 'Something went wrong.')));
    server.headersTimeout = 15000; server.requestTimeout = 0; server.keepAliveTimeout = 5000; server.maxConnections = 64;
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, lan ? '0.0.0.0' : '127.0.0.1', resolve); });
    this.server = server;
    this.keepAlive = setInterval(() => { for (const client of this.clients) client.write(': keep-alive\n\n'); }, 25000); this.keepAlive.unref?.();
    return server.address().port;
  }
  async stop() {
    clearInterval(this.keepAlive);
    for (const client of this.clients) client.end();
    this.clients.clear();
    const server = this.server; this.server = null;
    if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  }
  signOutEverywhere() { this.sessions.clear(); for (const client of this.clients) client.end(); this.clients.clear(); }

  /** Pushes an app event to every signed-in browser. */
  broadcast(channel, value) {
    if (!EVENTS.has(channel) || !this.clients.size) return;
    const message = `data: ${JSON.stringify({ channel, value })}\n\n`;
    for (const client of this.clients) client.write(message);
  }

  send(res, status, type, body, headers = {}) {
    if (res.headersSent || res.destroyed) return;
    res.writeHead(status, { 'Content-Type': type, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin', 'X-Frame-Options': 'DENY', 'Cache-Control': 'no-store', ...headers });
    res.end(body);
  }
  session(req) {
    const token = /(?:^|;\s*)ogb_session=([A-Za-z0-9_-]{43})/.exec(req.headers.cookie || '')?.[1];
    const found = token && this.sessions.get(token);
    if (!found || found.expires < Date.now()) { if (token) this.sessions.delete(token); return null; }
    return found;
  }
  sameOrigin(req) {
    const origin = req.headers.origin; if (!origin) return true;
    try { return new URL(origin).host === req.headers.host; } catch { return false; }
  }
  async body(req, limit) {
    const chunks = []; let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > limit) throw Object.assign(new Error('too large'), { status: 413 }); chunks.push(chunk); }
    return Buffer.concat(chunks).toString('utf8');
  }

  async route(req, res) {
    const remote = String(req.socket.remoteAddress || '').replace(/^::ffff:/, '');
    // On Wi-Fi, only devices on private networks (home Wi-Fi, Tailscale) may connect.
    if (this.lan && !localHost(remote)) return this.send(res, 403, 'text/plain', 'Not allowed from this network.');
    const url = new URL(req.url || '/', 'http://localhost');
    if (req.method === 'GET' && url.pathname === '/login.css') return this.send(res, 200, 'text/css; charset=utf-8', LOGIN_CSS, { 'Cache-Control': 'max-age=3600' });
    if (url.pathname === '/login') return this.login(req, res, remote);
    if (req.method === 'POST' && url.pathname === '/logout') {
      const token = /(?:^|;\s*)ogb_session=([A-Za-z0-9_-]{43})/.exec(req.headers.cookie || '')?.[1]; if (token) this.sessions.delete(token);
      return this.send(res, 303, 'text/plain', '', { Location: '/login', 'Set-Cookie': this.cookie('', 0) });
    }
    if (!this.session(req)) {
      if (url.pathname.startsWith('/api/')) return this.send(res, 401, 'application/json', '{"ok":false,"error":"Sign in again."}');
      return this.send(res, 303, 'text/plain', '', { Location: '/login' });
    }
    if (url.pathname === '/api/invoke') return this.invoke(req, res);
    if (url.pathname === '/api/events') return this.events(req, res);
    if (url.pathname === '/api/media') return this.media(req, res, url);
    if (req.method !== 'GET') return this.send(res, 405, 'text/plain', 'Not allowed.');
    return this.file(res, url.pathname);
  }

  cookie(token, maxAge) { return `ogb_session=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAge}${this.secure ? '; Secure' : ''}`; }

  async login(req, res, remote) {
    if (req.method === 'GET') return this.send(res, 200, 'text/html; charset=utf-8', loginPage(), { 'Content-Security-Policy': "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'" });
    if (req.method !== 'POST' || !this.sameOrigin(req)) return this.send(res, 403, 'text/plain', 'Not allowed.');
    const failure = this.failures.get(remote) || { count: 0, until: 0 };
    const page = (status, message) => this.send(res, status, 'text/html; charset=utf-8', loginPage(message), { 'Content-Security-Policy': "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'" });
    if (failure.until > Date.now()) return page(429, `Too many tries. Wait ${Math.ceil((failure.until - Date.now()) / 1000)} seconds.`);
    let form; try { form = new URLSearchParams(await this.body(req, 4096)); } catch { return page(413, 'Try again.'); }
    const { username, passwordHash } = this.deps.config();
    const nameOK = typeof username === 'string' && username.length > 0 && crypto.timingSafeEqual(crypto.createHash('sha256').update(String(form.get('username') || '')).digest(), crypto.createHash('sha256').update(username).digest());
    const passwordOK = checkPassword(form.get('password') || '', passwordHash);
    if (!nameOK || !passwordOK) {
      failure.count++; if (failure.count >= 5) failure.until = Date.now() + Math.min(3600000, 30000 * 2 ** (failure.count - 5));
      this.failures.set(remote, failure);
      return page(401, 'That username and password don’t match.');
    }
    this.failures.delete(remote);
    const token = crypto.randomBytes(32).toString('base64url');
    this.sessions.set(token, { expires: Date.now() + SESSION_DAYS * 86400000, user: username });
    if (this.sessions.size > 200) this.sessions.delete(this.sessions.keys().next().value);
    return this.send(res, 303, 'text/plain', '', { Location: '/', 'Set-Cookie': this.cookie(token, SESSION_DAYS * 86400) });
  }

  async invoke(req, res) {
    if (req.method !== 'POST' || req.headers['x-ogb-request'] !== '1' || !this.sameOrigin(req)) return this.send(res, 403, 'application/json', '{"ok":false,"error":"Not allowed."}');
    let request; try { request = JSON.parse(await this.body(req, 32 * 1024 * 1024)); } catch (error) { return this.send(res, error.status || 400, 'application/json', '{"ok":false,"error":"Invalid request."}'); }
    if (!request || typeof request.channel !== 'string' || !INVOKE.has(request.channel) || !Array.isArray(request.args) || request.args.length > 8) return this.send(res, 403, 'application/json', '{"ok":false,"error":"Open OpenGrokBot on the computer that runs it to do this."}');
    const result = await this.deps.invoke(request.channel, request.args);
    return this.send(res, 200, 'application/json', JSON.stringify(result));
  }

  events(req, res) {
    if (req.method !== 'GET') return this.send(res, 405, 'text/plain', 'Not allowed.');
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', Connection: 'keep-alive' });
    res.write(': connected\n\n');
    this.clients.add(res);
    req.on('close', () => this.clients.delete(res));
  }

  async media(req, res, url) {
    if (req.headers['x-ogb-request'] !== '1') return this.send(res, 403, 'text/plain', 'Not allowed.');
    const result = await this.deps.invoke('bot:media', [url.searchParams.get('bot') || '', url.searchParams.get('file') || '']);
    if (!result?.ok || !result.value?.data) return this.send(res, 404, 'text/plain', 'Not found.');
    return this.send(res, 200, result.value.type, Buffer.from(result.value.data));
  }

  async file(res, pathname) {
    const name = pathname === '/' ? 'index.html' : decodeURIComponent(pathname.slice(1));
    if (name === 'web-bridge.js') return this.send(res, 200, TYPES['.js'], this.bridge);
    const root = path.resolve(this.deps.rendererDir), target = path.resolve(root, name), type = TYPES[path.extname(target).toLowerCase()];
    if (!target.startsWith(root + path.sep) || !type || /(^|\/)\./.test(name)) return this.send(res, 404, 'text/plain', 'Not found.');
    let body; try { body = await fs.readFile(target); } catch { return this.send(res, 404, 'text/plain', 'Not found.'); }
    if (name === 'index.html') {
      // The bridge loads first, and the page may talk to this server (and nowhere else).
      body = body.toString('utf8').replace("connect-src 'none'", "connect-src 'self'").replace('<link rel="stylesheet" href="style.css">', '<link rel="stylesheet" href="style.css"><script src="web-bridge.js"></script>');
    }
    return this.send(res, 200, type, body, { 'Cache-Control': name === 'index.html' ? 'no-store' : 'max-age=300' });
  }
}

module.exports = { WebAccess, INVOKE, EVENTS, hashPassword, checkPassword, passwordProblem, bridgeTable, bridgeScript, USER };
