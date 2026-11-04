// Settings → API Keys: optional pay-per-token keys for the provider CLIs. A subscription needs no key (sign in through the CLI).
const PROVIDERS = [
  ['codex', 'Codex / OpenAI', 'OpenAI API usage is billed per token to your API account, separately from a ChatGPT subscription.', 'https://platform.openai.com/api-keys'],
  ['claude', 'Claude Code', 'Claude Code uses a configured API key instead of your Claude subscription, so usage is billed per token to your Anthropic API account.', 'https://console.anthropic.com/settings/keys'],
  ['grok', 'Grok Build', 'xAI API usage is billed per token to your xAI account, separately from any X or Grok subscription.', 'https://console.x.ai'],
  ['gemini', 'Gemini CLI', 'Gemini API usage follows your Google AI Studio plan and quota.', 'https://aistudio.google.com/apikey']
];

const el = (tag, className = '', text = '') => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };

export async function renderApiKeys({ bridge, result, toast, page }) {
  if (!bridge.cliKeysStatus) { page.append(el('p', 'muted', 'API keys are available in the installed app.')); return; }
  let status = {};
  try { status = await result(bridge.cliKeysStatus()); } catch (error) { toast(error.message); }
  const wrap = el('div', 'voice-settings');
  wrap.append(el('p', 'muted', 'A ChatGPT, Claude or Grok subscription works without a key: sign in through that provider’s CLI. Add an API key only if you want a Bot to use pay-per-token API access instead. A saved key replaces the CLI’s own sign-in for that provider until you remove it. Keys are encrypted on this PC and passed to that CLI only through its environment.'));
  for (const [id, title, billing, link] of PROVIDERS) {
    const state = el('span', 'muted', status[id] ? 'Using your saved API key' : 'Using CLI sign-in');
    const input = el('input'); input.type = 'password'; input.autocomplete = 'off'; input.placeholder = status[id] ? 'Saved — paste a new key to replace' : 'Paste API key';
    const save = el('button', '', 'Save key'); save.type = 'button';
    save.addEventListener('click', async () => {
      try { await result(bridge.cliKeysSet(id, input.value.trim())); input.value = ''; input.placeholder = 'Saved — paste a new key to replace'; state.textContent = 'Using your saved API key'; toast(`${title} key saved.`); }
      catch (error) { toast(error.message); }
    });
    const remove = el('button', '', 'Remove'); remove.type = 'button';
    remove.addEventListener('click', async () => {
      try { await result(bridge.cliKeysSet(id, '')); input.placeholder = 'Paste API key'; state.textContent = 'Using CLI sign-in'; toast(`${title} key removed.`); }
      catch (error) { toast(error.message); }
    });
    const line = el('div', 'voice-key'); line.append(input, save, remove);
    const label = el('label', 'voice-row'); label.append(el('span', '', title), line);
    wrap.append(label, state, el('p', 'muted', billing));
    const get = el('a', '', 'Get a key ↗'); get.href = link; get.target = '_blank'; get.rel = 'noopener noreferrer'; wrap.append(get);
  }
  page.append(wrap);
}
