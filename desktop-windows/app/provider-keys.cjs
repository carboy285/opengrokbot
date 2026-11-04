'use strict';
// Optional API keys for the provider CLIs. A saved key goes to that CLI only through its process environment
// (never arguments, files or prompts) and replaces the CLI's own sign-in until removed. Keys are encrypted with Electron safeStorage.

const VARIABLES = {
  codex: ['CODEX_API_KEY', 'OPENAI_API_KEY'],
  claude: ['ANTHROPIC_API_KEY'],
  grok: ['XAI_API_KEY'],
  gemini: ['GEMINI_API_KEY']
};
const PROVIDERS = new Set(Object.keys(VARIABLES));

/** Keys contain no whitespace or control characters; anything else is a paste mistake. */
function normalized(value) {
  const text = String(value ?? '').trim();
  return text.length >= 8 && text.length <= 512 && /^[\x21-\x7e]+$/.test(text) ? text : null;
}

function environmentFor(provider, key) {
  const names = VARIABLES[provider];
  return names && key ? Object.fromEntries(names.map(name => [name, key])) : {};
}

module.exports = { VARIABLES, PROVIDERS, normalized, environmentFor };
