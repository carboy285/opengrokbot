'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const pkgs = require('./bot-package.cjs');

const state = () => ({
  bots: [{ id: '11111111-1111-4111-8111-111111111111', name: 'Fantasy', purpose: 'Help', color: 'pink', memory: ['likes pizza', ''], aiConfiguration: { providers: [{ provider: 'codex', model: 'm1' }, { provider: 'claude', model: '' }], activeProvider: 'claude', replyMode: 'one' }, schedules: [{ id: 'a', occurrence: 'b', name: 'Daily', text: 'Do it', recurrence: 'daily', timezone: 'Etc/UTC', nextRun: '2099-01-01T09:00:00Z', enabled: true, lastRun: 'x', history: [1] }] }, { id: '22222222-2222-4222-8222-222222222222', name: 'Group', purpose: 'g', color: 'ochre', memberIDs: ['11111111-1111-4111-8111-111111111111'] }],
  entries: [{ id: 'e1', botID: '11111111-1111-4111-8111-111111111111', kind: 'user', text: 'hi', date: '2026-11-01T10:00:00.123Z' }, { id: 'e2', botID: '11111111-1111-4111-8111-111111111111', kind: 'bot', text: 'hello', state: 'streaming', detail: 'FULL', date: '2026-11-01T10:00:05Z' }, { id: 'e3', botID: '22222222-2222-4222-8222-222222222222', kind: 'user', text: 'other', date: '2026-11-01T10:00:05Z' }],
  sharedMemory: ['shared']
});

test('build packages one Bot with trimmed history and no private detail', () => {
  const pkg = pkgs.build({ state: state(), botID: '11111111-1111-4111-8111-111111111111', sourceName: 'Bens-PC', files: [{ name: 'a.txt', data: Buffer.from('hello') }, { name: 'bad.exe', data: Buffer.from('x') }] });
  assert.equal(pkg.format, 'opengrokbot-bot-package');
  assert.equal(pkg.entries.length, 2);
  assert.ok(pkg.entries.every(x => !('detail' in x)));
  assert.equal(pkg.entries[1].state, 'complete');
  assert.equal(pkg.entries[0].date, '2026-11-01T10:00:00Z');
  assert.deepEqual(pkg.knowledge.map(x => x.name), ['a.txt']);
  assert.equal(pkg.bot.symbol, 'sparkles');
  assert.throws(() => pkgs.build({ state: state(), botID: '22222222-2222-4222-8222-222222222222', sourceName: 'x' }), /individual Bot/);
});

test('sanitize rebuilds the Bot with fresh IDs, paused routines and only installed providers', () => {
  const pkg = pkgs.build({ state: state(), botID: '11111111-1111-4111-8111-111111111111', sourceName: 'Bens-PC', files: [] });
  const result = pkgs.sanitize({ pkg, existingNames: ['Fantasy'], installed: ['claude'], defaultProvider: 'claude' });
  assert.equal(result.bot.name, 'Fantasy (copy)');
  assert.notEqual(result.bot.id, '11111111-1111-4111-8111-111111111111');
  assert.deepEqual(result.bot.memory, ['likes pizza']);
  assert.deepEqual(result.bot.aiConfiguration.providers, [{ provider: 'claude', model: '' }]);
  assert.equal(result.bot.aiConfiguration.replyMode, 'one');
  assert.equal(result.bot.schedules[0].enabled, false);
  assert.ok(!('lastRun' in result.bot.schedules[0]) && !('history' in result.bot.schedules[0]));
  assert.ok(result.entries.every(x => x.botID === result.bot.id));
  assert.equal(new Set(result.entries.map(x => x.id)).size, result.entries.length);
  assert.match(result.entries.at(-1).text, /^Copied from Bens-PC/);
  assert.match(result.message, /Copied “Fantasy \(copy\)” with 2 messages/);
});

test('sanitize falls back to the default provider and refuses bad packages', () => {
  const pkg = pkgs.build({ state: state(), botID: '11111111-1111-4111-8111-111111111111', sourceName: 'x', files: [] });
  assert.equal(pkgs.sanitize({ pkg, existingNames: [], installed: ['gemini'], defaultProvider: 'gemini' }).bot.aiConfiguration.providers[0].provider, 'gemini');
  assert.throws(() => pkgs.sanitize({ pkg: { format: 'nope' }, existingNames: [], installed: [] }), /not a Bot package/);
  assert.throws(() => pkgs.sanitize({ pkg: { ...pkg, bot: { ...pkg.bot, memberIDs: ['x'] } }, existingNames: [], installed: [] }), /Groups/);
  const hostile = { ...pkg, knowledge: [{ name: '../../evil.txt', data: Buffer.from('a').toString('base64') }, { name: '.hidden.txt', data: 'YQ==' }, { name: 'run.exe', data: 'YQ==' }], entries: [{ kind: 'user', text: 'x', state: 'weird', senderBotID: 'steal' }] };
  const clean = pkgs.sanitize({ pkg: hostile, existingNames: [], installed: ['codex'] });
  assert.deepEqual(clean.files.map(x => x.name), ['evil.txt']);
  assert.ok(!('senderBotID' in clean.entries[0]) && !('state' in clean.entries[0]));
});
