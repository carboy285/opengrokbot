// Same X25519/HKDF/AES-GCM mailbox protocol as the native Apple apps.
// Auth tokens, private keys and approvals are held by the main process only.
const crypto = require('node:crypto');
const os = require('node:os');
const BASE = 'https://kiaenmbtsgoxvfsijzzc.supabase.co';
const API_KEY = 'sb_publishable_iDMMZU6icZ1Wjwrv_zkbLw_W4pr-nCK';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
const lower = value => String(value).toLowerCase();
const fingerprint = key => crypto.createHash('sha256').update(Buffer.from(key, 'base64')).digest('hex').slice(0, 12).match(/../g).join(' ');
function identity() {
  const pair = crypto.generateKeyPairSync('x25519');
  return { id: crypto.randomUUID(), privateKey: pair.privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32).toString('base64'), publicKey: pair.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64') };
}
function keyFor(local, peer, owner) {
  const raw = Buffer.from(peer.public_key, 'base64');
  if (raw.length !== 32) throw new Error('The phone identity is invalid.');
  const privateKey = crypto.createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b656e04220420', 'hex'), Buffer.from(local.privateKey, 'base64')]), format: 'der', type: 'pkcs8' });
  const publicKey = crypto.createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b656e032100', 'hex'), raw]), format: 'der', type: 'spki' });
  const shared = crypto.diffieHellman({ privateKey, publicKey });
  const peers = [lower(local.id), lower(peer.id)].sort().join('|');
  return Buffer.from(crypto.hkdfSync('sha256', shared, Buffer.from(lower(owner)), Buffer.from('OpenGrokBot/relay/v1|' + peers), 32));
}
function context(owner, sender, recipient, id, kind) { return Buffer.from(`OpenGrokBot/1|${owner}|${sender}|${recipient}|${id}|${kind}`.toLowerCase()); }
function seal(local, peer, owner, id, body) {
  const data = Buffer.from(JSON.stringify(body));
  if (data.length > 5900000) throw new Error('The workspace is too large to send. Export older conversations first.');
  const expiry = Buffer.alloc(8); expiry.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 1000) + 90));
  const nonce = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', keyFor(local, peer, owner), nonce);
  cipher.setAAD(context(owner, local.id, peer.id, id, 'response'));
  return Buffer.concat([nonce, cipher.update(Buffer.concat([expiry, data])), cipher.final(), cipher.getAuthTag()]).toString('base64');
}
function open(local, peer, owner, packet) {
  if (!uuid(packet.id) || lower(packet.sender) !== lower(peer.id) || lower(packet.recipient) !== lower(local.id) || packet.kind !== 'request' || !Number.isFinite(Date.parse(packet.created_at)) || Math.abs(Date.now() - Date.parse(packet.created_at)) >= 120000) throw new Error('Unverified phone message.');
  if (typeof packet.ciphertext !== 'string' || packet.ciphertext.length > 8000048) throw new Error('Invalid message size.');
  const bytes = Buffer.from(packet.ciphertext, 'base64');
  if (bytes.length < 36 || bytes.length > 6000036) throw new Error('Invalid encrypted message.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', keyFor(local, peer, owner), bytes.subarray(0, 12));
  decipher.setAAD(context(owner, peer.id, local.id, packet.id, 'request')); decipher.setAuthTag(bytes.subarray(-16));
  const data = Buffer.concat([decipher.update(bytes.subarray(12, -16)), decipher.final()]);
  const expiry = Number(data.readBigUInt64BE());
  if (expiry <= Date.now() / 1000 || expiry >= Date.now() / 1000 + 120) throw new Error('Expired phone message.');
  return JSON.parse(data.subarray(8).toString('utf8'));
}
class CloudHost {
  constructor({ load, save, snapshot, execute, models, files, pins = () => [], applyPins = async () => {}, changed = () => {}, fetchImpl = fetch }) {
    Object.assign(this, { load, save, snapshot, execute, models, files, pins, applyPins, changed, fetchImpl });
    this.data = { identities: {}, approvals: {}, receipts: [], pinPending: {} }; this.devices = []; this.phase = 'signed-out'; this.feedback = 'Sign in with the same account as your iPhone.'; this.generation = 0; this.accountGeneration = 0; this.enabled = false; this.refreshing = null; this.saveQueue = Promise.resolve();
  }
  get active() { return this.enabled && !!this.data.session; }
  get local() { return this.data.identities[lower(this.data.session?.user.id)]; }
  async persist() {
    const snapshot = JSON.parse(JSON.stringify(this.data));
    const operation = this.saveQueue.catch(() => {}).then(() => this.save(snapshot)); this.saveQueue = operation; return operation;
  }
  status() {
    const owner = lower(this.data.session?.user.id), approvals = this.data.approvals[owner] || {};
    return { signedIn: !!this.data.session, email: this.data.session?.user.email || '', enabled: this.active, phase: this.phase, feedback: this.feedback, lastHeartbeat: this.lastHeartbeat, lastRequest: this.lastRequest, fingerprint: this.local ? fingerprint(this.local.publicKey) : '', pinSyncMessage: this.pinSyncMessage || '', phones: this.devices.filter(x => x.kind === 'controller').map(x => ({ id: x.id, name: x.name, fingerprint: fingerprint(x.public_key), approved: approvals[lower(x.id)] === x.public_key, online: x.available && Date.now() - Date.parse(x.last_seen) < 65000 })) };
  }
  transition(phase, feedback) { const different = phase !== this.phase || feedback !== this.feedback; this.phase = phase; this.feedback = feedback; if (different) this.changed(this.status()); }
  async restore() {
    try { const saved = await this.load(); if (saved) this.data = saved; this.data.identities ||= {}; this.data.approvals ||= {}; this.data.receipts ||= []; this.data.pinPending ||= {}; if (this.data.session && this.data.enabled) this.start(); else this.transition(this.data.session ? 'disabled' : 'signed-out', this.data.session ? 'Phone access is off.' : 'Sign in with the same account as your iPhone.'); if(this.data.session)this.startPreferences(); }
    catch { this.transition('locked', 'Unlock Windows device encryption, then reopen OpenGrokBot to restore phone access.'); }
  }
  async raw(path, { body, method = 'POST', token, signal } = {}) {
    const response = await this.fetchImpl(BASE + path, { method, redirect: 'error', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(20000)]) : AbortSignal.timeout(20000), headers: { apikey: API_KEY, 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
    const data = await response.text(); if (Buffer.byteLength(data) > 16000000) throw new Error('The account response was too large.');
    let value; try { value = data ? JSON.parse(data) : null; } catch { throw new Error('The account service returned an invalid response.'); }
    if (!response.ok) throw new Error(String(value?.msg || value?.message || value?.error_description || 'The account service is unavailable. Reconnect and try again.').slice(0, 400));
    return value;
  }
  async token() {
    const session = this.data.session; if (!session) throw new Error('Sign in first.');
    if (session.expires_at > Date.now() / 1000 + 90) return session.access_token;
    if (!this.refreshing) {
      const generation = this.accountGeneration;
      this.refreshing = (async () => { const next = await this.raw('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh_token } }); if (generation !== this.accountGeneration || this.data.session?.user.id !== session.user.id) throw new Error('The account changed.'); next.expires_at ||= Date.now() / 1000 + (next.expires_in || 3600); this.data.session = next; await this.persist(); return next.access_token; })().finally(() => { this.refreshing = null; });
    }
    return this.refreshing;
  }
  async request(path, body, method = 'POST') { const generation = this.accountGeneration, signal = this.abort?.signal; const token = await this.token(); const result = await this.raw(path, { body, method, token, signal }); if (generation !== this.accountGeneration) throw new Error('The account changed.'); return result; }
  async signIn(email, password, create = false) {
    if (typeof email !== 'string' || !email.includes('@') || email.length > 320 || typeof password !== 'string' || !password || password.length > 4096) throw new Error('Enter your email and password.');
    const generation = this.accountGeneration;
    const session = await this.raw(create ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password', { body: { email: email.trim(), password } });
    if (generation !== this.accountGeneration) throw new Error('The account changed. Try signing in again.');
    if (!session?.access_token) { this.transition('confirm-email', 'Check your email to confirm the account, then sign in.'); return this.status(); }
    this.abort?.abort(); this.generation++; this.accountGeneration++; this.refreshing = null; this.data.session = session; session.expires_at ||= Date.now() / 1000 + (session.expires_in || 3600);
    const owner = lower(session.user.id); this.data.identities[owner] ||= identity(); this.data.approvals[owner] ||= {}; this.devices = []; this.data.enabled = true; await this.persist(); this.start(); return this.status();
  }
  async signOut() {
    const old = this.data.session; this.preferencesAbort?.abort(); this.abort?.abort(); this.generation++; this.accountGeneration++; this.refreshing = null; this.enabled = false; this.devices = []; this.data.session = null; this.data.enabled = false; await this.persist(); this.transition('signed-out', 'Signed out on this computer.');
    if (old) this.raw('/auth/v1/logout?scope=local', { body: {}, token: old.access_token }).catch(() => {}); return this.status();
  }
  async setEnabled(value) {
    if (!this.data.session) throw new Error('Sign in first.');
    if (value) { this.data.enabled = true; await this.persist(); this.start(); }
    else { this.abort?.abort(); this.generation++; this.abort = new AbortController(); this.enabled = false; this.data.enabled = false; await this.persist(); await this.sync(false).catch(() => {}); this.transition('disabled', 'Phone access is off.'); }
    return this.status();
  }
  async approve(id, allowed) {
    const phone = this.devices.find(x => lower(x.id) === lower(id) && x.kind === 'controller'); if (!phone) throw new Error('Wait for this phone to appear, then compare its fingerprint.');
    const owner = lower(this.data.session.user.id); this.data.approvals[owner] ||= {};
    if (allowed) this.data.approvals[owner][lower(id)] = phone.public_key; else delete this.data.approvals[owner][lower(id)];
    await this.persist(); this.changed(this.status()); return this.status();
  }
  approved(peer) { return this.data.approvals[lower(this.data.session?.user.id)]?.[lower(peer.id)] === peer.public_key; }
  async sync(available = true) {
    const local = this.local; if (!local) throw new Error('Sign in first.');
    await this.request('/rest/v1/rpc/opengrok_register_device', { device_id: local.id, device_name: os.hostname(), device_kind: 'host', device_key: local.publicKey, is_available: String(available) });
    const devices = await this.request('/rest/v1/opengrok_devices?select=id,name,kind,public_key,last_seen,available&order=last_seen.desc', null, 'GET');
    if (!Array.isArray(devices) || devices.some(x => !uuid(x.id) || !['host', 'controller'].includes(x.kind) || typeof x.public_key !== 'string' || Buffer.from(x.public_key, 'base64').length !== 32)) throw new Error('Invalid device registry response.');
    this.devices = devices; this.lastHeartbeat = new Date().toISOString(); this.changed(this.status());
  }
  async ack(packet) { await this.request('/rest/v1/rpc/opengrok_ack', { device_id: this.local.id, packet_id: packet.id, packet_kind: packet.kind }); }
  async respond(request) {
    if (!request || !['GET', 'POST'].includes(request.method) || typeof request.target !== 'string' || request.target.length > 2048 || !request.target.startsWith('/') || request.target.startsWith('//')) throw new Error('Invalid phone request.');
    const url = new URL(request.target, BASE);
    if (request.method === 'GET') {
      if (url.pathname === '/v1/state') { const snapshot = this.snapshot(); return url.searchParams.get('since') === snapshot.revision ? { status: 204, body: '' } : this.response(200, { snapshot, removedEntries: [] }); }
      if (url.pathname === '/v1/models') return this.response(200, await this.models(url.searchParams.get('provider')));
      if (url.pathname === '/v1/files') return this.response(200, await this.files(url.searchParams.get('bot')));
    }
    if (request.method !== 'POST' || url.pathname !== '/v1/command') return this.response(404, { error: 'Unknown endpoint.' });
    if (typeof request.body !== 'string' || request.body.length > 174764) throw new Error('Invalid command size.');
    const bytes = Buffer.from(request.body, 'base64'); if (bytes.length > 131072) throw new Error('Command too large.');
    const command = JSON.parse(bytes.toString('utf8')); if (!uuid(command.requestID)) throw new Error('Invalid command.');
    const key = lower(this.data.session.user.id) + '|' + lower(command.requestID);
    if (!this.data.receipts.includes(key)) { await this.execute(command); this.data.receipts = [...this.data.receipts.slice(-255), key]; await this.persist(); }
    return this.response(200, { accepted: true });
  }
  response(status, body) { return { status, body: Buffer.from(JSON.stringify(body)).toString('base64') }; }
  start() {
    if (!this.data.session || !this.local) return;
    this.abort?.abort(); const generation = ++this.generation; this.abort = new AbortController(); this.enabled = true; this.transition('connecting', 'Connecting to your account…');
    this.startPreferences();
    this.worker(generation).catch(error => { if (generation === this.generation) this.transition('offline', error.message); });
  }
  async worker(generation) {
    let heartbeat = 0, backoff = 1000, recent = 0;
    while (generation === this.generation && this.active) {
      let wait = Date.now() - recent < 10000 ? 250 : 700;
      try {
        if (Date.now() >= heartbeat) { await this.sync(); heartbeat = Date.now() + 20000; }
        const packets = await this.request('/rest/v1/rpc/opengrok_poll', { device_id: this.local.id });
        if (!Array.isArray(packets)) throw new Error('Invalid mailbox response.');
        for (const packet of packets) {
          if (generation !== this.generation) return;
          if (!this.devices.some(x => lower(x.id) === lower(packet.sender))) await this.sync();
          const peer = this.devices.find(x => lower(x.id) === lower(packet.sender) && x.kind === 'controller');
          if (!peer) { await this.ack(packet); continue; }
          let request; try { request = open(this.local, peer, this.data.session.user.id, packet); } catch { await this.ack(packet); continue; }
          recent = Date.now(); this.lastRequest = new Date().toISOString();
          let response;
          if (!this.approved(peer)) { this.transition('approval-required', `Approve ${peer.name} after comparing the fingerprint shown on the iPhone.`); response = this.response(403, { error: 'Approve this phone in Windows Settings → Computer. Compare its fingerprint before approving.' }); }
          else { try { response = await this.respond(request); } catch (error) { response = this.response(409, { error: error.publicMessage || 'The request could not be completed. Check provider setup and the desktop conversation.' }); } }
          if (generation !== this.generation || !this.active) return;
          if (response.status !== 403 && !this.approved(peer)) { await this.ack(packet); continue; }
          let payload; try { payload = seal(this.local, peer, this.data.session.user.id, packet.id, response); } catch (error) { payload = seal(this.local, peer, this.data.session.user.id, packet.id, this.response(413, { error: error.message })); }
          await this.request('/rest/v1/rpc/opengrok_send', { packet_id: packet.id, from_device: this.local.id, to_device: peer.id, packet_kind: 'response', payload }); await this.ack(packet);
          if (response.status !== 403) this.transition('online', 'Connected. Approved phones can use this computer’s Bots.');
        }
        if (!packets.length && this.phase !== 'approval-required') this.transition('online', 'Phone access is ready. Keep this computer awake.');
        backoff = 1000;
      } catch (error) { if (generation !== this.generation) return; this.transition('offline', error.message + ' Retrying automatically.'); heartbeat = 0; wait = backoff; backoff = Math.min(15000, backoff * 2); }
      await new Promise(resolve => { const timer = setTimeout(done, wait); const signal = this.abort.signal; function done() { clearTimeout(timer); signal.removeEventListener('abort', done); resolve(); } signal.addEventListener('abort', done, { once: true }); if (signal.aborted) done(); });
    }
  }
  async queuePin(bot, value) {
    if (!this.data.session) return;
    if (!uuid(bot) || typeof value !== 'boolean') throw new Error('Invalid pin preference.');
    const owner = lower(this.data.session.user.id); this.data.pinPending ||= {}; this.data.pinPending[owner] ||= {};
    this.data.pinPending[owner][lower(bot)] = value; await this.persist(); this.startPreferences();
  }
  startPreferences() {
    if (!this.data.session || !this.local || this.preferenceTask && this.preferenceAccount === this.accountGeneration) return;
    this.preferencesAbort?.abort(); const signal = new AbortController(); this.preferencesAbort = signal;
    const epoch = this.accountGeneration; this.preferenceAccount = epoch;
    this.preferenceTask = this.preferenceWorker(epoch, signal.signal).catch(() => {}).finally(() => { if (this.preferenceAccount === epoch) this.preferenceTask = null; });
  }
  async preferenceWorker(epoch, signal) {
    let backoff = 2000;
    while (!signal.aborted && epoch === this.accountGeneration && this.data.session) {
      let wait = 2000;
      try {
        const owner = lower(this.data.session.user.id), host = this.local.id;
        if (!this.devices.some(device => lower(device.id) === lower(host))) await this.sync(this.active);
        this.data.pinPending ||= {}; this.data.pinPending[owner] ||= {};
        const pending = this.data.pinPending[owner], hadPending = Object.keys(pending).length > 0;
        for (const [id, value] of Object.entries(pending)) {
          await this.request('/rest/v1/rpc/opengrok_set_bot_pin', { host_device: host, bot: id, pinned: value });
          if (signal.aborted || epoch !== this.accountGeneration) return;
          if (pending[id] === value) delete pending[id];
        }
        if (hadPending) await this.persist();
        const rows = await this.request('/rest/v1/opengrok_bot_pins?select=bot_id,is_pinned&host_id=eq.' + host, null, 'GET');
        if (!Array.isArray(rows) || rows.some(row => !uuid(row.bot_id) || typeof row.is_pinned !== 'boolean')) throw new Error('Invalid pin settings.');
        const existing = new Set(rows.map(row => lower(row.bot_id)));
        for (const bot of this.pins()) {
          if (existing.has(lower(bot.bot_id)) || !bot.is_pinned && !bot.explicit) continue;
          const result = await this.request('/rest/v1/rpc/opengrok_set_bot_pin', { host_device: host, bot: bot.bot_id, pinned: bot.is_pinned, only_if_missing: true });
          if (result?.[0]) rows.push(result[0]);
        }
        if (signal.aborted || epoch !== this.accountGeneration) return;
        await this.applyPins(rows.filter(row => !Object.hasOwn(pending, lower(row.bot_id))));
        if (this.pinSyncMessage) { this.pinSyncMessage = ''; this.changed(this.status()); }
        backoff = 2000;
      } catch {
        if (signal.aborted || epoch !== this.accountGeneration) return;
        this.pinSyncMessage = 'Pins are saved locally and will sync when the account service reconnects.'; this.changed(this.status());
        wait = backoff; backoff = Math.min(15000, backoff * 2);
      }
      await new Promise(resolve => { const timer = setTimeout(done, wait); function done() { clearTimeout(timer); signal.removeEventListener('abort', done); resolve(); } signal.addEventListener('abort', done, { once: true }); if(signal.aborted)done(); });
    }
  }
  stop() { this.preferencesAbort?.abort(); this.abort?.abort(); this.generation++; this.enabled = false; }
}
module.exports = { CloudHost, seal, open, identity, fingerprint };
