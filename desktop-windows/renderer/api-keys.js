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
  await renderMediaKeys({ bridge, result, toast, page });
}

// Image and video generators (0.9.7). The app calls them with your key; Bots never see it.
async function renderMediaKeys({ bridge, result, toast, page }) {
  if (!bridge.mediaKeysStatus) return;
  let status;
  try { status = await result(bridge.mediaKeysStatus()); } catch (error) { toast(error.message); return; }
  const settings = structuredClone(status.settings || {}); settings.models ||= {};
  const wrap = el('div', 'voice-settings media-keys');
  wrap.append(el('h2', '', 'Image & video'), el('p', 'muted', 'Add a key and any Bot can make pictures or videos when you ask. The app calls the provider with your key, saves the result in that Bot’s folder and shows it in the chat. Each provider bills its own account.'));
  const saveSettings = async () => { try { await result(bridge.mediaSettingsSet(settings)); } catch (error) { toast(error.message); } };
  for (const provider of status.providers) {
    const state = el('span', 'muted', provider.saved ? 'Key saved' : 'No key');
    const input = el('input'); input.type = 'password'; input.autocomplete = 'off'; input.placeholder = provider.saved ? 'Saved — paste a new key to replace' : 'Paste API key';
    input.setAttribute('aria-label', provider.name + ' API key');
    const save = el('button', '', 'Save key'); save.type = 'button';
    save.addEventListener('click', async () => { try { await result(bridge.mediaKeysSet(provider.id, input.value.trim())); input.value = ''; input.placeholder = 'Saved — paste a new key to replace'; state.textContent = 'Key saved'; toast(`${provider.name} key saved.`); } catch (error) { toast(error.message); } });
    const remove = el('button', '', 'Remove'); remove.type = 'button';
    remove.addEventListener('click', async () => { try { await result(bridge.mediaKeysSet(provider.id, '')); input.placeholder = 'Paste API key'; state.textContent = 'No key'; toast(`${provider.name} key removed.`); } catch (error) { toast(error.message); } });
    const line = el('div', 'voice-key'); line.append(input, save, remove);
    const label = el('label', 'voice-row'); label.append(el('span', '', provider.name), line);
    const models = el('div', 'media-models');
    for (const kind of provider.kinds) {
      const field = el('input', 'media-model'); field.value = settings.models[provider.id]?.[kind] || ''; field.placeholder = provider.defaults[kind]; field.setAttribute('aria-label', `${provider.name} ${kind} model`);
      field.addEventListener('change', () => { (settings.models[provider.id] ||= {})[kind] = field.value.trim(); saveSettings(); });
      models.append(append(el('label', 'media-model-row'), el('span', 'muted', kind === 'video' ? 'Video model' : 'Image model'), field));
    }
    const get = el('a', '', 'Get a key ↗'); get.href = provider.help; get.target = '_blank'; get.rel = 'noopener noreferrer';
    wrap.append(label, state, models, get);
  }
  for (const kind of ['image', 'video']) {
    const choices = status.providers.filter(x => x.kinds.includes(kind));
    const select = el('select'); select.setAttribute('aria-label', `Default ${kind} provider`);
    select.append(Object.assign(el('option', '', 'First one with a key'), { value: '' }));
    for (const choice of choices) select.append(Object.assign(el('option', '', choice.name), { value: choice.id }));
    select.value = settings[kind + 'Provider'] || '';
    select.addEventListener('change', () => { if (select.value) settings[kind + 'Provider'] = select.value; else delete settings[kind + 'Provider']; saveSettings(); });
    wrap.append(append(el('label', 'voice-row'), el('span', '', kind === 'video' ? 'Default for videos' : 'Default for images'), select));
  }
  page.append(wrap);
}
const append = (parent, ...children) => { parent.append(...children); return parent; };
