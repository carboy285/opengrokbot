'use strict';
// Keys and connector settings copied between computers on one account (same JSON as the Mac app's SettingsBundle).
// It only travels inside the encrypted account link, only while "Share keys and connectors" is on at both ends,
// and everything that arrives is re-validated field by field.
const FORMAT = 'opengrokbot-settings-bundle';
const CLI_PROVIDERS = new Set(['codex', 'claude', 'grok', 'gemini']);
const VOICE_PROVIDERS = new Set(['groq', 'openAI', 'elevenLabs', 'nvidiaNIM', 'nvidiaCloud', 'gemini']);
const SHARING_OFF = '“Share keys and connectors” is off on this computer. Turn it on in Settings → Computer, then try again.';
const cliKey = value => { const t = String(value ?? '').trim(); return t.length >= 8 && t.length <= 512 && /^[\x21-\x7e]+$/.test(t) ? t : null; };
const voiceKey = value => { const t = String(value ?? '').trim(); return t.length >= 8 && t.length <= 600 && /^[\x21-\x7e]+$/.test(t) ? t : null; };

function sanitize(value) {
  if (!value || value.format !== FORMAT || value.version !== 1) throw new Error('That is not a settings bundle this version understands. Update OpenGrokBot on both computers.');
  const clean = { format: FORMAT, version: 1, sourceName: String(value.sourceName || 'another computer').replace(/[\r\n]/g, ' ').slice(0, 80), cliKeys: {}, voiceKeys: {} };
  for (const [name, key] of Object.entries(value.cliKeys && typeof value.cliKeys === 'object' ? value.cliKeys : {})) { const k = cliKey(key); if (CLI_PROVIDERS.has(name) && k) clean.cliKeys[name] = k; }
  for (const [name, key] of Object.entries(value.voiceKeys && typeof value.voiceKeys === 'object' ? value.voiceKeys : {})) { const k = voiceKey(key); if (VOICE_PROVIDERS.has(name) && k) clean.voiceKeys[name] = k; }
  const c = value.composio;
  if (c && typeof c === 'object') {
    const key = String(c.key ?? '').trim(), slugs = (Array.isArray(c.toolkits) ? c.toolkits : []).filter(x => typeof x === 'string' && /^[_a-z0-9]{1,100}$/.test(x));
    if (key && key.length < 4096 && !/\s/.test(key) && /^[A-Za-z0-9_-]{8,100}$/.test(String(c.userID ?? '')) && slugs.length && slugs.length <= 30) clean.composio = { key, userID: c.userID, toolkits: slugs };
  }
  return clean;
}
const isEmpty = bundle => !Object.keys(bundle.cliKeys).length && !Object.keys(bundle.voiceKeys).length && !bundle.composio;
function summary(bundle) {
  const parts = [], cli = Object.keys(bundle.cliKeys).length, voice = Object.keys(bundle.voiceKeys).length;
  if (cli) parts.push(`${cli} AI provider key${cli === 1 ? '' : 's'}`);
  if (voice) parts.push(`${voice} voice key${voice === 1 ? '' : 's'}`);
  if (bundle.composio) parts.push(`connectors (${bundle.composio.toolkits.length} apps)`);
  return parts.join(', ') || 'nothing';
}
module.exports = { FORMAT, SHARING_OFF, CLI_PROVIDERS, VOICE_PROVIDERS, sanitize, isEmpty, summary };
