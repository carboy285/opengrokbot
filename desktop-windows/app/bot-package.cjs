'use strict';
// Copy a Bot between computers on one account: its job, provider settings, memory, chat history, paused routines and small Knowledge
// files. The JSON shape is shared with the Mac app (BotPackage). A package from another computer is untrusted, so import rebuilds every
// field with fresh IDs and hard limits.
const { randomUUID } = require('node:crypto');
const path = require('node:path');
const schedules = require('./schedules.cjs');

const FORMAT = 'opengrokbot-bot-package';
const MAX_BYTES = 2_300_000, MAX_ENTRIES = 2000, MAX_KNOWLEDGE_BYTES = 800_000, MAX_FILE_BYTES = 8_000_000;
const KNOWLEDGE_EXTENSIONS = new Set(['.pdf', '.txt', '.md', '.markdown', '.csv', '.tsv', '.json', '.log', '.html', '.htm', '.xml', '.yaml', '.yml']);
const PROVIDERS = new Set(['codex', 'claude', 'grok', 'opencode', 'gemini']);
const iso = value => { const t = Date.parse(value); return Number.isFinite(t) ? new Date(t).toISOString().replace(/\.\d+Z$/, 'Z') : '2001-01-01T00:00:00Z'; };

/** @param {{state:any, botID:string, sourceName:string, files:{name:string,data:Buffer}[]}} input */
function build({ state, botID, sourceName, files = [] }) {
  const bot = state.bots.find(x => x.id.toLowerCase() === String(botID).toLowerCase());
  if (!bot || bot.memberIDs) throw new Error('Choose an individual Bot to copy.');
  let entries = state.entries.filter(x => x.botID.toLowerCase() === bot.id.toLowerCase()).map(({ detail, ...x }) => ({ ...x, state: x.state === 'streaming' ? 'complete' : x.state, date: iso(x.date) }));
  if (entries.length > MAX_ENTRIES) entries = entries.slice(-MAX_ENTRIES);
  const knowledge = []; let used = 0;
  for (const file of files.slice(0, 50)) {
    if (!KNOWLEDGE_EXTENSIONS.has(path.extname(file.name).toLowerCase()) || file.data.length > MAX_FILE_BYTES || used + file.data.length > MAX_KNOWLEDGE_BYTES) continue;
    used += file.data.length; knowledge.push({ name: path.basename(file.name), data: file.data.toString('base64') });
  }
  const make = list => ({ format: FORMAT, version: 1, sourceName, bot: { ...bot, symbol: bot.symbol || 'sparkles' }, entries: list, ...(state.sharedMemory ? { sharedMemory: state.sharedMemory } : {}), knowledge });
  let pkg = make(entries);
  while (pkg.entries.length > 20 && Buffer.byteLength(JSON.stringify(pkg)) > MAX_BYTES) pkg = make(pkg.entries.slice(Math.max(1, Math.floor(pkg.entries.length / 5))));
  return pkg;
}

/**
 * Returns { bot, entries, files, message } for a package, or throws a user-readable Error.
 * @param {{pkg:any, existingNames:string[], installed:string[], defaultProvider?:string}} input
 */
function sanitize({ pkg, existingNames, installed, defaultProvider }) {
  if (!pkg || pkg.format !== FORMAT || pkg.version !== 1 || !pkg.bot || typeof pkg.bot !== 'object' || !Array.isArray(pkg.entries)) throw new Error('That is not a Bot package this version understands. Update OpenGrokBot on both computers.');
  if (pkg.bot.memberIDs) throw new Error('Groups cannot be copied. Copy its members one at a time.');
  const source = String(pkg.sourceName || 'another computer').replace(/[\r\n]/g, ' ').slice(0, 80);
  let name = String(pkg.bot.name || '').replace(/[\r\n]/g, ' ').trim().slice(0, 60);
  if (!name) throw new Error('The Bot has no name.');
  const taken = new Set(existingNames.map(x => x.toLowerCase()));
  if (taken.has(name.toLowerCase())) { let n = 1, candidate = `${name} (copy)`; while (taken.has(candidate.toLowerCase()) && n < 100) candidate = `${name} (copy ${++n})`; name = candidate; }
  const id = randomUUID();
  const bot = { id, name, purpose: String(pkg.bot.purpose || '').slice(0, 2000), color: ['white', 'purple', 'pink', 'ochre'].includes(pkg.bot.color) ? pkg.bot.color : 'purple', symbol: 'sparkles' };
  if (pkg.bot.appearance && typeof pkg.bot.appearance === 'object') bot.appearance = pkg.bot.appearance; // validated with the whole workspace by the caller
  const memory = (Array.isArray(pkg.bot.memory) ? pkg.bot.memory : []).filter(x => typeof x === 'string' && x && x.length <= 2000).slice(0, 100);
  if (memory.length) bot.memory = memory;
  if (typeof pkg.bot.folder === 'string' && pkg.bot.folder) bot.folder = pkg.bot.folder.slice(0, 80);
  const tasks = (Array.isArray(pkg.bot.schedules) ? pkg.bot.schedules : []).slice(0, 100).map(x => {
    const { lastEvent, lastRun, lastResult, history, ...rest } = x || {};
    return { ...rest, id: randomUUID(), occurrence: randomUUID(), enabled: false };
  }).filter(x => schedules.valid(x));
  if (tasks.length) bot.schedules = tasks;
  const configuration = pkg.bot.aiConfiguration;
  if (configuration && Array.isArray(configuration.providers)) {
    let providers = configuration.providers.filter(x => x && installed.includes(x.provider) && PROVIDERS.has(x.provider) && typeof x.model === 'string' && x.model.length <= 200 && !/[\r\n]/.test(x.model));
    if (!providers.length) { const fallback = defaultProvider || installed[0]; if (fallback) providers = [{ provider: fallback, model: '' }]; }
    if (providers.length) bot.aiConfiguration = { providers, activeProvider: providers.some(x => x.provider === configuration.activeProvider) ? configuration.activeProvider : providers[0].provider, replyMode: 'one' };
  }
  const entries = pkg.entries.slice(-MAX_ENTRIES).filter(x => x && ['user', 'bot', 'activity'].includes(x.kind) && typeof x.text === 'string').map(x => ({
    id: randomUUID(), botID: id, kind: x.kind, text: x.text.slice(0, 100000), date: iso(x.date),
    ...(['complete', 'stopped', 'failed'].includes(x.state) ? { state: x.state } : x.state === 'streaming' ? { state: 'complete' } : {}),
    ...(typeof x.provider === 'string' ? { provider: x.provider.slice(0, 200) } : {}),
    ...(typeof x.senderName === 'string' ? { senderName: x.senderName.slice(0, 100) } : {}),
    ...(x.delivery === 'scheduled' ? { delivery: 'scheduled' } : {})
  }));
  let total = 0;
  const files = (Array.isArray(pkg.knowledge) ? pkg.knowledge : []).slice(0, 50).flatMap(x => {
    const clean = path.basename(String(x?.name || '')); const data = typeof x?.data === 'string' ? Buffer.from(x.data, 'base64') : null;
    if (!clean || clean.startsWith('.') || !data || !KNOWLEDGE_EXTENSIONS.has(path.extname(clean).toLowerCase()) || data.length > MAX_FILE_BYTES || total + data.length > MAX_KNOWLEDGE_BYTES) return [];
    total += data.length; return [{ name: clean, data }];
  });
  entries.push({ id: randomUUID(), botID: id, kind: 'activity', text: `Copied from ${source}. The AI here starts a fresh session, so it does not remember earlier chats word for word, but its memory and these messages came along.`, date: new Date().toISOString().replace(/\.\d+Z$/, 'Z') });
  return { bot, entries, files, message: `Copied “${name}” with ${entries.length - 1} messages, ${memory.length} memory items and ${files.length} Knowledge files. Routines were copied paused.` };
}

module.exports = { FORMAT, MAX_BYTES, build, sanitize };
