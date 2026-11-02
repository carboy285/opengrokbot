// Lifecycle for a packaged Hermes gateway. Each bot receives its own Hermes
// home and process; existing OpenGrokBot data is never moved or deleted.
const { spawn } = require('node:child_process');
const { randomBytes } = require('node:crypto');
const net = require('node:net');
const path = require('node:path');
const { mkdir, stat } = require('node:fs/promises');
const { HermesGateway } = require('./hermes-gateway.cjs');

async function availablePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => { const port = server.address().port; server.close(error => error ? reject(error) : resolve(port)); });
  });
}

class HermesRuntime {
  constructor({ executable, dataDirectory, spawnImpl = spawn, fetchImpl = fetch }) {
    if (!path.isAbsolute(executable) || !path.isAbsolute(dataDirectory)) throw new Error('Hermes runtime paths must be absolute.');
    this.executable = executable; this.dataDirectory = dataDirectory; this.spawn = spawnImpl; this.fetch = fetchImpl;
    this.instances = new Map(); this.starting = new Map();
  }
  async start(botID) {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(botID)) throw new Error('Invalid Bot identifier.');
    if (this.instances.has(botID)) return this.instances.get(botID).client;
    if (this.starting.has(botID)) return this.starting.get(botID);
    const pending = this.launch(botID).finally(() => this.starting.delete(botID));
    this.starting.set(botID, pending); return pending;
  }
  async launch(botID) {
    if (!(await stat(this.executable)).isFile()) throw new Error('The bundled Hermes runtime is missing. Reinstall OpenGrokBot.');
    const home = path.join(this.dataDirectory, botID.toLowerCase());
    await mkdir(home, { recursive: true, mode: 0o700 });
    const port = await availablePort(), key = randomBytes(32).toString('hex');
    // Do not inherit opt-in Hermes overrides or model provider secrets from the app.
    const env = Object.fromEntries(['PATH','Path','HOME','USERPROFILE','SYSTEMROOT','SystemRoot','TEMP','TMP','TMPDIR','LANG','SSL_CERT_FILE'].filter(name => process.env[name]).map(name => [name, process.env[name]]));
    Object.assign(env, { HERMES_HOME: home, API_SERVER_ENABLED: 'true', API_SERVER_HOST: '127.0.0.1', API_SERVER_PORT: String(port), API_SERVER_KEY: key });
    const child = this.spawn(this.executable, ['gateway', 'run', '--quiet'], { cwd: home, env, windowsHide: true, shell: false, stdio: 'ignore' });
    let exited = false; child.once('error', () => { exited = true; }); child.once('exit', () => { exited = true; if (this.instances.get(botID)?.child === child) this.instances.delete(botID); });
    const client = new HermesGateway({ port, key, fetchImpl: this.fetch });
    try {
      const deadline = Date.now() + 60000;
      while (Date.now() < deadline) {
        if (exited) throw new Error('The bundled Hermes gateway stopped during startup.');
        try {
          const response = await client.request('/health/detailed', { signal: AbortSignal.timeout(1500) });
          const health = await response.json();
          if (health && !exited) { this.instances.set(botID, { child, client }); return client; }
        } catch { /* Wait for the authenticated gateway to start. */ }
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      throw new Error('The bundled Hermes gateway did not become ready.');
    } catch (error) { if (!exited) child.kill(); throw error; }
  }
  async stopAll() {
    await Promise.allSettled([...this.starting.values()]);
    for (const { child } of this.instances.values()) child.kill();
    this.instances.clear();
  }
}
module.exports = { HermesRuntime };
