import { preview } from './seed.js';

const $ = selector => document.querySelector(selector);
const node = (tag, className = '', text = '') => { const value = document.createElement(tag); value.className = className; value.textContent = text; return value; };
const button = (text, action, className = 'pill') => { const value = node('button', className, text); value.type = 'button'; value.addEventListener('click', action); return value; };
const append = (parent, ...children) => { parent.append(...children.filter(Boolean)); return parent; };
const avatar = (color = 'white', starred = false) => append(node('span', `avatar ${color}`), starred ? node('b', '', '★') : null);
const result = async operation => { const response = await operation; if (!response.ok) throw new Error(response.error); return response.value; };
const webPreview = {
  load: async () => { try { return { ok: true, value: JSON.parse(localStorage.getItem('workspace') || 'null') || structuredClone(preview) }; } catch { return { ok: false, error: 'Saved workspace could not be read. Existing storage was kept.' }; } },
  save: async value => { try { localStorage.setItem('workspace', JSON.stringify(value)); return { ok: true }; } catch { return { ok: false, error: 'Local storage is full. Your draft was kept.' }; } },
  export: async text => { const link = document.createElement('a'); link.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' })); link.download = 'OpenGrokBot-conversation.txt'; link.click(); URL.revokeObjectURL(link.href); return { ok: true, value: true }; },
  openDocs: async url => { window.open(url, '_blank', 'noopener,noreferrer'); return { ok: true }; },
  setupStatus:async()=>({ok:true,value:{providers:[],installed:[],selected:'',complete:false}}),
  scanCLIs:async()=>({ok:true,value:{providers:[],installed:[],selected:'',complete:false}}),
  composioStatus:async()=>({ok:true,value:{configured:false,toolkits:[]}}),
  vaultList: async () => ({ ok: false, error: 'The device vault is available only inside the installed Windows app with Windows encryption.' })
};
const bridge = window.desktop || webPreview;
let workspace = structuredClone(preview);
let selected = workspace.bots[0]?.id;
let setup={providers:[],installed:[],selected:'',complete:false};
let running=new Set();
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
  if (!bot) { $('#messages').append(node('div', 'empty', 'Create a Bot to start chatting.')); return; }
  append($('#chat-heading'), avatar(bot.color), node('span', '', bot.name));
  $('#draft').placeholder = `Message ${bot.name}`;
  for (const entry of entries(bot)) {
    if (entry.kind === 'activity') {
      append($('#messages'), append(node('div', 'activity'), node('span', '', entry.text.split(' · ')[0]), avatar('ochre'), node('span', '', 'School')));
    } else {
      const bubble = node('div', 'bubble', entry.text || (entry.state==='streaming'?'Thinking…':''));
      bubble.setAttribute('aria-label', `${entry.kind === 'user' ? 'You' : 'AI reply'}: ${entry.text}`);
      append($('#messages'), append(node('div', `message-row ${entry.kind}`), bubble));
    }
  }
  if(entries(bot).at(-1)?.state==='failed')$('#messages').append(button('Retry response',async()=>{try{await result(bridge.retry(bot.id));}catch(error){toast(error.message);}}));
  if(running.has(bot.id))$('#messages').append(button('Stop response',()=>bridge.stop(bot.id)));
  const activeCLI=setup.installed.find(x=>x.id===setup.selected);$('#status-button').textContent=activeCLI?`${activeCLI.name} · On this device`:'Set up an AI CLI';
  if (!entries(bot).length) $('#messages').append(node('div', 'empty', 'Send your first message to start chatting with an AI CLI on this device.'));
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
async function showConnection(detail='') {
  let step=0,provider='codex',verified=false;
  async function draw(){
    const content=panel('Set up Grok Bot');
    const body=node('div','connection-details');content.append(body);
    if(detail)body.append(node('p','muted',detail));
    body.append(node('p','muted',`${step+1} of 6`));
    if(step===0){append(body,avatar('white',true),node('h1','','A free app for your AI CLIs'),node('p','','Start with one Grok Bot. Choose a CLI installed on this computer, sign in through that CLI, then optionally connect your tools with Composio.'),node('p','muted','OpenGrokBot is free and open source. AI providers and Composio apply their own pricing, quotas, and model requirements.'));}
    else if(step===1){
      body.append(node('h2','','Choose an AI CLI'));
      if(!window.desktop)body.append(node('p','','Install the desktop app to use AI CLIs. A browser cannot launch local processes.'));
      for(const candidate of setup.providers){const found=setup.installed.find(x=>x.provider===candidate.id);body.append(button(`${provider===candidate.id?'✓ ':''}${candidate.name} · ${found?.version||'Not installed'}`,async()=>{provider=candidate.id;verified=false;if(found)setup=await result(bridge.chooseCLI(found.id));draw();},'setting-row'));}
      body.append(button('Scan again',async()=>{try{setup=await result(bridge.scanCLIs());draw();}catch(error){toast(error.message);}}));
    }else if(step===2){
      const definition=setup.providers.find(x=>x.id===provider),found=setup.installed.find(x=>x.provider===provider);
      append(body,node('h2','',`Install ${definition?.name||'a CLI'}`),node('p','',found?`Already installed: ${found.path}`:'Follow the official install guide, then return and scan again.'));
      if(definition?.install){const code=node('pre','',definition.install);append(body,code,button('Copy install command',()=>navigator.clipboard.writeText(definition.install)),button('Get Node.js ↗',()=>bridge.openDocs('https://nodejs.org/en/download')));}
      if(definition)body.append(button('Official install guide ↗',()=>bridge.openDocs(definition.guide)));
      append(body,button('Scan again',async()=>{setup=await result(bridge.scanCLIs());draw();}),button('Choose executable…',async()=>{await result(bridge.choosePath(provider));setup=await result(bridge.scanCLIs());draw();}));
    }else if(step===3){
      const definition=setup.providers.find(x=>x.id===provider);
      append(body,node('h2','',`Sign in through ${definition?.name||'your CLI'}`),node('p','','Open your Terminal, run this command, and complete the CLI’s own sign-in. Credentials stay with that CLI.'),node('pre','',definition?.login||''),button('Copy login command',()=>navigator.clipboard.writeText(definition.login)),button(provider==='codex'?'Check sign-in':'I’ve configured this CLI',async()=>{try{const found=setup.installed.find(x=>x.provider===provider);setup=await result(bridge.chooseCLI(found.id));const message=await result(bridge.checkLogin());verified=true;draw();toast(message);}catch(error){toast(error.message);}}));
      if(verified)body.append(node('p','','Ready to continue.'));
    }else if(step===4){await renderComposio(body);}
    else append(body,avatar('white',true),node('h2','','Ready for your first message'),node('p','','Each Bot keeps a separate CLI session. The app preserves the CLI’s tool permission settings and does not add approval bypass flags.'));
    const controls=node('div','panel-bottom');
    if(step>0)controls.append(button('Back',()=>{step--;draw();}));
    const next=button(step===5?'Start chatting':step===4?'Continue to chat':'Continue',async()=>{
      try{if(step===5){await result(bridge.completeSetup());setup.complete=true;dialog.close();render();return;}
      if(step===2){const found=setup.installed.find(x=>x.provider===provider);setup=await result(bridge.chooseCLI(found.id));}
      step++;draw();}catch(error){toast(error.message);}
    },'pill primary');
    next.disabled=(step===1&&!setup.providers.length)||(step===2&&!setup.installed.some(x=>x.provider===provider))||(step===3&&!verified)||(step===5&&!setup.installed.length);controls.append(next);body.append(controls);
  }
  try{setup=await result(bridge.scanCLIs());provider=setup.installed.find(x=>x.id===setup.selected)?.provider||'codex';}catch(error){toast(error.message);}
  await draw();
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
  const create = button('Create Bot', () => {}, 'pill primary'); create.type = 'submit'; create.disabled = true;
  name.addEventListener('input', () => create.disabled = !name.value.trim());
  append(form, face, node('label', 'muted', 'Name'), name, node('label', 'muted', 'What should it help with?'), purpose, choices, create);
  form.addEventListener('submit', async event => { event.preventDefault(); if (!name.value.trim()) return; if(workspace.bots.some(bot=>bot.name.toLowerCase()===name.value.trim().toLowerCase())){toast('A Bot with this name already exists.');return;} const next = structuredClone(workspace); const bot = { id: crypto.randomUUID(), name: name.value.trim(), purpose: purpose.value, color }; next.bots.push(bot); if (await persist(next)) { selectBot(bot.id); dialog.close(); } });
  append(content, form, node('p', 'panel-footnote', 'Creates a separate conversation with your selected AI CLI.'));
  name.focus();
}
const toolChoices=[['github','GitHub'],['gmail','Gmail'],['googledrive','Google Drive'],['googlecalendar','Google Calendar'],['slack','Slack'],['notion','Notion'],['linear','Linear'],['figma','Figma']];
async function renderComposio(content){
  const body=node('div','composio-settings');content.append(body);
  const draw=async()=>{
    body.replaceChildren();let status;
    try{status=await result(bridge.composioStatus());}catch(error){body.append(node('p','',error.message));return;}
    append(body,node('h2','','Connect your tools'),node('p','','Use your own Composio project to connect apps to your CLI. This is optional.'));
    if(!window.desktop){body.append(node('p','','Open the installed desktop app to store your project key securely.'));return;}
    if(!status.configured){
      const key=node('input','field');key.type='password';key.placeholder='Composio project API key';key.setAttribute('aria-label','Composio project API key');key.autocomplete='off';
      const chosen=new Set(),choices=node('div','catalog-grid');
      for(const [slug,name] of toolChoices){const label=node('label','setting-row');const check=node('input');check.type='checkbox';check.addEventListener('change',()=>check.checked?chosen.add(slug):chosen.delete(slug));append(label,check,node('span','',name));choices.append(label);}
      const connect=button('Connect project',async()=>{connect.disabled=true;try{const value=key.value;key.value='';await result(bridge.composioConnect(value,[...chosen]));draw();}catch(error){toast(error.message);connect.disabled=false;}},'pill primary');
      append(body,key,button('Get a project key ↗',()=>bridge.openDocs('https://platform.composio.dev')),choices,connect,node('p','muted','The project key and tool session are encrypted with Windows device storage. Composio has its own pricing and usage limits.'));
    }else{
      append(body,node('p','',`${status.toolkits.filter(x=>x.connected).length} connected`),button('Refresh connections',async()=>{try{await result(bridge.composioRefresh());draw();}catch(error){toast(error.message);}}));
      for(const toolkit of status.toolkits.filter(x=>x.enabled)){
        const row=append(node('div','setting-row'),node('strong','',toolkit.name),node('small','muted',toolkit.connected?'Connected':toolkit.noAuth?'No sign-in required':toolkit.status||'Not connected'));
        if(!toolkit.connected&&!toolkit.noAuth)row.append(button('Connect',async()=>{try{await result(bridge.composioLink(toolkit.slug));toast('Finish authorizing in your browser, then refresh connections.');}catch(error){toast(error.message);}}));body.append(row);
      }
      append(body,node('p','muted','Selected tools reach your CLI through MCP. Tool actions follow the CLI’s permission settings.'),button('Remove project from this device',async()=>{try{await result(bridge.composioRemove());draw();}catch(error){toast(error.message);}}),button('Manage or revoke accounts in Composio ↗',()=>bridge.openDocs('https://platform.composio.dev')));
    }
  };await draw();
}
async function showApps(){const content=panel('Connect Apps');try{if(bridge.composioRefresh)await result(bridge.composioRefresh());}catch(error){toast(error.message);}await renderComposio(content);}
function unavailable(title, detail) { return append(node('div', 'unavailable'), node('h2', '', title), node('p', '', detail), button('View connection status', () => showConnection())); }
function showSettings(tab = 'General') {
  dialog.replaceChildren();
  const layout = node('div', 'settings-layout'); const nav = node('nav', 'settings-nav'); const page = node('section', 'settings-page');
  for (const [name, glyph] of [['General','⚙'],['Computer','▣'],['Permissions','♧'],['Vault','⚿'],['Usage & Billing','▥'],['Updates','⇩']]) nav.append(append(button('', () => showSettings(name), name === tab ? 'active' : ''), node('span','',glyph), node('div','',name)));
  append(page, append(node('header','panel-head'), node('h1','',tab), button('×', () => dialog.close(), 'close-panel')));
  append(layout, nav, page); dialog.append(layout); if (!dialog.open) dialog.showModal();
  if (tab === 'General') {
    const promo = node('div','promo');
    append(promo, append(node('div'), node('h3','','A free app for your AI CLIs'), node('p','','Choose Codex, Claude Code, Grok Build, OpenCode, or Gemini CLI on this computer. Optionally connect tools with Composio.'), button('Set up AI and tools', () => showConnection(), 'pill primary')), append(node('div','brand-tile'), node('span','','⬡'), node('span','','✧'), avatar(), node('span','','𝕏')));
    const profile = node('input'); profile.value = localStorage.getItem('profile') || 'Local workspace'; profile.setAttribute('aria-label','Local display name'); profile.addEventListener('change', () => localStorage.setItem('profile',profile.value));
    const account = append(node('div','settings-card'), append(node('div','setting-row'), node('span','profile-icon','LP'), append(node('div','profile-text'),profile,node('small','','Uses your CLI account')),button('Connection status', () => showConnection())));
    const appearance = node('div','settings-card'); const select = node('select'); select.setAttribute('aria-label','Theme');
    for (const [value,label] of [['system','Follow System'],['dark','Dark'],['light','Light']]) { const option=node('option','',label); option.value=value; select.append(option); } select.value=localStorage.getItem('appearance') || 'dark'; select.addEventListener('change',()=>applyTheme(select.value));
    append(appearance, append(node('div','setting-row'),node('label','','Theme'),select),append(node('div','setting-row'),node('label','','Accent'),node('span','muted','Bot color')),append(node('div','setting-row'),node('label','','Language'),node('span','muted','English')));
    append(page,promo,node('p','settings-label','Account'),account,node('p','settings-label','Appearance'),appearance,button('Reset conversations…',()=>confirmReset()));
  } else if (tab === 'Computer') page.append(unavailable('This computer', 'AI CLIs run on this computer in a private folder for each Bot. Their model settings and account configuration remain with the CLI.'));
  else if (tab === 'Permissions') page.append(unavailable('CLI tool permissions', 'Codex runs with read-only workspace access. Other CLIs retain their own permissions. The app does not add approval bypass flags. Composio tools follow your CLI’s MCP permission settings.'));
  else if (tab === 'Usage & Billing') page.append(unavailable('No usage to report', 'Usage is billed or limited by your AI provider and Composio project. Check those accounts for current usage; the app does not invent a percentage.'));
  else if (tab === 'Updates') append(page,unavailable('OpenGrokBot 0.3.0','Install a new build from the project’s release artifacts. This app does not update the official Grok Bot application.'),button('Open project ↗',()=>bridge.openDocs('https://github.com/carboy285/opengrokbot')));
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
function confirmReset() { const content=panel('Reset conversations?'); append(content,node('p','','This removes local conversations and additional Bots. Your CLI login, Composio setup, and vault notes are kept.'),button('Reset conversations',async()=>{if(await persist(structuredClone(preview))){selected=workspace.bots[0].id;drafts.clear();render();dialog.close();}}),button('Cancel',()=>showSettings())); }
function showBotActions(bot) { const content=panel(bot.name); append(content,button('Export conversation…',()=>exportConversation(bot)),!bot.isMain?button('Delete Bot',async()=>{const next=structuredClone(workspace);next.bots=next.bots.filter(x=>x.id!==bot.id);next.entries=next.entries.filter(x=>x.botID!==bot.id);if(await persist(next)){selected=workspace.bots[0]?.id;render();dialog.close();}}):null); }
async function exportConversation(bot=currentBot()) { if(!bot)return; const text='OpenGrokBot — Local AI conversation\n\n'+entries(bot).map(x=>`${x.kind==='user'?'You':bot.name}: ${x.text}`).join('\n\n'); try { if(await result(bridge.export(text)))toast('Conversation exported.'); }catch(error){toast(error.message);} }
$('#composer').addEventListener('submit',async event=>{
  event.preventDefault();const bot=currentBot(),text=$('#draft').value.trim();if(!bot||!text||running.has(bot.id))return;
  if(!window.desktop){showConnection();return;}
  if(!setup.installed.length){showConnection();return;}
  try{workspace=await result(bridge.send(bot.id,text));drafts.delete(bot.id);render();$('#draft').focus();}catch(error){toast(error.message);}
});
$('#draft').addEventListener('input',()=>{ drafts.set(selected,$('#draft').value); $('#draft').style.height='auto';$('#draft').style.height=Math.min(180,$('#draft').scrollHeight)+'px'; });
$('#search-button').addEventListener('click',()=>{const slot=$('#search-slot');if(slot.firstChild){slot.replaceChildren();search='';render();return;}const field=node('input','search-input');field.placeholder='Search Bots';field.setAttribute('aria-label','Search Bots');field.addEventListener('input',()=>{search=field.value;render();});slot.append(field);field.focus();});
$('#new-button').addEventListener('click',showNewBot); $('#profile-button').addEventListener('click',()=>showSettings()); $('#apps-button').addEventListener('click',showApps); $('#status-button').addEventListener('click',()=>showConnection()); $('#attachment-button').addEventListener('click',()=>{const content=panel('Conversation actions');append(content,button('Export conversation…',()=>exportConversation()),button('Attachment status',()=>toast('Paste text into your message. File attachments are not supported yet.')));});
for(const control of document.querySelectorAll('[data-window]')) control.addEventListener('click',()=>window.desktop?.windowAction(control.dataset.window));
window.addEventListener('blur',()=>{focusGeneration++;for(const secret of document.querySelectorAll('.revealed-secret')){secret.textContent='';secret.hidden=true;}for(const field of document.querySelectorAll('input[type=password]'))field.value='';});
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey))return;if(event.key==='n'){event.preventDefault();showNewBot();}else if(event.key===','){event.preventDefault();showSettings();}else if(event.key==='f'){event.preventDefault();$('#search-button').click();}else if(event.key==='Enter'&&!dialog.open){event.preventDefault();$('#composer').requestSubmit();}});
bridge.onChange?.(value=>{workspace=value.workspace;running=new Set(value.running);render();$('#messages').scrollTop=$('#messages').scrollHeight;});
try { workspace=await result(bridge.load());selected=workspace.bots[0]?.id; setup=await result(bridge.scanCLIs()); }catch(error){toast(error.message);}
render();

if(window.desktop&&!setup.complete)showConnection();
