import { preview } from './seed.js';

const $ = selector => document.querySelector(selector);
const node = (tag, className = '', text = '') => { const value = document.createElement(tag); value.className = className; value.textContent = text; return value; };
const button = (text, action, className = 'pill') => { const value = node('button', className, text); value.type = 'button'; value.addEventListener('click', action); return value; };
const append = (parent, ...children) => { parent.append(...children.filter(Boolean)); return parent; };
const avatar = (color = 'white', starred = false) => append(node('span', `avatar ${color}`), starred ? node('b', '', '★') : null);
const result = async operation => { const response = await operation; if (!response.ok) throw new Error(response.error); return response.value; };
const webPreview = {
  load: async () => { try { return { ok: true, value: JSON.parse(localStorage.getItem('workspace') || 'null') || structuredClone(preview) }; } catch { return { ok: false, error: 'Saved preview could not be read. Existing storage was kept.' }; } },
  save: async value => { try { localStorage.setItem('workspace', JSON.stringify(value)); return { ok: true }; } catch { return { ok: false, error: 'Local storage is full. Your draft was kept.' }; } },
  export: async text => { const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' })); link.download = 'OpenGrokBot-preview.txt'; link.click(); URL.revokeObjectURL(link.href); return { ok: true, value: true }; },
  openDocs: async url => { window.open(url, '_blank', 'noopener,noreferrer'); return { ok: true }; },
  vaultList: async () => ({ ok: false, error: 'The device vault is available only inside the installed Windows app with Windows encryption.' })
};
const bridge = window.desktop || webPreview;
let workspace = structuredClone(preview);
let selected = workspace.bots[0]?.id;
let search = '';
let toastTimer;
let focusGeneration = 0;
const drafts = new Map();
const dialog = $('#panel');
function toast(text) { $('#toast').textContent = text; $('#toast').classList.add('visible'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 5000); }
function currentBot() { return workspace.bots.find(bot => bot.id === selected); }
function entries(bot) { return workspace.entries.filter(entry => entry.botID === bot.id); }
function applyTheme(value) {
  document.documentElement.dataset.theme = value === 'system' ? (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark') : value;
  localStorage.setItem('appearance', value);
}
applyTheme(localStorage.getItem('appearance') || 'dark');
matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => { if (localStorage.getItem('appearance') === 'system') applyTheme('system'); });
async function persist(next) {
  try { await result(bridge.save(next)); workspace = next; return true; }
  catch (error) { toast(error.message); return false; }
}
function selectBot(id) { if (currentBot()) drafts.set(selected, $('#draft').value); selected = id; render(); }
function render() {
  const primary = $('#primary-bot'); primary.replaceChildren();
  if (workspace.bots[0]) {
    const first = workspace.bots[0];
    primary.append(append(button('', () => selectBot(first.id), `primary-card ${selected === first.id ? 'selected' : ''}`), avatar('white', true), node('span', '', 'Grok Bot')));
  }
  const list = $('#bot-list'); list.replaceChildren();
  const visible = workspace.bots.filter((bot, index) => (index !== 0 || search) && `${bot.name} ${bot.purpose}`.toLowerCase().includes(search.toLowerCase()));
  for (const bot of visible) {
    const row = button('', () => selectBot(bot.id), `bot-row ${bot.id === selected ? 'selected' : ''}`);
    append(row, avatar(bot.color), append(node('span', 'details'), node('strong', '', bot.name), node('small', '', entries(bot).at(-1)?.text || bot.purpose)));
    row.addEventListener('contextmenu', event => { event.preventDefault(); showBotActions(bot); });
    list.append(row);
  }
  if (search && !visible.length) list.append(node('p', 'empty', 'No Bots found.'));
  const bot = currentBot();
  $('#chat-heading').replaceChildren(); $('#messages').replaceChildren();
  $('#draft').value = drafts.get(selected) || '';
  $('#draft').disabled = !bot;
  if (!bot) { $('#messages').append(node('div', 'empty', 'Create a preview Bot to start your local workspace.')); return; }
  append($('#chat-heading'), avatar(bot.color), node('span', '', bot.name));
  $('#draft').placeholder = `Message ${bot.name}`;
  for (const entry of entries(bot)) {
    if (entry.kind === 'activity') {
      append($('#messages'), append(node('div', 'activity'), node('span', '', entry.text.split(' · ')[0]), avatar('ochre'), node('span', '', 'School')));
    } else {
      const bubble = node('div', 'bubble', entry.text);
      bubble.setAttribute('aria-label', `${entry.kind === 'user' ? 'Local note' : 'Example Bot message'}: ${entry.text}`);
      append($('#messages'), append(node('div', `message-row ${entry.kind}`), bubble));
    }
  }
  if (!entries(bot).length) $('#messages').append(node('div', 'empty', 'Write a local note below. No message is sent to Grok Bot.'));
}
function panel(title) {
  dialog.replaceChildren();
  const content = node('div', 'panel-content');
  const close = button('×', () => dialog.close(), 'close-panel'); close.setAttribute('aria-label', 'Close panel');
  append(content, append(node('header', 'panel-head'), node('h1', '', title), close));
  dialog.append(content);
  if (!dialog.open) dialog.showModal();
  return content;
}
dialog.addEventListener('click', event => { if (event.target === dialog) { const box = dialog.getBoundingClientRect(); if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close(); } });
dialog.addEventListener('close', () => dialog.replaceChildren());
function showConnection(detail = '') {
  const content = panel('Connection');
  const body = node('div', 'connection-details');
  append(body, append(node('div', 'panel-head'), avatar('white'), node('h1', '', 'Not connected')),
    node('p', '', detail || 'Your workspace is running locally. You can create preview Bots and save notes, but no messages or tasks are sent to Grok Bot.'),
    append(node('div', 'settings-card'), node('h3', '', 'Live service access is not implemented'), node('p', '', 'The 0.78.1 installer’s authentication, transport, streaming, and approval contracts need to be verified before this independent client can use them. Example conversations and app listings are offline.')),
    append(node('div', 'panel-bottom'), button('Official setup ↗', () => bridge.openDocs('https://docs.x.ai/grok-bot/get-started')), button('Back to workspace', () => dialog.close(), 'pill primary')));
  content.append(body);
}
function showNewBot() {
  const content = panel('Create a Bot');
  const form = node('form', 'new-bot');
  let color = 'purple';
  const face = avatar(color);
  const name = node('input', 'field'); name.placeholder = 'Give your Bot a name'; name.maxLength = 200; name.required = true; name.setAttribute('aria-label', 'Bot name');
  const purpose = node('textarea', 'field'); purpose.placeholder = 'A short description'; purpose.rows = 3; purpose.maxLength = 2000; purpose.setAttribute('aria-label', 'Bot description');
  const choices = node('div', 'colors');
  for (const option of ['purple', 'pink', 'ochre', 'white']) {
    const control = button('', () => { color = option; face.className = `avatar ${color}`; for (const other of choices.children) other.classList.remove('active'); control.classList.add('active'); }, `color-choice ${color === option ? 'active' : ''}`);
    control.style.backgroundColor = { purple: '#9355ff', pink: '#fa2a99', ochre: '#9c6c37', white: '#fff' }[option]; control.setAttribute('aria-label', `${option} avatar`); choices.append(control);
  }
  const create = button('Create preview Bot', () => {}, 'pill primary'); create.type = 'submit'; create.disabled = true;
  name.addEventListener('input', () => create.disabled = !name.value.trim());
  append(form, face, node('label', 'muted', 'Name'), name, node('label', 'muted', 'What should it help with?'), purpose, choices, create);
  form.addEventListener('submit', async event => { event.preventDefault(); if (!name.value.trim()) return; const next = structuredClone(workspace); const bot = { id: crypto.randomUUID(), name: name.value.trim(), purpose: purpose.value, color }; next.bots.push(bot); if (await persist(next)) { selectBot(bot.id); dialog.close(); } });
  append(content, form, node('p', 'panel-footnote', 'Creates a local preview Bot. No agent is started.'));
  name.focus();
}
const catalog = [
  ['Datadog','Code','♞','#9a63cf'],['Vercel','Code','▲','#fff'],['Supabase','Code','ϟ','#3ecf8e'],['Cloudflare','Code','☁','#f6821f'],['Sentry','Code','◬','#ddd'],['Firebase','Code','♦','#ffb300'],['1Password','Password Managers','⚿','#d6d9e5'],['Notion','Productivity','N','#fff'],['Atlassian','Productivity','Λ','#2684ff'],['Google Drive','Productivity','△','#39a96b'],['Slack','Communication','#','#59b9a9'],['Gmail','Communication','M','#e05a50'],['Figma','Design','⠿','#a66bfe'],['GitHub','Code','⌘','#e7e7e7']
];
function showApps() {
  const content = panel('Connect Apps');
  content.querySelector('.panel-head').insertBefore(node('span', 'muted', 'No account connected'), content.querySelector('.close-panel'));
  const searchField = node('input', 'catalog-search'); searchField.placeholder = 'Search across apps and skills'; searchField.setAttribute('aria-label', 'Search apps');
  const categories = node('div', 'categories'); let category = 'All';
  const scroller = node('div', 'panel-scroll');
  function section(title, apps) {
    const value = append(node('section', 'catalog-section'), node('h3', '', title)); const grid = node('div', 'catalog-grid');
    for (const [name, , glyph, color] of apps) {
      const icon = node('span', 'app-icon', glyph); icon.style.color = color;
      grid.append(append(node('div', 'catalog-app'), icon, node('span', 'name', name), button('Connect', () => showConnection(`${name} cannot be connected in offline preview. No authorization was requested and no account was changed.`))));
    }
    value.append(grid); return value;
  }
  function update() {
    categories.replaceChildren();
    for (const label of ['All','Password Managers','Productivity','Communication','Design','Code']) categories.append(button(label, () => { category = label; update(); }, `pill ${category === label ? 'active' : ''}`));
    scroller.replaceChildren();
    if (category === 'All' && !searchField.value) {
      scroller.append(section('Recommended for you', catalog.slice(0,6)));
      for (const label of ['Password Managers','Productivity','Communication','Design']) scroller.append(section(label, catalog.filter(app => app[1] === label)));
    } else {
      const matches = catalog.filter(app => (category === 'All' || app[1] === category) && app[0].toLowerCase().includes(searchField.value.toLowerCase()));
      scroller.append(matches.length ? section(category === 'All' ? 'Search results' : category, matches) : node('p', 'empty', 'No apps found.'));
    }
  }
  searchField.addEventListener('input', update); append(content, searchField, categories, scroller, node('p', 'panel-footnote', 'Catalog preview · Connecting requires a verified Grok Bot session.')); update();
}
function unavailable(title, detail) { return append(node('div', 'unavailable'), node('h2', '', title), node('p', '', detail), button('View connection status', () => showConnection())); }
function showSettings(tab = 'General') {
  dialog.replaceChildren();
  const layout = node('div', 'settings-layout'); const nav = node('nav', 'settings-nav'); const page = node('section', 'settings-page');
  for (const [name, glyph] of [['General','⚙'],['Computer','▣'],['Permissions','♧'],['Vault','⚿'],['Usage & Billing','▥'],['Updates','⇩']]) nav.append(append(button('', () => showSettings(name), name === tab ? 'active' : ''), node('span','',glyph), node('div','',name)));
  append(page, append(node('header','panel-head'), node('h1','',tab), button('×', () => dialog.close(), 'close-panel')));
  append(layout, nav, page); dialog.append(layout); if (!dialog.open) dialog.showModal();
  if (tab === 'General') {
    const promo = node('div','promo');
    append(promo, append(node('div'), node('h3','','One place for your AI teammates'), node('p','','Grok Bot’s official plans bring your Bots and their tools together. Learn what’s included in the service.'), button('View official plans', () => bridge.openDocs('https://docs.x.ai/grok-bot/get-started'), 'pill primary')), append(node('div','brand-tile'), node('span','','⬡'), node('span','','✧'), avatar(), node('span','','𝕏')));
    const profile = node('input'); profile.value = localStorage.getItem('profile') || 'Local preview'; profile.setAttribute('aria-label','Local display name'); profile.addEventListener('change', () => localStorage.setItem('profile',profile.value));
    const account = append(node('div','settings-card'), append(node('div','setting-row'), node('span','profile-icon','LP'), append(node('div','profile-text'),profile,node('small','','Local workspace · Not signed in')),button('Connection status', () => showConnection())));
    const appearance = node('div','settings-card'); const select = node('select'); select.setAttribute('aria-label','Theme');
    for (const [value,label] of [['system','Follow System'],['dark','Dark'],['light','Light']]) { const option=node('option','',label); option.value=value; select.append(option); } select.value=localStorage.getItem('appearance') || 'dark'; select.addEventListener('change',()=>applyTheme(select.value));
    append(appearance, append(node('div','setting-row'),node('label','','Theme'),select),append(node('div','setting-row'),node('label','','Accent'),node('span','muted','Bot color')),append(node('div','setting-row'),node('label','','Language'),node('span','muted','English')));
    append(page,promo,node('p','settings-label','Account'),account,node('p','settings-label','Appearance'),appearance,button('Reset preview data…',()=>confirmReset()));
  } else if (tab === 'Computer') page.append(unavailable('Your Bot’s computer', 'Cloud computer access has not been established. Screen viewing, terminal control, and resets require a verified Grok Bot connection.'));
  else if (tab === 'Permissions') page.append(unavailable('Permissions belong to your connected Bot', 'Auto-review and approval rules are not read or changed in offline preview.'));
  else if (tab === 'Usage & Billing') page.append(unavailable('No usage to report', 'This app has made no model or service requests. No subscription usage percentage is inferred.'));
  else if (tab === 'Updates') append(page,unavailable('OpenGrokBot 0.2.0','Install a new build from the project’s release artifacts. This app does not update the official Grok Bot application.'),button('Open project ↗',()=>bridge.openDocs('https://github.com/carboy285/opengrokbot')));
  else if (tab === 'Vault') renderVault(page);
}
async function renderVault(page) {
  append(page,node('h2','','Device vault'),node('p','muted','Encrypted with Windows data protection. This local vault is not synced or accessible to Grok Bot.'));
  let items;
  try { items = await result(bridge.vaultList()); } catch(error) { page.append(node('div','unavailable',error.message)); return; }
  for (const item of items) {
    const row=node('div','secret-row'); const revealed=node('div','revealed-secret'); revealed.hidden=true;
    const reveal=button('Reveal',async()=>{ if (!revealed.hidden) { revealed.textContent=''; revealed.hidden=true; reveal.textContent='Reveal'; return; } try { const generation=focusGeneration; const value=await result(bridge.vaultRead(item.id)); if(generation!==focusGeneration||!document.hasFocus()||!dialog.open||!revealed.isConnected)return; revealed.textContent=value; revealed.hidden=false; reveal.textContent='Hide'; } catch(error) { toast(error.message); } });
    const remove=button('Delete',()=>showDeleteSecret(item));
    append(row,node('strong','',item.title),reveal,remove); append(page,row,revealed);
  }
  const form=node('form','settings-card'); const title=node('input','field'); title.placeholder='Label'; title.required=true; title.setAttribute('aria-label','Secure note label');
  const secret=node('input','field'); secret.type='password'; secret.placeholder='Secret value'; secret.required=true; secret.setAttribute('aria-label','Secret value');
  const save=button('Save secure note',()=>{},'pill primary'); save.type='submit';
  append(form,title,secret,save); form.addEventListener('submit',async event=>{event.preventDefault(); try { await result(bridge.vaultSave(title.value,secret.value)); secret.value=''; showSettings('Vault'); } catch(error) { toast(error.message); }}); page.append(form);
}
function showDeleteSecret(item) { const content=panel('Delete secure note?'); append(content,node('p','','This removes the encrypted note from this device.'),button('Delete secure note',async()=>{try {await result(bridge.vaultDelete(item.id));showSettings('Vault');}catch(error){toast(error.message);}}),button('Cancel',()=>showSettings('Vault'))); }
function confirmReset() { const content=panel('Reset local preview?'); append(content,node('p','','This replaces local Bots and notes with the example workspace. Device vault notes are kept.'),button('Reset preview',async()=>{if(await persist(structuredClone(preview))){selected=workspace.bots[0].id;drafts.clear();render();dialog.close();}}),button('Cancel',()=>showSettings())); }
function showBotActions(bot) { const content=panel(bot.name); append(content,button('Export conversation…',()=>exportConversation(bot)),button('Delete preview Bot',async()=>{const next=structuredClone(workspace);next.bots=next.bots.filter(x=>x.id!==bot.id);next.entries=next.entries.filter(x=>x.botID!==bot.id);if(await persist(next)){selected=workspace.bots[0]?.id;render();dialog.close();}})); }
async function exportConversation(bot=currentBot()) { if(!bot)return; const text='OpenGrokBot — OFFLINE PREVIEW\nNo messages sent to Grok Bot.\n\n'+entries(bot).map(x=>`${x.kind==='user'?'Local note':'Example '+x.kind}: ${x.text}`).join('\n\n'); try { if(await result(bridge.export(text)))toast('Conversation exported.'); }catch(error){toast(error.message);} }
$('#composer').addEventListener('submit', async event => {
  event.preventDefault(); const bot=currentBot(); const text=$('#draft').value.trim(); if(!bot||!text)return;
  if(text.length>100000){toast('This local note is too long.');return;}
  const next=structuredClone(workspace); next.entries.push({id:crypto.randomUUID(),botID:bot.id,kind:'user',text});
  if(await persist(next)){drafts.delete(bot.id);render();$('#draft').focus();$('#messages').scrollTop=$('#messages').scrollHeight;}
});
$('#draft').addEventListener('input',()=>{ drafts.set(selected,$('#draft').value); $('#draft').style.height='auto';$('#draft').style.height=Math.min(180,$('#draft').scrollHeight)+'px'; });
$('#search-button').addEventListener('click',()=>{const slot=$('#search-slot');if(slot.firstChild){slot.replaceChildren();search='';render();return;}const field=node('input','search-input');field.placeholder='Search Bots';field.setAttribute('aria-label','Search Bots');field.addEventListener('input',()=>{search=field.value;render();});slot.append(field);field.focus();});
$('#new-button').addEventListener('click',showNewBot); $('#profile-button').addEventListener('click',()=>showSettings()); $('#apps-button').addEventListener('click',showApps); $('#status-button').addEventListener('click',()=>showConnection()); $('#attachment-button').addEventListener('click',()=>{const content=panel('Conversation actions');append(content,button('Export conversation…',()=>exportConversation()),button('Attachment status',()=>showConnection('Files cannot be uploaded until the Grok Bot connection protocol is verified. Nothing has been uploaded.')));});
for(const control of document.querySelectorAll('[data-window]')) control.addEventListener('click',()=>window.desktop?.windowAction(control.dataset.window));
window.addEventListener('blur',()=>{focusGeneration++;for(const secret of document.querySelectorAll('.revealed-secret')){secret.textContent='';secret.hidden=true;}for(const field of document.querySelectorAll('input[type=password]'))field.value='';});
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey))return;if(event.key==='n'){event.preventDefault();showNewBot();}else if(event.key===','){event.preventDefault();showSettings();}else if(event.key==='f'){event.preventDefault();$('#search-button').click();}else if(event.key==='Enter'&&!dialog.open){event.preventDefault();$('#composer').requestSubmit();}});
try { workspace=await result(bridge.load());selected=workspace.bots[0]?.id; }catch(error){toast(error.message);}
render();
