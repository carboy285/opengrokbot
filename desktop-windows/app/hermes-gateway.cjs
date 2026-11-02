// Client for the authenticated local Hermes runs API. This module does not start
// a gateway or select it as a bot backend; lifecycle and approvals must be wired first.
const { randomUUID } = require('node:crypto');

class HermesGateway {
  constructor({ port, key, profile, fetchImpl = fetch }) {
    if (!Number.isInteger(port) || port < 1 || port > 65535 || typeof key !== 'string' || key.length < 16 || /[\r\n]/.test(key)) throw new Error('Invalid local Hermes gateway configuration.');
    if (profile !== undefined && !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(profile)) throw new Error('Invalid Hermes profile.');
    this.base = `http://127.0.0.1:${port}` + (profile ? `/p/${profile}` : '');
    this.key = key;
    this.fetch = fetchImpl;
  }
  async request(path, { method = 'GET', body, headers = {}, signal } = {}) {
    const response = await this.fetch(this.base + path, { method, redirect: 'error', signal, headers: { Authorization: `Bearer ${this.key}`, ...headers, ...(body ? { 'Content-Type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
    if (!response.ok) throw new Error(`Hermes gateway request failed (${response.status}).`);
    return response;
  }
  async start({ botID, input, requestID = randomUUID(), instructions }) {
    if (!/^[0-9a-f-]{36}$/i.test(botID) || typeof input !== 'string' || !input.trim() || input.length > 100000 || !/^[0-9a-f-]{36}$/i.test(requestID)) throw new Error('Invalid Hermes request.');
    if (instructions !== undefined && (typeof instructions !== 'string' || instructions.length > 100000)) throw new Error('Invalid Hermes instructions.');
    const response = await this.request('/v1/runs', { method: 'POST', headers: { 'X-Hermes-Session-Key': `opengrokbot-${botID}`, 'Idempotency-Key': requestID }, body: { input, ...(instructions === undefined ? {} : { instructions }) } });
    const result = await response.json();
    if (!/^run_[a-z0-9]+$/i.test(result.run_id || '')) throw new Error('Hermes returned an invalid run identifier.');
    return result.run_id;
  }
  runPath(runID) {
    if (!/^run_[a-z0-9]+$/i.test(runID)) throw new Error('Invalid Hermes run identifier.');
    return `/v1/runs/${runID}`;
  }
  async status(runID) { return (await this.request(this.runPath(runID))).json(); }
  async stop(runID) { return (await this.request(this.runPath(runID) + '/stop', { method: 'POST', body: {} })).json(); }
  async approve(runID, requestID, choice) {
    if (!['once', 'deny'].includes(choice) || typeof requestID !== 'string' || !requestID || requestID.length > 256) throw new Error('Invalid approval response.');
    return (await this.request(this.runPath(runID) + '/approval', { method: 'POST', body: { request_id: requestID, choice } })).json();
  }
  async events(runID, onEvent, { signal, lastSequence } = {}) {
    if (lastSequence !== undefined && (!Number.isSafeInteger(lastSequence) || lastSequence < 0)) throw new Error('Invalid Hermes event sequence.');
    const headers = lastSequence === undefined ? {} : { 'Last-Event-ID': String(lastSequence) };
    const response = await this.request(this.runPath(runID) + '/events', { headers, signal });
    if (!response.body) throw new Error('Hermes event stream is unavailable.');
    const decoder = new TextDecoder(); let buffer = '';
    for await (const chunk of response.body) {
      buffer += decoder.decode(chunk, { stream: true });
      if (buffer.length > 2 * 1024 * 1024) throw new Error('Hermes event stream exceeded its limit.');
      let match;
      while ((match = /\r?\n\r?\n/.exec(buffer))) {
        const frame = buffer.slice(0, match.index); buffer = buffer.slice(match.index + match[0].length);
        const data = frame.split(/\r?\n/).filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
        if (!data) continue;
        let event; try { event = JSON.parse(data); } catch { throw new Error('Hermes returned an invalid event.'); }
        if (event.run_id !== runID || typeof event.event !== 'string') throw new Error('Hermes returned an event for another run.');
        onEvent(event);
      }
    }
    buffer += decoder.decode();
    if (buffer.trim()) throw new Error('Hermes event stream ended unexpectedly.');
  }
}
module.exports = { HermesGateway };
