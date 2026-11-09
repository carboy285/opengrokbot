import { preview } from './seed.js';
import { createVoice } from './voice.js';
import { renderApiKeys } from './api-keys.js';
import { renderSecureLogins } from './secure-logins.js';
import { encodeWav } from './voice-core.mjs';
import * as catalog from './catalog.js';

const $ = selector => document.querySelector(selector);
const node = (tag, className = '', text = '') => { const value = document.createElement(tag); value.className = className; value.textContent = text; return value; };
const button = (text, action, className = 'pill') => { const value = node('button', className, text); value.type = 'button'; value.addEventListener('click', action); return value; };
const append = (parent, ...children) => { parent.append(...children.filter(Boolean)); return parent; };
const avatarColors={white:'#ffffff',black:'#111111',purple:'#9355ff',pink:'#fa2a99',ochre:'#a46e39',red:'#ff2948',orange:'#ff7012',amber:'#f69a0a',green:'#10bf70',teal:'#15b6a5',blue:'#2385ff',gray:'#969696'};
const avatarShapes=['circle','cloud','square','sparkle','flower','heart','clover','droplet','capsule','triangle','pebble','star','hexagon','fruit'];
const shapePaths=new Map();
function avatar(value='white',starred=false){
 const bot=typeof value==='object'?value:{color:value},appearance=bot.appearance||{color:bot.color,shape:bot.color==='white'||bot.color==='pink'?'circle':bot.color==='ochre'?'hexagon':'pebble'};
 const face=node('span','avatar custom-avatar');face.style.setProperty('--avatar-color',avatarColors[appearance.color]||avatarColors.purple);face.setAttribute('aria-hidden','true');
 if(appearance.imageData){const img=node('img');img.src='data:image/jpeg;base64,'+appearance.imageData;img.alt='';face.append(img);}
 else{
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 100 100');
  const path=document.createElementNS(svg.namespaceURI,'path');let d='';
  if(appearance.shape==='heart')d='M50 94 C10 75 -10 55 4 30 C10 -2 40 1 50 22 C60 1 90 -2 96 30 C110 55 90 75 50 94 Z';
  else if(appearance.shape==='square')d='M22 8 Q12 8 12 18 L12 82 Q12 92 22 92 L78 92 Q88 92 88 82 L88 18 Q88 8 78 8 Z';
  else if(shapePaths.has(appearance.shape))d=shapePaths.get(appearance.shape);
  else {for(let i=0;i<120;i++){const a=i/120*2*Math.PI-Math.PI/2;let r=.46;switch(appearance.shape){case'hexagon':r=.42/Math.cos((a+2*Math.PI)%(Math.PI/3)-Math.PI/6);break;case'cloud':r=.42+.055*Math.cos(7*a)+.025*Math.sin(3*a);break;case'flower':r=.41+.07*Math.cos(5*a);break;case'star':r=.37+.105*Math.cos(6*a);break;case'sparkle':r=.37+.11*Math.cos(4*a);break;case'clover':r=.4+.085*Math.cos(4*a+.6);break;case'triangle':r=.37+.105*Math.cos(3*a);break;case'droplet':r=.39+.08*Math.cos(a)+.055*Math.cos(3*a);break;case'pebble':r=.43+.035*Math.cos(3*a)+.025*Math.sin(2*a);break;case'capsule':r=.45;break;}d+=(i?'L':'M')+(50+100*r*Math.cos(a))+','+(50+100*r*Math.sin(a));}d+='Z';shapePaths.set(appearance.shape,d);}
  path.setAttribute('d',d);path.setAttribute('fill','var(--avatar-color)');if(appearance.shape==='square')path.setAttribute('transform','rotate(-20 50 50)');if(appearance.shape==='capsule')path.setAttribute('transform','translate(0 12) scale(1 .76)');svg.append(path);
  for(const [x,y]of [[42,36],[63,32]]){const eye=document.createElementNS(svg.namespaceURI,'rect');for(const[k,v]of Object.entries({x,y,width:9,height:24,rx:4.5,fill:appearance.color==='white'?'#111':'#fff',transform:'rotate(-25 50 50)'}))eye.setAttribute(k,v);svg.append(eye);}face.append(svg);
 }
 if(starred)face.append(node('b','','★'));return face;
}
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
const pendingFiles=new Map();
let inspectorOpen=false,inspectorTab="Details",inspectorSignature="",inspectorGeneration=0;
const modelCatalogs=new Map();
const browserActivity=new Map();
let search = '';
let toastTimer;
let focusGeneration = 0;
const drafts = new Map();
const pendingSends=new Map();
let folderFilter='*',draggedBot=null,draftTimer,displayedBot=null,cloudStatus=null;
function persistDrafts(){clearTimeout(draftTimer);draftTimer=setTimeout(()=>{bridge.saveDrafts?.(Object.fromEntries(drafts)).then(response=>{if(!response.ok)toast(response.error);}).catch(()=>toast('Your draft could not be saved.'));},400);}
const isPinned=bot=>bot.isPinned??!!bot.isMain;
const recentBots=bots=>bots.map((bot,index)=>({bot,index,time:Date.parse(bot.lastUsedAt)||0})).sort((a,b)=>b.time-a.time||a.index-b.index).map(x=>x.bot);
const orderedBots=()=>workspace.bots.map((bot,index)=>({bot,index})).sort((a,b)=>(a.bot.sortOrder??a.index)-(b.bot.sortOrder??b.index)).map(x=>x.bot);
async function organize(bot,changes){try{if(bridge.organizeBot)workspace=await result(bridge.organizeBot(bot.id,changes));else{const next=structuredClone(workspace);Object.assign(next.bots.find(x=>x.id===bot.id),changes);if(!await persist(next))return;}render();}catch(error){toast(error.message);}}
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
function selectBot(id) { if (currentBot()) drafts.set(selected, $('#draft').value); selected = id;const bot=currentBot();if(bot)bot.lastUsedAt=new Date().toISOString();bridge.touchBot?.(id).then(response=>{if(!response.ok)toast(response.error);}).catch(()=>{});if(bot?.unread){bot.unread=false;bridge.organizeBot?.(id,{unread:null}).catch?.(()=>{});}render(); }
function render() {
  const chatMatches=new Set(search?workspace.entries.filter(x=>x.text.toLowerCase().includes(search.toLowerCase())).map(x=>x.botID):[]);
  const matches=bot=>(!bot.hidden||!!search)&&(`${bot.name} ${bot.purpose}`.toLowerCase().includes(search.toLowerCase())||chatMatches.has(bot.id))&&(folderFilter==='*'||(bot.folder||'')===folderFilter);
  const primary=$('#primary-bot');primary.replaceChildren();
  const matching=orderedBots().filter(x=>matches(x));const heroes=[...matching.filter(x=>x.isMain&&isPinned(x)),...matching.filter(x=>!x.isMain&&isPinned(x))];
  for(const bot of heroes){const tile=append(button('',()=>selectBot(bot.id),`primary-card ${selected===bot.id?'selected':''}`),avatar(bot,true),node('span','',bot.name));tile.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});wireBotDrag(tile,bot);primary.append(tile);}
  const lastText=new Map();for(const entry of workspace.entries)lastText.set(entry.botID,entry.text);
  const list=$('#bot-list');list.replaceChildren();
  const visible=recentBots(matching.filter(bot=>!isPinned(bot)));
  for(const bot of visible){
    const row=button('',()=>selectBot(bot.id),`bot-row ${bot.id===selected?'selected':''}`);row.draggable=true;
    const preview=String(lastText.get(bot.id)||bot.purpose||'').slice(0,90);
    append(row,avatar(bot),append(node('span','details'),append(node('strong','',bot.name),...(isPinned(bot)?[node('i','pin','⚲')]:[]),...(bot.unread&&bot.id!==selected?[Object.assign(node('i','unread-dot'),{title:'Unread'})]:[])),node('small','',running.has(bot.id)?'Working…':preview)));
    row.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});
    wireBotDrag(row,bot);list.append(row);
  }
  if(!visible.length&&!primary.children.length)list.append(node('p','empty','No Bots found.'));
  renderFolderFilter();
  const bot = currentBot();
  $('#chat-heading').replaceChildren();
  const draft=$('#draft');if(displayedBot!==selected||document.activeElement!==draft){draft.value=drafts.get(selected)||'';displayedBot=selected;}renderChips();
  draft.disabled=!bot;if(!bot){$('#messages').replaceChildren(node('div','empty','Create a Bot to start chatting.'));return;}
  append($('#chat-heading'),avatar(bot),node('span','',bot.name));draft.placeholder=`Ask ${bot.name}`;
  document.documentElement.style.setProperty('--bot-accent',avatarColors[bot.appearance?.color||bot.color]||'#9355ff');
  document.documentElement.style.setProperty('--bot-ink',['white','amber','orange','green','teal','gray'].includes(bot.appearance?.color||bot.color)?'#000':'#fff');
  renderMessages(bot);
  const activeCLI=setup.installed.find(x=>x.id===setup.selected);$('#status-button').textContent=activeCLI?`${activeCLI.name} · On this device`:'Set up an AI CLI';$('#status-button').hidden=!!activeCLI;

  renderInspector();renderBrowserPill();
}
function wireBotDrag(row,bot){
 row.draggable=true;row.addEventListener('dragstart',event=>{draggedBot=bot.id;event.dataTransfer.setData('text/plain',bot.id);event.dataTransfer.effectAllowed='move';});row.addEventListener('dragend',()=>{draggedBot=null;});row.addEventListener('dragover',event=>{if(draggedBot)event.preventDefault();});
 row.addEventListener('drop',async event=>{event.preventDefault();const from=draggedBot;draggedBot=null;if(!from||from===bot.id||!bridge.reorderBots)return;const ids=orderedBots().map(x=>x.id).filter(id=>id!==from);ids.splice(ids.indexOf(bot.id),0,from);try{workspace=await result(bridge.reorderBots(ids));render();}catch(error){toast(error.message);}});
}
function renderFolderFilter(){
 let picker=$('#folder-filter');const values=[...new Set(workspace.bots.map(x=>x.folder).filter(Boolean))].sort();
 if(!picker){picker=node('select','folder-filter');picker.id='folder-filter';picker.setAttribute('aria-label','Filter Bot folders');picker.addEventListener('change',()=>{folderFilter=picker.value;render();});$('#search-slot').before(picker);}
 picker.replaceChildren();for(const[value,label]of [['*','All Bots'],['','Unfiled'],...values.map(x=>[x,x])]){const option=node('option','',label);option.value=value;picker.append(option);}if(!['*','',...values].includes(folderFilter))folderFilter='*';picker.value=folderFilter;
}
const chatScroll={bot:null,follow:true,frame:null,programmatic:false,userUntil:0,lastTop:0};
const chatViewport=$('#messages');
function scheduleChatBottom(){
 if(!chatScroll.follow||chatScroll.frame!==null)return;
 chatScroll.frame=requestAnimationFrame(()=>{chatScroll.frame=null;if(!chatScroll.follow)return;chatScroll.programmatic=true;chatViewport.scrollTop=chatViewport.scrollHeight;requestAnimationFrame(()=>{chatScroll.programmatic=false;});});
}
function scrollIntent(event){
 chatScroll.userUntil=performance.now()+600;
 if(event.type==='wheel'&&event.deltaY<0){chatScroll.follow=false;chatScroll.programmatic=false;}
}
chatViewport.tabIndex=0;
chatViewport.addEventListener('wheel',scrollIntent,{passive:true});
chatViewport.addEventListener('touchstart',scrollIntent,{passive:true});
chatViewport.addEventListener('touchmove',scrollIntent,{passive:true});
chatViewport.addEventListener('pointerdown',scrollIntent,{passive:true});
chatViewport.addEventListener('pointermove',event=>{if(event.buttons)scrollIntent(event);},{passive:true});
chatViewport.addEventListener('keydown',event=>{if(['ArrowUp','ArrowDown','PageUp','PageDown','Home','End',' '].includes(event.key))scrollIntent(event);});
chatViewport.addEventListener('scroll',()=>{const top=chatViewport.scrollTop;if(!chatScroll.programmatic&&performance.now()<chatScroll.userUntil){if(top<chatScroll.lastTop-1)chatScroll.follow=false;else if(top>chatScroll.lastTop)chatScroll.follow=chatViewport.scrollHeight-top-chatViewport.clientHeight<80;}chatScroll.lastTop=top;},{passive:true});
const chatResizeObserver=new ResizeObserver(()=>scheduleChatBottom());chatResizeObserver.observe(chatViewport);
function renderMessages(bot){
 let messages=$('#message-content');if(!messages){messages=node('div');messages.id='message-content';chatViewport.replaceChildren(messages);chatResizeObserver.observe(messages);}
 const previousScroll=chatViewport.scrollTop;
 if(chatScroll.bot!==bot.id){chatScroll.bot=bot.id;chatScroll.follow=true;chatScroll.userUntil=0;messages.replaceChildren();messages.dataset.bot=bot.id;messages.rows=new Map();}
 const rows=messages.rows||=new Map();
 for(const el of messages.querySelectorAll('[data-extra]'))el.remove();
 const live=new Set();let index=0;const lastEntryID=entries(bot).at(-1)?.id;
 for(const entry of entries(bot)){
  live.add(entry.id);let row=rows.get(entry.id);
  if(!row){row=node('div',entry.kind==='activity'||entry.delivery==='scheduled'?'activity':`message-row ${entry.kind}`);row.dataset.entry=entry.id;row.append(node('div','message-body'));rows.set(entry.id,row);}
  const body=row.firstElementChild;if(row.entryText!==entry.text||row.dataset.state!==(entry.state||'')){body.replaceChildren();if(entry.senderName)body.append(node('small','muted',`Message from ${entry.senderName}`));if(entry.state==='failed'&&entry.provider)body.append(node('small','muted',entry.provider));body.append(node('div','bubble',entry.text||(entry.state==='streaming'?'Thinking…':'')));if(entry.kind==='user')body.append(node('small','delivery-state',entry.delivery==='scheduled'?'Routine started':'Delivered'));if(entry.state==='failed'){body.append(button('Retry response',async()=>{try{await result(bridge.retry(bot.id));}catch(error){toast(error.message);}}));}row.entryText=entry.text;row.dataset.state=entry.state||'';}
  if(entry.kind!=='activity'&&entry.delivery!=='scheduled'){const key=`${entry.reaction||''}|${entry.state||''}|${running.has(bot.id)}|${entry.id===lastEntryID}`;if(row.toolsKey!==key||!body.querySelector(':scope>.message-tools')){body.querySelector(':scope>.message-tools')?.remove();row.toolsKey=key;body.append(messageTools(bot,entry,entry.id===lastEntryID));}}
  if(messages.children[index]!==row)messages.insertBefore(row,messages.children[index]||null);index++;
 }
 for(const [id,row] of rows)if(!live.has(id)){row.remove();rows.delete(id);}
 const pending=pendingSends.get(bot.id);
 if(pending&&!live.has(pending.id)){const row=append(node('div','message-row user pending'),append(node('div','message-body'),node('div','bubble',pending.text),node('small','delivery-state',pending.failed?'Failed to send':'Sending…')));row.dataset.extra='true';if(pending.failed)row.firstChild.append(button('Retry sending',()=>submitMessage(bot,pending.text,pending.id)));messages.append(row);}
 if(!entries(bot).length&&!pending){const empty=node('div','empty','What’s on your mind?');empty.dataset.extra='true';messages.append(empty);}
 if(running.has(bot.id)){const stop=button('Stop response',()=>bridge.stop(bot.id));stop.dataset.extra='true';messages.append(stop);}
 $('#save-note').disabled=running.has(bot.id)||!!pending&&!pending.failed;$('#save-note').setAttribute('aria-label',pending&&!pending.failed?'Sending message':'Send message');
 if(chatScroll.follow)scheduleChatBottom();else chatViewport.scrollTop=previousScroll;
}
async function submitMessage(bot,text,id=crypto.randomUUID(),files=pendingFiles.get(bot.id)||[]){
 if(running.has(bot.id)||pendingSends.get(bot.id)&&!pendingSends.get(bot.id).failed)return;
 if(selected===bot.id)chatScroll.follow=true;
 const pending={id,text:text||(files.length?`📎 ${files.length} attachment${files.length===1?'':'s'}`:''),failed:false};pendingSends.set(bot.id,pending);drafts.set(bot.id,text);persistDrafts();renderMessages(bot);
 try{workspace=await result(bridge.send(bot.id,text,id,files.length?files:undefined));pendingSends.delete(bot.id);if(files.length&&pendingFiles.get(bot.id)===files){pendingFiles.delete(bot.id);renderChips();}if(drafts.get(bot.id)===text){drafts.delete(bot.id);if(selected===bot.id&&$('#draft').value.trim()===text)$('#draft').value='';}persistDrafts();render();if(selected===bot.id)$('#draft').focus();}
 catch(error){pending.failed=true;toast(error.message);if(selected===bot.id)renderMessages(bot);}
}
function configuration(bot){const active=setup.installed.find(x=>x.id===setup.selected);return bot.aiConfiguration||{providers:active?[{provider:active.provider,model:''}]:[],activeProvider:active?.provider,replyMode:'one'};}
function toggleInspector(open=!inspectorOpen){inspectorOpen=open;renderInspector();}
async function configureBot(bot,value){try{value.replyMode='one';workspace=await result(bridge.configureBot(bot.id,value));inspectorSignature='';renderInspector();}catch(error){toast(error.message);}}
function renderInspector(){
 const pane=$('#bot-inspector'),bot=currentBot();pane.hidden=!inspectorOpen||!bot;$('#workspace').classList.toggle('inspector-open',!pane.hidden);$('#chat-heading').setAttribute('aria-expanded',String(!pane.hidden));
 if(pane.hidden){inspectorSignature='';inspectorGeneration++;return;}
 const config=configuration(bot),busy=running.has(bot.id),signature=JSON.stringify([bot,inspectorTab,busy,setup.installed,modelCatalogs.size,workspace.sharedMemory]);
 if(signature===inspectorSignature)return;inspectorSignature=signature;const generation=++inspectorGeneration;
 pane.replaceChildren();
 const controls=node('div','inspector-actions');const share=button('↑',()=>exportConversation(bot),'circle glass');share.setAttribute('aria-label','Share conversation');const close=button('×',()=>toggleInspector(false),'circle glass');close.setAttribute('aria-label','Close bot details');append(controls,share,close);
 const avatarButton=append(button('',()=>showAvatarPicker(bot),'avatar-edit'),avatar(bot));avatarButton.setAttribute('aria-label','Change Bot avatar');const profile=append(node('div','inspector-profile'),avatarButton,node('h2','',bot.name));
 const tabs=node('nav','inspector-tabs');tabs.setAttribute('aria-label','Bot details tabs');
 for(const name of ['Details','Library','Computer']){const tab=button(name,()=>{inspectorTab=name;renderInspector();},name===inspectorTab?'active':'');tab.setAttribute('aria-current',String(name===inspectorTab));tabs.append(tab);}
 const body=node('div','inspector-body');append(pane,controls,profile,tabs,body);
 let providersMark;
 if(inspectorTab==='Details'){
  append(body,node('h3','','Linux VM'),node('p','muted','All Bots share one VM (set up once, here or on another computer).'),button('Shared Linux VM settings…',()=>showBotVM(workspace.bots.find(x=>x.isMain)||bot)));
  append(body,node('h3','','Knowledge'),node('p','muted','Text, Markdown and CSV files this Bot can search instead of needing them attached to every message.'),button('Add knowledge files…',async()=>{try{const added=await result(bridge.knowledgeAdd(bot.id));if(added)toast(`Added ${added} file${added===1?'':'s'} to ${bot.name}’s Knowledge. Ask it to search them.`);}catch(error){toast(error.message);}}));
  append(body,node('h3','','Local browser'),node('p','muted','Its own browser profile, in a window on this PC.'),button('Open local browser',async()=>{try{await result(bridge.openBrowser(bot.id));}catch(error){toast(error.message);}}));
  append(body,node('h3','','Routines'),node('p','muted','Ask the Bot to run a task once, on a repeat, or when another Bot messages it. The app must be running; missed runs catch up once.'));
  for(const task of bot.schedules||[]){const history=node('details'),summary=node('summary','','Run history');history.append(summary);for(const run of task.history||[])history.append(node('p','muted',`${run.date} · ${run.status}`));if(task.history?.length)body.append(history);append(body,node('p','',`${task.name} · ${task.enabled?(task.nextRun||'Incoming Bot message'):'Paused'} · ${task.recurrence} · ${task.timezone}${task.lastRun?' · Last run: '+task.lastRun+' · '+(task.lastResult||'outcome unavailable'):''}`),append(node('div','row-actions'),...(bridge.pauseTask?[button(task.enabled?'Pause':'Resume',async()=>{try{await result(bridge.pauseTask(bot.id,task.id,!task.enabled));}catch(error){toast(error.message);}})]:[]),button('Delete',async()=>{try{await result(bridge.cancelTask(bot.id,task.id));}catch(error){toast(error.message);}})));}
  if(!(bot.schedules||[]).length)body.append(node('p','muted','No routines yet. You can also ask in chat to add one.'));
  append(body,node('h3','','Voice chat'),voiceCard(bot));
  if(bot.memberIDs){body.append(node('h3','','Group members'));for(const member of workspace.bots.filter(x=>bot.memberIDs.includes(x.id)))body.append(button(member.name,()=>selectBot(member.id)));body.append(node('p','muted','Each member answers with its own provider and model.'));}
  else{
   providersMark=body.childNodes.length;
   append(body,node('h3','','Providers & models'),node('p','muted','Pick the provider and model that answer for this Bot. Access follows each CLI’s account.'));
   if(config.providers.length>1){const select=node('select','field');select.setAttribute('aria-label','Active provider');for(const choice of config.providers){const option=node('option','',setup.providers.find(x=>x.id===choice.provider)?.name||choice.provider);option.value=choice.provider;select.append(option);}select.value=config.activeProvider||config.providers[0].provider;select.disabled=busy;select.addEventListener('change',()=>configureBot(bot,{...config,activeProvider:select.value}));append(body,node('label','','Active provider'),select);}
   for(const provider of setup.providers){
    const choice=config.providers.find(x=>x.provider===provider.id),installed=setup.installed.find(x=>x.provider===provider.id),card=node('div','provider-card');
    const check=node('input');check.type='checkbox';check.checked=!!choice;check.disabled=busy||(!installed&&!choice);check.setAttribute('aria-label',`Enable ${provider.name}`);
    check.addEventListener('change',()=>{const value=structuredClone(config);if(check.checked){value.providers.push({provider:provider.id,model:''});value.activeProvider||=provider.id;}else{value.providers=value.providers.filter(x=>x.provider!==provider.id);if(value.activeProvider===provider.id)value.activeProvider=value.providers[0]?.provider;}configureBot(bot,value);});
    const label=append(node('label','provider-label'),check,node('strong','',provider.name));card.append(label);
    if(!installed)append(card,node('small','muted','Not installed on this device'),button('Set up',()=>showConnection()));
    if(choice){
     const models=modelCatalogs.get(provider.id)||[];
     if(models.length){const picker=node('select','field');picker.setAttribute('aria-label',`${provider.name} model`);const options=[{id:'',name:'CLI default'},...models];if(choice.model&&!models.some(x=>x.id===choice.model))options.push({id:choice.model,name:choice.model});for(const model of options){const option=node('option','',model.name);option.value=model.id;picker.append(option);}picker.value=choice.model;picker.disabled=busy;picker.addEventListener('change',()=>saveModel(picker.value));card.append(picker);}
     const field=node('input','field');field.placeholder='Model ID · blank uses CLI default';field.value=choice.model;field.maxLength=200;field.disabled=busy;field.setAttribute('aria-label',`${provider.name} model ID`);
     const saveModel=value=>{if(/[\r\n]/.test(value)||value.length>200){toast('Enter a model ID of up to 200 characters.');return;}const next=structuredClone(config);next.providers.find(x=>x.provider===provider.id).model=value.trim();configureBot(bot,next);};
     const apply=button('Apply',()=>saveModel(field.value));apply.disabled=busy;apply.setAttribute('aria-label',`Apply ${provider.name} model`);card.append(append(node('div','model-entry'),field,apply));
     if(['codex','opencode'].includes(provider.id)){const load=button('Load available models',async()=>{load.disabled=true;load.textContent='Loading models…';try{const models=await result(bridge.listModels(provider.id));modelCatalogs.set(provider.id,models);inspectorSignature='';renderInspector();if(!models.length)toast('No model list returned. Enter an exact model ID.');}catch(error){toast(error.message);load.disabled=false;}});load.disabled=!installed;load.setAttribute('aria-label',`Load ${provider.name} models`);card.append(load);}
    }body.append(card);
   }
   body.append(node('p','muted','Only the active provider and model answer for this Bot.'));
  }
  let providersBox;if(providersMark!==undefined){providersBox=node('details','providers-box');providersBox.open=localStorage.getItem('providersOpen')!=='0'||!config.providers.length;providersBox.addEventListener('toggle',()=>localStorage.setItem('providersOpen',providersBox.open?'1':'0'));providersBox.append(node('summary','','Providers & models'),...[...body.childNodes].slice(providersMark));}
  if(!bot.isMain)body.append(node('p','',bot.purpose));
  for(const [title,memory] of [['This Bot’s memory',bot.memory],['Shared memory',workspace.sharedMemory]])if(memory?.length){body.append(node('h3','',title));for(const fact of memory)body.append(node('p','memory-fact',fact));}
  body.append(button(isPinned(bot)?'Unpin Bot':'Pin to top',()=>organize(bot,{isPinned:!isPinned(bot)})));body.append(button('Organize Bot…',()=>showBotActions(bot)));if(providersBox)body.append(providersBox);
 }else if(inspectorTab==='Computer'){
  const choice=config.providers.find(x=>x.provider===config.activeProvider)||config.providers[0],provider=setup.providers.find(x=>x.id===choice?.provider);
  append(body,node('h3','','Runs on this device'),node('p','',provider?.name||'Choose an AI CLI'),node('p','muted',choice?.model||'CLI default model'),node('p','muted',busy?'Working…':'Each Bot keeps its own working folder.'),button('AI CLI setup',()=>showConnection()),button('Open working folder',()=>bridge.openBotFolder(bot.id)));
 }else{
  const files=node('div','library-files');body.append(files);
  const refresh=async()=>{try{const list=await result(bridge.listFiles(bot.id));if(generation!==inspectorGeneration)return;files.replaceChildren();if(!list.length)append(files,node('h3','','No files yet'),node('p','muted','Files created in this Bot’s working folder appear here.'));for(const file of list)files.append(button(file.name,()=>bridge.revealBotFile(bot.id,file.name),'file-row'));}catch(error){if(generation===inspectorGeneration)files.textContent=error.message;}};
  append(body,button('Refresh',refresh),button('Open folder',()=>bridge.openBotFolder(bot.id)));refresh();
 }
}
$('#chat-heading').addEventListener('click',()=>toggleInspector());
$('#draft').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey&&!event.isComposing){event.preventDefault();event.stopPropagation();$('#composer').requestSubmit();}});
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!dialog.open&&inspectorOpen){event.preventDefault();toggleInspector(false);}});
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
      for(const candidate of setup.providers){const found=setup.installed.find(x=>x.provider===candidate.id);body.append(button(`${provider===candidate.id?'✓ ':''}${candidate.name} · ${found?.version||'Not installed'}${setup.health?.[candidate.id]?' · '+setup.health[candidate.id].detail:''}`,async()=>{provider=candidate.id;verified=false;if(found)setup=await result(bridge.chooseCLI(found.id));draw();},'setting-row'));}
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
async function showApps(){const content=panel('Connect Apps');await renderCatalog(content);}
function unavailable(title, detail) { return append(node('div', 'unavailable'), node('h2', '', title), node('p', '', detail), button('View connection status', () => showConnection())); }
function showSettings(tab = 'General') {
  dialog.replaceChildren();
  const layout = node('div', 'settings-layout'); const nav = node('nav', 'settings-nav'); const page = node('section', 'settings-page');
  for (const [name, glyph] of [['General','⚙'],['Computer','▣'],['Permissions','♧'],['API Keys','⚷'],['Secure Logins','⚿'],['Vault','⚿'],['Voice','♫'],['Backup','⛁'],['Usage & Billing','▥'],['Updates','⇩']]) nav.append(append(button('', () => showSettings(name), name === tab ? 'active' : ''), node('span','',glyph), node('div','',name)));
  append(page, append(node('header','panel-head'), node('h1','',tab), button('×', () => dialog.close(), 'close-panel')));
  append(layout, nav, page); dialog.append(layout); if (!dialog.open) dialog.showModal();
  if (tab === 'General') {
    const promo = node('div','promo');
    append(promo, append(node('div'), node('h3','','A free app for your AI CLIs'), node('p','','Choose Codex, Claude Code, Grok Build, OpenCode, or Gemini CLI on this computer. Optionally connect tools with Composio.'), button('Set up AI and tools', () => showConnection(), 'pill primary')), append(node('div','brand-tile'), node('span','','⬡'), node('span','','✧'), avatar(), node('span','','𝕏')));
    const profile = node('input'); profile.value = localStorage.getItem('profile') || 'Local workspace'; profile.setAttribute('aria-label','Local display name'); profile.addEventListener('change', () => localStorage.setItem('profile',profile.value));
    const account = append(node('div','settings-card'), append(node('div','setting-row'), node('span','profile-icon',(localStorage.getItem('profile')||'You').slice(0,2).toUpperCase()), append(node('div','profile-text'),profile,node('small','','Uses your CLI account')),button('Connection status', () => showConnection())));
    const appearance = node('div','settings-card'); const select = node('select'); select.setAttribute('aria-label','Theme'); const accentSelect = node('select'); accentSelect.setAttribute('aria-label','Accent'); for (const [value,label] of [['bot','Bot color'],['neutral','Neutral']]) { const option=node('option','',label); option.value=value; accentSelect.append(option); } accentSelect.value=localStorage.getItem('accentStyle')==='neutral'?'neutral':'bot'; accentSelect.addEventListener('change',()=>{localStorage.setItem('accentStyle',accentSelect.value);applyAccent();});
    for (const [value,label] of [['system','Follow System'],['dark','Dark'],['light','Light']]) { const option=node('option','',label); option.value=value; select.append(option); } select.value=localStorage.getItem('appearance') || 'dark'; select.addEventListener('change',()=>applyTheme(select.value));
    append(appearance, append(node('div','setting-row'),node('label','','Theme'),select),append(node('div','setting-row'),node('label','','Accent'),accentSelect),append(node('div','setting-row'),node('label','','Language'),node('span','muted','English')));
    append(page,promo,node('p','settings-label','Account'),account,node('p','settings-label','Appearance'),appearance,button('Reset conversations…',()=>confirmReset()));
  } else if (tab === 'Computer') { page.append(button('Shared VM for all Bots…',()=>showBotVM(workspace.bots.find(x=>x.isMain)||currentBot()))); page.append(button('View another computer on this account',async()=>{try{await result(bridge.openMirror());}catch(error){toast(error.message);}})); page.append(unavailable('This computer', 'AI CLIs run on this computer in a private folder for each Bot.')); renderRemoteAccess(page); renderSharing(page); page.append(node('p','muted','Each Bot has its own visible local browser with separate cookies and login storage. Open it from Bot details. No cloud browser account is required.')); }
  else if (tab === 'Permissions') renderPermissions(page);
  else if (tab === 'Usage & Billing') page.append(unavailable('No usage to report', 'Usage is billed or limited by your AI provider and Composio project. Check those accounts for current usage; the app does not invent a percentage.'));
  else if (tab === 'Updates') renderUpdates(page);
  else if (tab === 'Vault') renderVault(page);
  else if (tab === 'API Keys') renderApiKeys({ bridge, result, toast, page });
  else if (tab === 'Secure Logins') renderSecureLogins({ bridge, result, toast, page });
  else if (tab === 'Voice') voice.renderSettings(page);
  else if (tab === 'Backup') renderBackup(page);
}
async function renderRemoteAccess(page){
 const body=node('section','composio-settings');page.append(body);let disposed=false;const draw=async()=>{
  if(!body.isConnected){disposed=true;return;}let status;try{status=await result(bridge.cloudStatus());}catch(error){body.replaceChildren(node('p','',error.message));return;}if(disposed||!body.isConnected)return;cloudStatus=status;body.replaceChildren();
  append(body,node('h2','','iPhone remote control'),node('p','','Sign in with the same account as your iPhone. Your computer runs the work; approved phones control its Bots.'),node('p',`connection-state ${status.phase}`,status.feedback),status.pinSyncMessage?node('p','muted',status.pinSyncMessage):null);
  const run=async operation=>{for(const control of body.querySelectorAll('button'))control.disabled=true;try{await result(operation);}catch(error){toast(error.message);}if(body.isConnected)draw();};
  if(!status.signedIn){const email=node('input','field'),password=node('input','field');email.type='email';email.placeholder='Email';email.autocomplete='username';email.setAttribute('aria-label','Account email');password.type='password';password.placeholder='Password';password.autocomplete='current-password';password.setAttribute('aria-label','Account password');const form=node('form');append(form,email,password);const sign=button('Sign in',()=>{});sign.type='submit';form.append(sign);form.addEventListener('submit',event=>{event.preventDefault();const value=password.value;password.value='';run(bridge.cloudSignIn(email.value,value,false));});append(body,form,button('Create account',()=>{const value=password.value;password.value='';run(bridge.cloudSignIn(email.value,value,true));}));}
  else{
   append(body,node('strong','',status.email),button(status.enabled?'Turn off phone access':'Allow phone access',()=>run(bridge.cloudEnabled(!status.enabled))),button('Reconnect now',()=>run(bridge.cloudReconnect())),node('p','fingerprint',`This computer: ${status.fingerprint}`));
   for(const phone of status.phones){const row=append(node('div','settings-card'),node('strong','',phone.name),node('p','fingerprint',phone.fingerprint),node('small','muted',phone.approved?'Approved':'Compare this fingerprint with your iPhone before approving.'));row.append(button(phone.approved?'Revoke':'Approve phone',()=>run(bridge.cloudApprove(phone.id,!phone.approved))));body.append(row);}
   if(!status.phones.length)body.append(node('p','muted','Sign in on your iPhone to make it appear here.'));body.append(button('Sign out on this computer',()=>run(bridge.cloudSignOut())));
  }
  const diagnostics={state:status.phase,enabled:status.enabled,lastHeartbeat:status.lastHeartbeat||null,lastPhoneRequest:status.lastRequest||null,approvedPhones:status.phones.filter(x=>x.approved).length};append(body,node('p','muted','Keep this computer awake with OpenGrokBot running. Closing the window keeps phone access running in the system tray.'),button('Copy connection diagnostics',()=>navigator.clipboard.writeText(JSON.stringify(diagnostics,null,2))));
 };if(!bridge.cloudStatus){body.append(node('p','','Open the installed Windows app to connect your iPhone.'));return;}await draw();const timer=setInterval(()=>{if(!body.isConnected){clearInterval(timer);return;}if(!body.querySelector('input'))draw();},4000);
}
/** Keys and connectors can be copied to and from this computer only while this switch is on (off until you turn it on). */
async function renderSharing(page){
 if(!bridge.sharingGet)return;
 const wrap=node('div','voice-settings');const row=node('label','voice-row');const box=document.createElement('input');box.type='checkbox';
 try{box.checked=await result(bridge.sharingGet());}catch{box.checked=false;}
 box.addEventListener('change',async()=>{try{box.checked=await result(bridge.sharingSet(box.checked));toast(box.checked?'Keys and connectors can now be copied to or from this computer.':'Keys and connectors can no longer be copied.');}catch(error){box.checked=!box.checked;toast(error.message);}});
 row.append(node('span','','Share keys and connectors with my other computers'),box);
 wrap.append(row,node('p','muted','Off by default. Turn it on here and on the other computer before its “Copy everything” button can send or take your AI provider keys, voice keys and connectors. They only travel inside your encrypted account link. Secure logins are never copied.'));
 page.append(wrap);
}
async function renderUpdates(page){
 const body=append(node('section','settings-card'),node('h2','','App updates'),node('p','muted','Updates come from the official project releases and are checked for size and integrity. Restart closes the app, installs the update and reopens it. Your workspace is kept.'));page.append(body);
 const check=button('Check for updates',async()=>{check.disabled=true;try{const update=await result(bridge.checkUpdates());body.append(node('p','',update.available?`${update.version} is available${update.prerelease?' (development release)':''}.`:`You’re using ${update.current}. No newer release is published.`));if(update.available){if(update.installer&&bridge.downloadUpdate){const action=button('Download update',async()=>{action.disabled=true;if(action.dataset.ready!=='true'){action.textContent='Downloading…';try{await result(bridge.downloadUpdate());action.dataset.ready='true';action.textContent='Restart and install';body.append(node('p','muted','Downloaded and verified. Restart closes the app, installs the update and reopens it. Your workspace is kept.'));}catch(error){toast(error.message);action.textContent='Download update';}action.disabled=false;return;}action.textContent='Restarting…';try{await result(bridge.installUpdate());}catch(error){toast(error.message);action.textContent='Restart and install';action.disabled=false;}},'pill primary');body.append(action);}body.append(button('Open download page',()=>bridge.openUpdate(update.url)));}}catch(error){toast(error.message);}finally{check.disabled=false;}});body.append(check);
}
function renderBackup(page){
 const field=(label)=>{const input=node('input');input.type='password';input.autocomplete='new-password';input.setAttribute('aria-label',label);input.placeholder=label;return input;};
 const out=append(node('section','settings-card'),node('h2','','Encrypted backup'),node('p','muted','Saves your Bots, conversations and routines to one file encrypted with your password. AI sign-ins, API keys and vault secrets are not included. Without the password the backup cannot be opened.'));
 const pass=field('Backup password (8+ characters)'),again=field('Repeat password');
 const save=button('Export backup…',async()=>{if(pass.value.length<8){toast('Use a password of at least 8 characters.');return;}if(pass.value!==again.value){toast('The passwords don’t match.');return;}save.disabled=true;try{if(await result(bridge.exportBackup(pass.value)))toast('Backup saved.');pass.value=again.value='';}catch(error){toast(error.message);}finally{save.disabled=false;}});
 append(out,pass,again,save);
 const restore=append(node('section','settings-card'),node('h2','','Restore'),node('p','muted','Replaces the Bots and conversations on this PC with the backup. Your current workspace is kept in a safety copy first.'));
 const key=field('Backup password');
 const load=button('Restore from backup…',async()=>{load.disabled=true;try{if(await result(bridge.importBackup(key.value))){toast('Backup restored.');key.value='';}}catch(error){toast(error.message);}finally{load.disabled=false;}});
 append(restore,key,load);page.append(out,restore);
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
function showAvatarPicker(bot){
 const content=panel('Bot avatar');let draft=structuredClone(bot.appearance||{shape:'hexagon',color:bot.color}),preview=avatar({...bot,appearance:draft});preview.classList.add('avatar-preview');content.append(preview);const refresh=()=>{const next=avatar({...bot,appearance:draft});next.classList.add('avatar-preview');preview.replaceWith(next);preview=next;};
 const shapes=node('div','avatar-grid');for(const shape of avatarShapes){const choice=append(button('',()=>{draft.shape=shape;delete draft.imageData;refresh();}),avatar({appearance:{shape,color:draft.color}}));choice.setAttribute('aria-label',shape);shapes.append(choice);}content.append(shapes);
 const colors=node('div','colors');for(const[color,hex]of Object.entries(avatarColors)){const swatch=button('',()=>{draft.color=color;delete draft.imageData;refresh();},'color-choice');swatch.style.background=hex;swatch.setAttribute('aria-label',color);colors.append(swatch);}content.append(colors);
 const upload=node('input','field');upload.type='file';upload.accept='image/png,image/jpeg,image/webp,image/heic';upload.setAttribute('aria-label','Upload avatar image');upload.addEventListener('change',async()=>{try{const file=upload.files[0];if(!file)return;if(file.size>12000000)throw new Error('Choose an image under 12 MB.');const image=await createImageBitmap(file);const canvas=document.createElement('canvas'),scale=Math.min(1,192/Math.max(image.width,image.height));canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);image.close();let data;for(const q of [.8,.6,.4,.2]){data=canvas.toDataURL('image/jpeg',q).split(',')[1];if(data.length<=32768)break;}if(data.length>32768)throw new Error('Choose a smaller image.');draft.imageData=data;refresh();}catch(error){toast(error.message);}});
 append(content,upload,button('Generate a look',()=>{draft={shape:avatarShapes[Math.floor(Math.random()*avatarShapes.length)],color:Object.keys(avatarColors)[Math.floor(Math.random()*Object.keys(avatarColors).length)]};refresh();}),button('Reset',async()=>{await organize(bot,{appearance:null,color:bot.isMain?'white':'purple'});dialog.close();}),button('Save avatar',async()=>{await organize(bot,{appearance:draft,color:draft.color});dialog.close();},'pill primary'));
}
async function exportConversation(bot=currentBot()) { if(!bot)return; const text='OpenGrokBot — Local AI conversation\n\n'+entries(bot).map(x=>`${x.kind==='user'?'You':x.senderName||bot.name}: ${x.text}`).join('\n\n'); try { if(await result(bridge.export(text)))toast('Conversation exported.'); }catch(error){toast(error.message);} }
function renderChips(){
 const box=$('#attachment-chips'),bot=currentBot(),files=bot?pendingFiles.get(bot.id)||[]:[];box.replaceChildren();box.hidden=!files.length;
 for(const name of files){const chip=node('span','attachment-chip');chip.append(node('span','',/\.(png|jpe?g|gif|webp)$/i.test(name)?'🖼':'📄'),node('span','chip-name',name.replace(/^[0-9a-f-]{37}/i,'')));const remove=button('×',()=>{pendingFiles.set(bot.id,(pendingFiles.get(bot.id)||[]).filter(x=>x!==name));renderChips();},'chip-remove');remove.setAttribute('aria-label','Remove attachment '+name.replace(/^[0-9a-f-]{37}/i,''));chip.append(remove);box.append(chip);}
}
function addFiles(bot,names){if(!bot||!names?.length)return;const list=[...(pendingFiles.get(bot.id)||[]),...names];if(list.length>10){toast('Attach up to 10 files per message.');return;}pendingFiles.set(bot.id,list);renderChips();}
async function attachFiles(bot=currentBot()){if(!bot)return;if(!window.desktop){toast('Attachments are available in the installed app.');return;}try{addFiles(bot,await result(bridge.attachFiles(bot.id)));}catch(error){toast(error.message);}}
$('#draft').addEventListener('paste',async event=>{
 const bot=currentBot(),items=[...(event.clipboardData?.items||[])].filter(item=>item.kind==='file'&&/^image\/(png|jpeg|gif|webp)$/.test(item.type));
 if(!bot||!items.length||!window.desktop)return;event.preventDefault();
 for(const item of items){const file=item.getAsFile();if(!file)continue;if(file.size>20000000){toast('Images must be under 20 MB.');continue;}
  const bytes=new Uint8Array(await file.arrayBuffer());let binary='';for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));
  try{addFiles(bot,[await result(bridge.attachData(bot.id,item.type,btoa(binary)))]);}catch(error){toast(error.message);}}
});
const voice = createVoice({
  get bridge() { return window.desktop || {}; }, result, toast, currentBot,
  latestReply: bot => { const entry = entries(bot).findLast(x => x.kind === 'bot'); return entry ? { id: entry.id, text: entry.text, finished: entry.state !== 'streaming' && !running.has(bot.id) } : null; },
  sendText: (bot, text) => submitMessage(bot, text, undefined, []),
  openSettings: () => showSettings('Voice')
});
$('#voice-button').addEventListener('click', () => { if (!window.desktop) { toast('Voice mode is available in the installed app.'); return; } if (!setup.installed.length) { showConnection(); return; } voice.start(); });
$('#composer').addEventListener('submit',event=>{event.preventDefault();const bot=currentBot(),text=$('#draft').value.trim();if(!bot||(!text&&!(pendingFiles.get(bot.id)||[]).length)||running.has(bot.id))return;if(!window.desktop||!setup.installed.length){showConnection();return;}submitMessage(bot,text,pendingSends.get(bot.id)?.text===text?pendingSends.get(bot.id).id:undefined);});
$('#draft').addEventListener('input',()=>{ drafts.set(selected,$('#draft').value);persistDrafts(); $('#draft').style.height='auto';$('#draft').style.height=Math.min(180,$('#draft').scrollHeight)+'px'; });
$('#search-button').addEventListener('click',openPalette);
$('#new-button').addEventListener('click',showNewBot); $('#profile-button').addEventListener('click',()=>showSettings()); $('#apps-button').addEventListener('click',showApps); $('#status-button').addEventListener('click',()=>showConnection()); $('#attachment-button').addEventListener('click',()=>{const content=panel('Conversation actions');const bot=currentBot();append(content,button('Attach files…',()=>{dialog.close();attachFiles(bot);}),button('Export conversation…',()=>exportConversation()),node('p','muted','Tip: press Ctrl+V in the message box to paste an image.'));});
for(const control of document.querySelectorAll('[data-window]')) control.addEventListener('click',async()=>{if(control.dataset.window==='close'&&bridge.saveDrafts){clearTimeout(draftTimer);try{await result(bridge.saveDrafts(Object.fromEntries(drafts)));}catch(error){toast(error.message);return;}}window.desktop?.windowAction(control.dataset.window);});
window.addEventListener('blur',()=>{focusGeneration++;for(const secret of document.querySelectorAll('.revealed-secret')){secret.textContent='';secret.hidden=true;}for(const field of document.querySelectorAll('input[type=password]'))field.value='';});
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey))return;if(event.key==='n'){event.preventDefault();showNewBot();}else if(event.key===','){event.preventDefault();showSettings();}else if(event.key==='f'){event.preventDefault();$('#search-button').click();}else if(event.key==='Enter'&&!dialog.open){event.preventDefault();$('#composer').requestSubmit();}});
bridge.onChange?.(value=>{workspace=value.workspace;running=new Set(value.running);render();});
bridge.onOpenBot?.(id=>{if(workspace.bots.some(bot=>bot.id===id))selectBot(id);});
function showCloudStatus(value){
 const old=cloudStatus?.phase;cloudStatus=value;let badge=$('#phone-state');if(!badge){badge=button('',()=>showSettings('Computer'),'phone-state');badge.id='phone-state';$('#status-button').before(badge);}badge.textContent=value.phase==='approval-required'?'Approve your iPhone':value.enabled?value.phase==='offline'?'Phone connection offline · retrying':value.phase==='connecting'?'Connecting your iPhone…':'Phone access ready':'Connect your iPhone';badge.title=value.feedback;badge.dataset.state=value.phase;if(value.phase==='approval-required'&&old!==value.phase)toast(value.feedback);
}
bridge.onCloudChange?.(showCloudStatus);
bridge.cloudStatus?.().then(response=>{if(response.ok)showCloudStatus(response.value);}).catch(()=>{});
try { workspace=await result(bridge.load());selected=workspace.bots[0]?.id; setup=await result(bridge.scanCLIs()); }catch(error){toast(error.message);}
render();

if(window.desktop&&!setup.complete)showConnection();

bridge.loadDrafts?.().then(response=>{if(response.ok){for(const[id,text]of Object.entries(response.value||{}))if(!drafts.has(id))drafts.set(id,text);render();}}).catch(()=>{});
if(bridge.checkUpdates&&Date.now()-Number(localStorage.getItem('lastUpdateCheck')||0)>86400000){localStorage.setItem('lastUpdateCheck',String(Date.now()));bridge.checkUpdates().then(response=>{if(response.ok&&response.value.available){toast(`${response.value.version} is available. Open Settings → Updates to download it.`);$('#profile-button').classList.add('update-available');}}).catch(()=>{});}
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey)||event.altKey||dialog.open)return;if(event.key.toLowerCase()==='k'){event.preventDefault();openPalette();}});



if(window.desktop&&bridge.checkUpdates){result(bridge.checkUpdates()).then(update=>{if(update?.available&&!$('.update-button')){const pill=button('↓',()=>showSettings('Updates'),'update-button');pill.setAttribute('aria-label','Update available');pill.title='Update available';$('.sidebar footer .footer-actions').append(pill);}}).catch(()=>{});}

async function showBotVM(bot){
 const content=panel('Shared Linux VM');
 const home=await result(bridge.vmHome()).catch(()=>null),botID=home?.botID||bot.id;
 if(bot.id!==botID)append(content,node('p','muted','Only the main Bot’s VM is shared. Set it up under “'+(home?.name||'the main Bot')+'”.'));
 append(content,node('p','muted','One button installs VirtualBox if needed, downloads Ubuntu 24.04, creates the VM, installs it, checks that commands work and shares it with your other computers. It needs about 25 GB of free disk space and takes a while.'));
 const info=node('p','muted','Loading VM settings…'),note=node('p','muted'),controls=node('div');append(content,info,note,controls);
 let stop=()=>{};const off=bridge.onVMProgress?.(value=>{if(value&&value.text)info.textContent=value.text;});stop=off||stop;
 let timer=null;const draw=async()=>{const state=await result(bridge.vmStatus(botID));
  const label={installing:'Installing',verifying:'Checking',ready:'Ready',failed:'Needs attention'}[state.state]||state.state;
  info.textContent=state.assigned?(state.progress||('VM: '+state.name+' · '+label)):state.installed?'VirtualBox found. Press Set up to create the shared VM.':'VirtualBox is not installed yet. Set up will download and install it.';
  note.textContent=state.hypervisorNote||'';controls.replaceChildren();
  clearTimeout(timer);if(state.assigned&&['installing','verifying'].includes(state.state))timer=setTimeout(()=>draw().catch(()=>{}),5000);
  if(!state.assigned){const setup=button('Set up shared Linux VM',async()=>{setup.disabled=true;try{await result(bridge.vmSetupAll());}catch(error){info.textContent=error.message;}setup.disabled=false;await draw().catch(()=>{});});controls.append(setup);return;}
  controls.append(button('Open VM console',async()=>{try{await result(bridge.vmOpen(botID));await draw();}catch(error){info.textContent=error.message;}}));
  if(state.hasCredentials)controls.append(button('Copy guest login',async()=>{try{const login=await result(bridge.vmCredentials(botID));await navigator.clipboard.writeText('Username: '+login.username+'\nPassword: '+login.password);info.textContent='Guest login copied (user '+login.username+').';}catch(error){info.textContent=error.message;}}));
  if(state.state==='failed')controls.append(button('Retry',async()=>{try{await result(bridge.vmRetry());await draw();}catch(error){info.textContent=error.message;}}));
  const option=(text,checked,disabled,handler)=>{const box=node('input');box.type='checkbox';box.checked=checked;box.disabled=disabled;box.addEventListener('change',async()=>{try{await result(handler(box.checked));await draw();}catch(error){info.textContent=error.message;box.checked=!box.checked;}});controls.append(append(node('label'),box,node('span','',' '+text)));};
  option('Allow Bots to run commands in the VM',!!state.commandsEnabled,!state.hasCredentials,value=>bridge.vmCommands(botID,value));
  option('Let my other computers use this VM',!!state.shared,!state.commandsEnabled,value=>bridge.vmShare(botID,value));
  option('Start the VM when I sign in to Windows (so it is running when a Bot needs it)',!!state.autoStart,false,value=>bridge.vmAutoStart(botID,value));
  option('Sign in to Ubuntu automatically (only affects the next new VM; anyone using this PC can then use the VM)',state.autoLogin!==false,false,value=>bridge.vmAutoLogin(botID,value));
 };try{await draw();}catch(error){info.textContent=error.message;}
 showRemoteVM(bot,content);
}

// Use a Linux VM that another computer on this account is sharing, instead of one on this PC.
async function showRemoteVM(bot,content){
 const box=node('div','remote-vm'),status=node('p','muted','');append(box,node('h3','','Or use a shared VM on another computer'),status);content.append(box);
 if(!bridge.vmRemoteGet){status.textContent='Open the installed desktop app to use a VM on another computer.';return;}
 const draw=async()=>{
  box.replaceChildren(node('h3','','Or use a shared VM on another computer'),status);
  let link=null;try{link=await result(bridge.vmRemoteGet(bot.id));}catch(error){status.textContent=error.message;return;}
  if(link){status.textContent=`Every Bot uses “${link.vmName}” on ${link.hostName}.`;box.append(button('Stop using it',async()=>{try{await result(bridge.vmRemoteSet(bot.id,null));await draw();}catch(error){status.textContent=error.message;}}));return;}
  status.textContent='The VM keeps running on the other computer. Commands travel over your encrypted account connection, and that computer must have turned sharing on for the VM. The first time, approve this PC there if it asks.';
  const pick=button('Choose a computer…',async()=>{pick.disabled=true;status.textContent='Looking for your other computers…';try{const hosts=await result(bridge.vmRemoteHosts());if(!hosts.length){status.textContent='No other computer is signed in to your account with OpenGrokBot open.';pick.disabled=false;return;}status.textContent='Choose a computer:';for(const host of hosts){box.append(button(host.name+(host.online?'':' (offline)'),async()=>{status.textContent='Asking '+host.name+' for its shared VMs…';try{const list=await result(bridge.vmRemoteList(host.id));if(!list.length){status.textContent=host.name+' is not sharing any VM. On that computer, open a Bot’s Linux VM settings, turn on guest commands, then “Let my other computers use this VM”.';return;}status.textContent='Choose a VM on '+host.name+':';for(const vm of list)box.append(button('Use “'+vm.botName+'”',async()=>{try{await result(bridge.vmRemoteSet(bot.id,{hostID:host.id,hostName:host.name,vmBotID:vm.botID,vmName:vm.botName}));await draw();}catch(error){status.textContent=error.message;}}));}catch(error){status.textContent=error.message;}}));}}catch(error){status.textContent=error.message;pick.disabled=false;}});
  box.append(pick);
 };
 await draw();
}

// ---- 0.8.6: palette, message actions, Create Bot, dictation, permissions, voice card ----
const toB64 = bytes => { let binary = ''; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(binary); };

function showShortcuts() {
  const content = panel('Keyboard shortcuts');
  for (const [keys, what] of [['Ctrl+K or Ctrl+F', 'Search Bots and actions'], ['Ctrl+N', 'New Bot'], ['Ctrl+,', 'Settings'], ['Enter', 'Send the message (Shift+Enter for a new line)'], ['Esc', 'Close a panel, the palette or Bot details']])
    content.append(append(node('div', 'setting-row'), node('strong', '', keys), node('span', 'muted', what)));
}

function openPalette() {
  if ($('#palette')) { $('#palette input')?.focus(); return; }
  const back = node('div', 'palette-backdrop'); back.id = 'palette';
  const box = node('div', 'palette-box'); box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true'); box.setAttribute('aria-label', 'Search Bots and actions');
  const field = node('input', 'palette-field'); field.placeholder = 'Search Bots and actions'; field.setAttribute('aria-label', 'Search Bots and actions'); field.autocomplete = 'off';
  const list = node('div', 'palette-list'); list.setAttribute('role', 'listbox');
  const actions = [['New Bot', 'Create a Bot', '＋', () => showNewBot()], ['Settings…', 'Preferences', '⚙', () => showSettings()], ['Permissions…', 'What Bots may do without asking', '♧', () => showSettings('Permissions')], ['Connect apps', 'Add your tools', '⬡', () => showApps()], ['Keyboard shortcuts', 'See every shortcut', '⌨', () => showShortcuts()]];
  let items = [], index = 0;
  const close = () => { back.remove(); $('#draft')?.focus(); };
  const choose = position => { const item = items[position]; if (!item) return; close(); item.run(); };
  const draw = () => {
    list.replaceChildren();
    items.forEach((item, position) => {
      const row = button('', () => choose(position), `palette-row ${position === index ? 'active' : ''}`); row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(position === index));
      append(row, item.bot ? avatar(item.bot) : node('span', 'palette-icon', item.icon), append(node('span', 'details'), node('strong', '', item.title), node('small', '', item.sub)));
      list.append(row);
    });
    if (!items.length) list.append(node('p', 'empty', `Nothing matches “${field.value}”.`));
    list.children[index]?.scrollIntoView?.({ block: 'nearest' });
  };
  const compute = () => {
    const query = field.value.trim().toLowerCase(); items = [];
    for (const bot of recentBots(orderedBots())) {
      const last = entries(bot).at(-1)?.text || '';
      if (query && !`${bot.name} ${bot.purpose} ${last}`.toLowerCase().includes(query)) continue;
      items.push({ title: bot.name, sub: (bot.hidden ? 'Hidden · ' : '') + (last || bot.purpose).replace(/\s+/g, ' ').slice(0, 90), bot, run: () => { if (bot.hidden) organize(bot, { hidden: null }); selectBot(bot.id); } });
      if (items.length >= 8) break;
    }
    for (const [title, sub, icon, run] of actions) if (!query || `${title} ${sub}`.toLowerCase().includes(query)) items.push({ title, sub, icon, run });
    index = Math.min(index, Math.max(items.length - 1, 0)); draw();
  };
  field.addEventListener('input', () => { index = 0; compute(); });
  field.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown') { event.preventDefault(); index = Math.min(index + 1, items.length - 1); draw(); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); index = Math.max(index - 1, 0); draw(); }
    else if (event.key === 'Enter') { event.preventDefault(); event.stopPropagation(); choose(index); }
    else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(); }
  });
  back.addEventListener('mousedown', event => { if (event.target === back) close(); });
  append(box, field, list); back.append(box); document.body.append(back); compute(); field.focus();
}

// Hover actions under each message: react, reply, more.
const reactionChoices = ['👍', '👎', '❤️', '😂', '🎉', '🤔'];
async function reactTo(entry, emoji) {
  try {
    if (bridge.reactEntry) await result(bridge.reactEntry(entry.id, emoji || ''));
    else { const next = structuredClone(workspace); const item = next.entries.find(x => x.id === entry.id); if (!item) return; if (emoji) item.reaction = emoji; else delete item.reaction; if (!await persist(next)) return; }
    render();
  } catch (error) { toast(error.message); }
}
async function deleteMessage(entry) {
  try {
    if (bridge.deleteEntry) await result(bridge.deleteEntry(entry.id));
    else { const next = structuredClone(workspace); next.entries = next.entries.filter(x => x.id !== entry.id); if (!await persist(next)) return; }
    render();
  } catch (error) { toast(error.message); }
}
function replyTo(bot, entry) {
  const quoted = entry.text.split('\n').filter(Boolean).slice(0, 3).map(line => '> ' + line.slice(0, 240)).join('\n');
  const draft = $('#draft'); draft.value = quoted + '\n\n' + draft.value; drafts.set(bot.id, draft.value); persistDrafts();
  draft.focus(); draft.setSelectionRange(draft.value.length, draft.value.length);
}
function messageTools(bot, entry, isLast) {
  const tools = node('div', 'message-tools');
  if (entry.reaction) tools.append(Object.assign(node('span', 'reaction-pill', entry.reaction), { title: 'Reaction' }));
  const bar = node('span', 'tool-bar');
  const react = button('☺', () => {
    const open = tools.querySelector('.reaction-pop'); if (open) { open.remove(); return; }
    const pop = node('span', 'reaction-pop'); pop.setAttribute('role', 'menu');
    for (const emoji of reactionChoices) pop.append(button(entry.reaction === emoji ? `${emoji} ✕` : emoji, () => { pop.remove(); reactTo(entry, entry.reaction === emoji ? '' : emoji); }, 'tool'));
    tools.append(pop);
  }, 'tool'); react.setAttribute('aria-label', 'React to message'); react.title = 'React';
  const reply = button('↩', () => replyTo(bot, entry), 'tool'); reply.setAttribute('aria-label', 'Reply to message'); reply.title = 'Reply';
  const more = button('…', () => showMessageMenu(bot, entry, isLast), 'tool'); more.setAttribute('aria-label', 'More message actions'); more.title = 'More';
  bar.append(react, reply, more); tools.append(bar); return tools;
}
function showMessageMenu(bot, entry, isLast) {
  const content = panel('Message');
  const copy = async text => { try { await navigator.clipboard.writeText(text); toast('Copied.'); } catch { toast('It could not be copied.'); } dialog.close(); };
  append(content, button('Copy text', () => copy(entry.text)), button('Copy as Markdown', () => copy((entry.kind === 'user' ? '**You:** ' : '') + entry.text)));
  if (entry.kind === 'bot' && isLast && !running.has(bot.id)) content.append(button('Retry', async () => { dialog.close(); try { await result(bridge.retry(bot.id)); } catch (error) { toast(error.message); } }));
  if (entry.state !== 'streaming') content.append(button('Delete message', () => {
    const confirm = panel('Delete this message?');
    append(confirm, node('p', '', 'It is removed from this conversation on this computer.'), button('Delete message', async () => { dialog.close(); await deleteMessage(entry); }, 'pill primary'), button('Cancel', () => dialog.close()));
  }));
}

// Bot row menu: pin, section, unread, rename, ID, hide, delete.
function showBotActions(bot) {
  const content = panel(bot.name);
  const done = () => dialog.close();
  const ask = (title, placeholder, initial, action) => {
    const inner = panel(title); const input = node('input', 'field'); input.value = initial; input.placeholder = placeholder; input.maxLength = 80; input.setAttribute('aria-label', title);
    const save = async () => { const value = input.value.trim(); if (!value) return; await action(value); };
    input.addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); save(); } });
    append(inner, input, button('Save', save, 'pill primary')); input.focus(); input.select();
  };
  append(content,
    button(isPinned(bot) ? 'Unpin' : 'Pin', async () => { await organize(bot, { isPinned: !isPinned(bot) }); done(); }),
    button('Move to new section…', () => ask('New section', 'Section name', '', async name => { await organize(bot, { folder: name }); done(); })),
    ...(bot.folder ? [button('Remove from section', async () => { await organize(bot, { folder: '' }); done(); })] : []),
    button(bot.unread ? 'Mark as read' : 'Mark as unread', async () => { await organize(bot, { unread: bot.unread ? null : true }); done(); }),
    button('Rename Bot…', () => ask('Rename Bot', 'Bot name', bot.name, async name => { await organize(bot, { name }); done(); })),
    button('Copy conversation ID', async () => { try { await navigator.clipboard.writeText(bot.id); toast('Conversation ID copied.'); } catch { toast('The ID could not be copied.'); } done(); }),
    ...(bot.isMain ? [] : [button('Hide from sidebar', async () => { await organize(bot, { hidden: true }); done(); })]),
    button('Change avatar', () => showAvatarPicker(bot)),
    button('Export conversation…', () => exportConversation(bot)));
  if (!bot.isMain) content.append(button('Delete Bot…', () => {
    const confirm = panel(`Delete ${bot.name}?`);
    append(confirm, node('p', '', 'This removes this Bot and its local conversations.'), button('Delete Bot', async () => { const next = structuredClone(workspace); next.bots = next.bots.filter(x => x.id !== bot.id); next.entries = next.entries.filter(x => x.botID !== bot.id); if (await persist(next)) { if (selected === bot.id) selected = workspace.bots[0]?.id; render(); dialog.close(); } }, 'pill danger'), button('Cancel', () => dialog.close()));
  }, 'pill danger'));
}

// Create a Bot: live preview, name, 14 shapes, 10 colours; description and templates are optional.
function showNewBot() {
  const content = panel('Create a Bot');
  const colors = ['purple', 'pink', 'red', 'orange', 'amber', 'green', 'teal', 'blue', 'gray', 'black'];
  let shape = 'hexagon', color = 'purple';
  const form = node('form', 'new-bot');
  const preview = node('div', 'new-bot-preview');
  const name = node('input', 'field'); name.placeholder = 'Name your Bot'; name.maxLength = 200; name.required = true; name.setAttribute('aria-label', 'Bot name');
  const shapes = node('div', 'shape-grid'), dots = node('div', 'colors color-grid');
  const purpose = node('textarea', 'field'); purpose.placeholder = 'What should it help with? (optional)'; purpose.rows = 3; purpose.maxLength = 2000; purpose.setAttribute('aria-label', 'Bot description');
  const more = node('details', 'new-bot-more'); append(more, node('summary', '', 'Add a description'), purpose);
  const create = button('Create', () => {}, 'pill primary'); create.type = 'submit'; create.disabled = true;
  const redraw = () => {
    preview.replaceChildren(avatar({ appearance: { shape, color } }));
    shapes.replaceChildren(...avatarShapes.map(option => { const choice = button('', () => { shape = option; redraw(); }, `shape-choice ${shape === option ? 'active' : ''}`); choice.append(avatar({ appearance: { shape: option, color } })); choice.setAttribute('aria-label', `${option} shape`); choice.setAttribute('aria-pressed', String(shape === option)); return choice; }));
    dots.replaceChildren(...colors.map(option => { const dot = button('', () => { color = option; redraw(); }, `color-choice ${color === option ? 'active' : ''}`); dot.style.backgroundColor = avatarColors[option]; dot.setAttribute('aria-label', `${option} color`); dot.setAttribute('aria-pressed', String(color === option)); return dot; }));
  };
  redraw();
  name.addEventListener('input', () => create.disabled = !name.value.trim());
  append(form, preview, name, shapes, dots, more, append(node('div', 'panel-bottom'), button('Cancel', () => dialog.close()), create));
  form.addEventListener('submit', async event => {
    event.preventDefault(); const clean = name.value.trim(); if (!clean) return;
    if (workspace.bots.some(bot => bot.name.toLowerCase() === clean.toLowerCase())) { toast('A Bot with this name already exists.'); return; }
    const next = structuredClone(workspace); const bot = { id: crypto.randomUUID(), name: clean, purpose: purpose.value, color, appearance: { shape, color } }; next.bots.push(bot);
    if (await persist(next)) { selectBot(bot.id); dialog.close(); }
  });
  append(content, form, node('p', 'panel-footnote', 'Creates a separate conversation with your selected AI CLI.')); name.focus();
}

// Dictation: tap the mic, talk, tap again. Windows has no built-in recognizer here, so the recording goes to the speech-to-text provider you chose under Settings → Voice.
let dictating = null;
async function toggleDictation() {
  if (dictating) { await stopDictation(); return; }
  if (!currentBot()) return;
  let voiceSettings;
  try { voiceSettings = await result(bridge.voiceSettings()); } catch (error) { toast(error.message); return; }
  if (!voiceSettings.keys?.[voiceSettings.transcriber]) { toast('Dictation on Windows uses your speech-to-text provider. Add a free Groq key under Settings → Voice first. Nothing is recorded until then.'); return; }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
    const context = new AudioContext(), source = context.createMediaStreamSource(stream), processor = context.createScriptProcessor(4096, 1, 1), chunks = [];
    processor.onaudioprocess = event => chunks.push(new Float32Array(event.inputBuffer.getChannelData(0)));
    source.connect(processor); processor.connect(context.destination);
    dictating = { stream, context, source, processor, chunks, timer: setTimeout(() => stopDictation(), 60000) };
    $('#mic-button').classList.add('recording'); $('#mic-button').setAttribute('aria-label', 'Stop dictation'); toast('Listening… tap the mic again to stop. The audio goes to your speech-to-text provider.');
  } catch { toast('The microphone could not be opened. Allow microphone access for OpenGrokBot in Windows Settings → Privacy → Microphone.'); }
}
async function stopDictation() {
  const session = dictating; if (!session) return; dictating = null; clearTimeout(session.timer);
  $('#mic-button').classList.remove('recording'); $('#mic-button').setAttribute('aria-label', 'Dictate a message');
  session.processor.disconnect(); session.source.disconnect(); session.stream.getTracks().forEach(track => track.stop());
  const rate = session.context.sampleRate; await session.context.close();
  const total = session.chunks.reduce((sum, chunk) => sum + chunk.length, 0); if (total < rate * 0.3) { toast('Nothing was heard.'); return; }
  const samples = new Float32Array(total); let offset = 0; for (const chunk of session.chunks) { samples.set(chunk, offset); offset += chunk.length; }
  toast('Transcribing…');
  try {
    const text = await result(bridge.voiceTranscribe(toB64(encodeWav(samples, rate))));
    if (!text) { toast('Nothing was heard.'); return; }
    const draft = $('#draft'); draft.value = (draft.value.trim() ? draft.value.trimEnd() + ' ' : '') + text; const bot = currentBot(); if (bot) { drafts.set(bot.id, draft.value); persistDrafts(); } draft.focus();
  } catch (error) { toast(error.message); }
}
$('#mic-button')?.addEventListener('click', toggleDictation);

// Settings → Permissions: always-ask rules, plus what always asks.
async function renderPermissions(page) {
  let config;
  try { config = await result(bridge.approvalRules()); } catch (error) { page.append(node('p', 'muted', error.message || 'Rules are available in the installed Windows app.')); return; }
  const save = async () => { try { config = { ...await result(bridge.setApprovalRules({ enabled: config.enabled, rules: config.rules })), tools: config.tools }; } catch (error) { toast(error.message); } draw(); };
  const draw = () => {
    page.replaceChildren(append(node('header', 'panel-head'), node('h1', '', 'Permissions'), button('×', () => dialog.close(), 'close-panel')));
    const toggle = node('input'); toggle.type = 'checkbox'; toggle.checked = config.enabled; toggle.setAttribute('aria-label', 'Use my rules'); toggle.addEventListener('change', () => { config.enabled = toggle.checked; save(); });
    append(page, append(node('label', 'setting-row'), toggle, append(node('span', 'details'), node('strong', '', 'Use my rules'), node('small', 'muted', 'Checked before any approval dialog. Turn off to use only the built-in behaviour.'))));
    page.append(node('p', 'settings-label', 'Always ask'));
    for (const rule of config.rules) page.append(append(node('div', 'setting-row'), append(node('span', 'details'), node('strong', '', config.tools.find(x => x.id === rule.tool)?.title || rule.tool), node('small', 'muted', rule.pattern ? `Only when the page address contains “${rule.pattern}”` : 'On any page')), button('Remove', () => { config.rules = config.rules.filter(x => x.id !== rule.id); save(); })));
    if (!config.rules.length) page.append(node('p', 'muted', 'No rules. Add one to make a Bot ask before every click on a website, even a harmless one.'));
    const tool = node('select', 'field'); for (const item of config.tools) { const option = node('option', '', item.title); option.value = item.id; tool.append(option); } tool.setAttribute('aria-label', 'Action');
    const pattern = node('input', 'field'); pattern.placeholder = 'Only when the page address contains… (optional)'; pattern.maxLength = 120; pattern.setAttribute('aria-label', 'Page address contains');
    page.append(append(node('div', 'rule-add'), tool, pattern, button('Add rule', () => { config.rules = [...config.rules, { kind: 'ask', tool: tool.value, pattern: pattern.value.trim() }]; save(); }, 'pill primary')));
    page.append(node('p', 'settings-label', 'Allow without asking'), node('p', 'muted', 'Nothing on Windows can be allowed without asking yet, because Bots here do not write to calendars, reminders, contacts or notes. This list will appear here when they can.'));
    page.append(node('p', 'settings-label', 'Always asks, and cannot be changed'));
    for (const [title, detail] of [['Clicks that send, buy, post or delete', 'You see what will be clicked and on which page.'], ['Typing and submitting a form', 'You see the field and the text first.'], ['Saved logins and passwords', 'Signing in always asks. Passwords are typed by the app, never shown to the Bot.'], ['Unattended routines', 'A routine that runs while you are away skips anything that needs approval.']])
      page.append(append(node('div', 'setting-row'), append(node('span', 'details'), node('strong', '', title), node('small', 'muted', detail)), node('span', 'muted', '🔒')));
    page.append(node('p', 'muted', 'Codex runs with read-only workspace access. Other CLIs keep their own permissions, and the app adds no approval bypass flags. Composio tools follow your CLI’s MCP permission settings.'));
  };
  draw();
}

// Bot details → Voice chat: this Bot's own voice, speed and language.
const voiceLanguages = [['auto', 'Auto-detect'], ['en-US', 'English (US)'], ['en-GB', 'English (UK)'], ['es-ES', 'Spanish'], ['fr-FR', 'French'], ['de-DE', 'German'], ['it-IT', 'Italian'], ['pt-BR', 'Portuguese (Brazil)'], ['ja-JP', 'Japanese'], ['ko-KR', 'Korean'], ['zh-CN', 'Chinese (Simplified)']];
function voiceCard(bot) {
  const card = node('div', 'voice-card-settings'), own = { ...(bot.voice || {}) };
  const save = async () => { const clean = {}; if (own.speaker) clean.speaker = own.speaker; if (own.speed && own.speed !== 1) clean.speed = Math.min(Math.max(own.speed, 0.75), 1.5); if (own.language && own.language !== '') clean.language = own.language; await organize(bot, { voice: Object.keys(clean).length ? clean : null }); };
  const speaker = node('select', 'field'); speaker.setAttribute('aria-label', 'Voice');
  for (const [value, label] of [['', 'App default'], ['apple', 'Windows voice (free)'], ['groq', 'Groq'], ['openAI', 'OpenAI'], ['elevenLabs', 'ElevenLabs'], ['gemini', 'Google AI Studio (Gemini)'], ['nvidiaCloud', 'NVIDIA Cloud'], ['nvidiaNIM', 'NVIDIA NIM']]) { const option = node('option', '', label); option.value = value; speaker.append(option); }
  speaker.value = own.speaker || ''; speaker.addEventListener('change', () => { own.speaker = speaker.value || undefined; save(); });
  const speed = node('input'); speed.type = 'range'; speed.min = '0.75'; speed.max = '1.5'; speed.step = '0.05'; speed.value = String(own.speed || 1); speed.setAttribute('aria-label', 'Speaking speed');
  const speedLabel = node('span', 'muted', `${Number(speed.value).toFixed(2).replace(/0$/, '')}×`);
  speed.addEventListener('input', () => { speedLabel.textContent = `${Number(speed.value).toFixed(2).replace(/0$/, '')}×`; }); speed.addEventListener('change', () => { own.speed = Number(speed.value); save(); });
  const language = node('select', 'field'); language.setAttribute('aria-label', 'Language');
  for (const [value, label] of [['', 'App default'], ...voiceLanguages]) { const option = node('option', '', label); option.value = value; language.append(option); }
  language.value = own.language || ''; language.addEventListener('change', () => { own.language = language.value || undefined; save(); });
  append(card, append(node('label', 'setting-row'), node('span', '', 'Voice'), speaker), append(node('label', 'setting-row'), node('span', '', 'Speed'), speed, speedLabel), append(node('label', 'setting-row'), node('span', '', 'Language'), language),
    node('p', 'muted', 'Only for this Bot. Anything left on App default follows Settings → Voice. Language sets the Windows voice; cloud voices pick their own.'));
  return card;
}

// Connect Apps: avatar stack, search, category chips, recommended grid and category sections with View all.
async function renderCatalog(content) {
  let status = { configured: false, toolkits: [] };
  try { if (bridge.composioRefresh && window.desktop) await result(bridge.composioRefresh()); status = await result(bridge.composioStatus()); } catch (error) { toast(error.message); }
  const chosen = new Set(), connected = new Set(status.toolkits.filter(x => x.connected || x.noAuth).map(x => x.slug)), enabled = new Set(status.toolkits.filter(x => x.enabled).map(x => x.slug));
  let query = '', category = null;
  const header = node('div', 'apps-head'), stack = node('span', 'avatar-stack');
  for (const slug of [...connected].slice(0, 4)) stack.append(Object.assign(node('i', '', (catalog.find(slug)?.name || slug)[0].toUpperCase()), { title: catalog.find(slug)?.name || slug }));
  if (connected.size) append(header, stack, node('span', 'muted', `${connected.size} connected`));
  const search = node('input', 'search-input'); search.placeholder = 'Search across apps'; search.setAttribute('aria-label', 'Search apps');
  const chips = node('div', 'category-chips'), body = node('div', 'apps-body'), setup = node('div', 'apps-setup');
  const key = node('input', 'field'); key.type = 'password'; key.placeholder = 'Composio project API key'; key.autocomplete = 'off'; key.setAttribute('aria-label', 'Composio project API key');
  const link = button('Connect project', async () => { link.disabled = true; try { const value = key.value; key.value = ''; await result(bridge.composioConnect(value, [...chosen])); await showApps(); } catch (error) { toast(error.message); link.disabled = false; } }, 'pill primary');
  const card = app => {
    const row = node('div', 'app-card'); const action = status.configured
      ? (enabled.has(app.slug) ? (connected.has(app.slug) ? node('span', 'muted', 'Connected ✓') : button('Connect', async () => { try { await result(bridge.composioLink(app.slug)); toast('Finish authorizing in your browser, then reopen Connect apps.'); } catch (error) { toast(error.message); } })) : node('span', 'muted', 'Not in project'))
      : (() => { const toggle = button(chosen.has(app.slug) ? 'Added ✓' : 'Add', () => { if (chosen.has(app.slug)) chosen.delete(app.slug); else chosen.add(app.slug); link.disabled = !chosen.size; draw(); }); toggle.setAttribute('aria-pressed', String(chosen.has(app.slug))); return toggle; })();
    return append(row, node('span', 'app-initial', app.name[0]), append(node('span', 'details'), node('strong', '', app.name), node('small', 'muted', app.category)), action);
  };
  const section = (title, apps, limit, viewAll) => {
    if (!apps.length) return; const wrap = node('section', 'app-section'), head = node('div', 'app-section-head', ''); head.append(node('strong', 'muted', title));
    if (limit && viewAll && apps.length > limit) head.append(button(`View all (${apps.length})`, () => { category = viewAll; draw(); }, 'link-button'));
    append(wrap, head, append(node('div', 'catalog-grid'), ...(limit ? apps.slice(0, limit) : apps).map(card))); body.append(wrap);
  };
  const draw = () => {
    chips.replaceChildren(...[['All', null], ...catalog.categories.map(x => [x, x])].map(([label, value]) => { const chip = button(label, () => { category = value; draw(); }, `chip ${category === value ? 'active' : ''}`); chip.setAttribute('aria-pressed', String(category === value)); return chip; }));
    body.replaceChildren();
    if (query.trim() || category) { const results = catalog.filter(query, category); if (!results.length) body.append(node('p', 'muted', 'No apps match your search.')); else section(category && !query.trim() ? category : 'Results', results); }
    else { section('Recommended for you', catalog.recommended.map(catalog.find).filter(Boolean)); for (const name of catalog.categories) section(name, catalog.filter('', name), 4, name); }
  };
  search.addEventListener('input', () => { query = search.value; draw(); });
  if (!status.configured && window.desktop) append(setup, node('p', 'muted', 'Use your own Composio project to connect apps to your CLI. This is optional. Add the apps you want, paste your project key, then connect.'), key, append(node('div', 'panel-bottom'), button('Get a project key ↗', () => bridge.openDocs('https://platform.composio.dev')), link), node('p', 'muted', 'The project key and tool session are encrypted with Windows device storage. Composio has its own pricing and usage limits.')), link.disabled = true;
  else if (!window.desktop) append(setup, node('p', 'muted', 'Open the installed desktop app to store your project key securely.'));
  else { append(setup, node('p', 'muted', 'Apps are chosen when the project is connected. To change them, remove the project below and connect again.'), button('Remove project from this device', async () => { try { await result(bridge.composioRemove()); await showApps(); } catch (error) { toast(error.message); } }), button('Manage or revoke accounts in Composio ↗', () => bridge.openDocs('https://platform.composio.dev'))); addAllowToggle(setup); }
  append(content, header, search, chips, setup, body); draw();
}

// Accent: Bot colour or neutral.
function applyAccent() { document.documentElement.dataset.accent = localStorage.getItem('accentStyle') === 'neutral' ? 'neutral' : 'bot'; }
applyAccent();

// A Bot's browser stays out of sight. This bar appears while a Bot is using it, with a button to look at it.
function renderBrowserPill() {
  const pill = $('#browser-pill'); if (!pill) return;
  const bot = currentBot(), state = bot && browserActivity.get(bot.id);
  pill.hidden = !state; pill.replaceChildren(); if (!state) return;
  append(pill, node('span', 'browser-dot'), node('span', '', `${bot.name} ${state.working}`),
    button(state.revealed ? 'Hide browser' : 'Show browser', async () => { try { await result(bridge.revealBrowser(bot.id, !state.revealed)); } catch (error) { toast(error.message); } }, 'link-button'));
}
bridge.onBrowserActivity?.(value => { if (value?.working) browserActivity.set(value.botID, value); else browserActivity.delete(value?.botID); renderBrowserPill(); });

// Claude Code cannot ask before using a connected app, so it refuses unless this is on. Only the connected-apps (Composio) tools are allowed.
function addAllowToggle(setup) {
  const allow = node('input'); allow.type = 'checkbox'; allow.setAttribute('aria-label', 'Let Claude Code use connected apps without asking');
  Promise.resolve(bridge.allowConnectedApps?.()).then(value => { if (value?.ok) allow.checked = value.value === true; }).catch(() => {});
  allow.addEventListener('change', async () => { try { await result(bridge.setAllowConnectedApps(allow.checked)); } catch (error) { toast(error.message); allow.checked = !allow.checked; } });
  setup.append(append(node('label', 'setting-row'), allow, append(node('span', 'details'), node('strong', '', 'Let Claude Code use connected apps without asking'),
    node('small', 'muted', 'Claude Code works in the background and cannot ask you before using an app, so it refuses unless this is on. It lets only your connected apps (Composio) run without a question, for example reading Google Drive or sending an email from Gmail. Leave it off if you read pages or files you do not trust. Other AI CLIs follow their own settings.'))));
}

// When a Bot needs the human in the shared VM, a pop-up opens and the Bot waits until the human says they are done.
let handoffTimer = null;
function renderVMHandoff(request) {
  clearInterval(handoffTimer); handoffTimer = null; $('#vm-handoff')?.remove();
  if (!request) return;
  const back = node('div', 'palette-backdrop'); back.id = 'vm-handoff';
  const box = node('div', 'palette-box handoff-box'); box.setAttribute('role', 'dialog'); box.setAttribute('aria-modal', 'true'); box.setAttribute('aria-label', `${request.botName} needs you in the VM`);
  const shot = node('div', 'handoff-shot'), note = node('p', 'muted', '');
  const refresh = async () => { try { const preview = await result(bridge.vmHandoffPreview()); if (preview?.imageData) { const img = node('img'); img.alt = 'The VM screen. Click to click in the VM.'; img.src = 'data:image/jpeg;base64,' + preview.imageData; img.style.cursor = 'crosshair'; img.addEventListener('click', event => { const box = img.getBoundingClientRect(); sendInput({ kind: 'click', fx: (event.clientX - box.left) / box.width, fy: (event.clientY - box.top) / box.height }); }); shot.replaceChildren(img); note.textContent = ''; } } catch (error) { note.textContent = error.message; } };
  const finish = outcome => { clearInterval(handoffTimer); handoffTimer = null; back.remove(); bridge.vmHandoffDone(request.id, outcome); };
  let sending = false;
  const sendInput = async payload => { if (sending) return; sending = true; note.textContent = 'Sending…'; try { await result(bridge.vmHandoffInput(payload)); note.textContent = ''; } catch (error) { note.textContent = error.message; } sending = false; refresh(); };
  const typed = node('input', 'field'); typed.placeholder = 'Type into the VM'; typed.setAttribute('aria-label', 'Type into the VM');
  typed.addEventListener('keydown', event => { if (event.key === 'Enter' && typed.value) { event.preventDefault(); const text = typed.value; typed.value = ''; sendInput({ kind: 'type', text }); } });
  const keys = append(node('div', 'panel-bottom'), button('Type', () => { if (!typed.value) return; const text = typed.value; typed.value = ''; sendInput({ kind: 'type', text }); }), ...[['↩', 'Return'], ['Tab', 'Tab'], ['Esc', 'Escape'], ['⌫', 'BackSpace']].map(([label, name]) => button(label, () => sendInput({ kind: 'key', key: name }))));
  shot.append(node('p', 'muted', 'The VM screen appears here when it can be shown. Use Open VM to work in it.'));
  append(box, node('h2', '', `${request.botName} needs you in the VM`), node('p', 'muted', request.reason), shot, typed, keys, node('p', 'muted', 'Click the picture to click in the VM; type above. Each action takes a moment. Clicking and typing need xdotool and an Xorg desktop session in the VM (Ubuntu: sudo apt install xdotool, and sign in with “Ubuntu on Xorg”).'), note,
    append(node('div', 'panel-bottom'),
      button('Open VM', async () => { try { note.textContent = await result(bridge.vmHandoffOpen()); } catch (error) { note.textContent = error.message; } }),
      button('Cancel task', () => finish('cancelled')),
      button('I’m done — continue', () => finish('done'), 'pill primary')));
  back.append(box); document.body.append(back);
  bridge.vmHandoffOpen().then(response => { if (response?.ok) note.textContent = response.value; else if (response?.error) note.textContent = response.error; }).catch(() => {});
  refresh(); handoffTimer = setInterval(refresh, 2000);
}
bridge.onVMHandoff?.(renderVMHandoff);
