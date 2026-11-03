import { preview } from './seed.js';
import { createVoice } from './voice.js';

const $ = selector => document.querySelector(selector);
const node = (tag, className = '', text = '') => { const value = document.createElement(tag); value.className = className; value.textContent = text; return value; };
const button = (text, action, className = 'pill') => { const value = node('button', className, text); value.type = 'button'; value.addEventListener('click', action); return value; };
const append = (parent, ...children) => { parent.append(...children.filter(Boolean)); return parent; };
const avatarColors={white:'#ffffff',black:'#111111',purple:'#9355ff',pink:'#fa2a99',ochre:'#a46e39',red:'#ff2948',orange:'#ff7012',amber:'#f69a0a',green:'#10bf70',teal:'#15b6a5',blue:'#2385ff',gray:'#969696'};
const avatarShapes=['circle','cloud','square','sparkle','flower','heart','clover','droplet','capsule','triangle','pebble','star','hexagon','fruit'];
function avatar(value='white',starred=false){
 const bot=typeof value==='object'?value:{color:value},appearance=bot.appearance||{color:bot.color,shape:bot.color==='white'||bot.color==='pink'?'circle':bot.color==='ochre'?'hexagon':'pebble'};
 const face=node('span','avatar custom-avatar');face.style.setProperty('--avatar-color',avatarColors[appearance.color]||avatarColors.purple);face.setAttribute('aria-hidden','true');
 if(appearance.imageData){const img=node('img');img.src='data:image/jpeg;base64,'+appearance.imageData;img.alt='';face.append(img);}
 else{
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 100 100');
  const path=document.createElementNS(svg.namespaceURI,'path');let d='';
  if(appearance.shape==='heart')d='M50 94 C10 75 -10 55 4 30 C10 -2 40 1 50 22 C60 1 90 -2 96 30 C110 55 90 75 50 94 Z';
  else if(appearance.shape==='square')d='M22 8 Q12 8 12 18 L12 82 Q12 92 22 92 L78 92 Q88 92 88 82 L88 18 Q88 8 78 8 Z';
  else {for(let i=0;i<120;i++){const a=i/120*2*Math.PI-Math.PI/2;let r=.46;switch(appearance.shape){case'hexagon':r=.42/Math.cos((a+2*Math.PI)%(Math.PI/3)-Math.PI/6);break;case'cloud':r=.42+.055*Math.cos(7*a)+.025*Math.sin(3*a);break;case'flower':r=.41+.07*Math.cos(5*a);break;case'star':r=.37+.105*Math.cos(6*a);break;case'sparkle':r=.37+.11*Math.cos(4*a);break;case'clover':r=.4+.085*Math.cos(4*a+.6);break;case'triangle':r=.37+.105*Math.cos(3*a);break;case'droplet':r=.39+.08*Math.cos(a)+.055*Math.cos(3*a);break;case'pebble':r=.43+.035*Math.cos(3*a)+.025*Math.sin(2*a);break;case'capsule':r=.45;break;}d+=(i?'L':'M')+(50+100*r*Math.cos(a))+','+(50+100*r*Math.sin(a));}d+='Z';}
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
let inspectorOpen=false,inspectorTab="Details",inspectorSignature="",inspectorGeneration=0;
const modelCatalogs=new Map();
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
function selectBot(id) { if (currentBot()) drafts.set(selected, $('#draft').value); selected = id;const bot=currentBot();if(bot)bot.lastUsedAt=new Date().toISOString();bridge.touchBot?.(id).then(response=>{if(!response.ok)toast(response.error);}).catch(()=>{});render(); }
function render() {
  const chatMatches=new Set(search?workspace.entries.filter(x=>x.text.toLowerCase().includes(search.toLowerCase())).map(x=>x.botID):[]);
  const matches=bot=>(`${bot.name} ${bot.purpose}`.toLowerCase().includes(search.toLowerCase())||chatMatches.has(bot.id))&&(folderFilter==='*'||(bot.folder||'')===folderFilter);
  const primary=$('#primary-bot');primary.replaceChildren();
  for(const bot of orderedBots().filter(x=>isPinned(x)&&matches(x))){const tile=append(button('',()=>selectBot(bot.id),`primary-card ${selected===bot.id?'selected':''}`),avatar(bot,true),node('span','',bot.name));tile.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});wireBotDrag(tile,bot);primary.append(tile);}
  const list=$('#bot-list');list.replaceChildren();
  const visible=recentBots(orderedBots().filter(bot=>!isPinned(bot)&&matches(bot)));
  for(const bot of visible){
    const row=button('',()=>selectBot(bot.id),`bot-row ${bot.id===selected?'selected':''}`);row.draggable=true;
    const preview=entries(bot).at(-1)?.text||bot.purpose;
    append(row,avatar(bot),append(node('span','details'),node('strong','',bot.name),node('small','',running.has(bot.id)?'Working…':preview)));
    row.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});
    wireBotDrag(row,bot);list.append(row);
  }
  if(!visible.length&&!primary.children.length)list.append(node('p','empty','No Bots found.'));
  renderFolderFilter();
  const bot = currentBot();
  $('#chat-heading').replaceChildren();
  const draft=$('#draft');if(displayedBot!==selected||document.activeElement!==draft){draft.value=drafts.get(selected)||'';displayedBot=selected;}
  draft.disabled=!bot;if(!bot){$('#messages').replaceChildren(node('div','empty','Create a Bot to start chatting.'));return;}
  append($('#chat-heading'),avatar(bot),node('span','',bot.name));draft.placeholder=`Ask ${bot.name}`;
  document.documentElement.style.setProperty('--bot-accent',avatarColors[bot.appearance?.color||bot.color]||'#9355ff');
  renderMessages(bot);
  const activeCLI=setup.installed.find(x=>x.id===setup.selected);$('#status-button').textContent=activeCLI?`${activeCLI.name} · On this device`:'Set up an AI CLI';

  renderInspector();
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
 if(chatScroll.bot!==bot.id){chatScroll.bot=bot.id;chatScroll.follow=true;chatScroll.userUntil=0;messages.replaceChildren();messages.dataset.bot=bot.id;}
 for(const el of messages.querySelectorAll('[data-extra]'))el.remove();
 const live=new Set();let index=0;
 for(const entry of entries(bot)){
  live.add(entry.id);let row=messages.querySelector(`[data-entry="${CSS.escape(entry.id)}"]`);
  if(!row){row=node('div',entry.kind==='activity'||entry.delivery==='scheduled'?'activity':`message-row ${entry.kind}`);row.dataset.entry=entry.id;row.append(node('div','message-body'));}
  const body=row.firstElementChild;if(row.entryText!==entry.text||row.dataset.state!==(entry.state||'')){body.replaceChildren();if(entry.senderName)body.append(node('small','muted',`Message from ${entry.senderName}`));if(entry.state==='failed'&&entry.provider)body.append(node('small','muted',entry.provider));body.append(node('div','bubble',entry.text||(entry.state==='streaming'?'Thinking…':'')));if(entry.kind==='user')body.append(node('small','delivery-state',entry.delivery==='scheduled'?'Routine started':'Delivered'));if(entry.state==='failed'){body.append(button('Retry response',async()=>{try{await result(bridge.retry(bot.id));}catch(error){toast(error.message);}}));}row.entryText=entry.text;row.dataset.state=entry.state||'';}
  if(messages.children[index]!==row)messages.insertBefore(row,messages.children[index]||null);index++;
 }
 for(const row of messages.querySelectorAll('[data-entry]'))if(!live.has(row.dataset.entry))row.remove();
 const pending=pendingSends.get(bot.id);
 if(pending&&!live.has(pending.id)){const row=append(node('div','message-row user pending'),append(node('div','message-body'),node('div','bubble',pending.text),node('small','delivery-state',pending.failed?'Failed to send':'Sending…')));row.dataset.extra='true';if(pending.failed)row.firstChild.append(button('Retry sending',()=>submitMessage(bot,pending.text,pending.id)));messages.append(row);}
 if(!entries(bot).length&&!pending){const empty=node('div','empty','What’s on your mind?');empty.dataset.extra='true';messages.append(empty);}
 if(running.has(bot.id)){const stop=button('Stop response',()=>bridge.stop(bot.id));stop.dataset.extra='true';messages.append(stop);}
 $('#save-note').disabled=running.has(bot.id)||!!pending&&!pending.failed;$('#save-note').setAttribute('aria-label',pending&&!pending.failed?'Sending message':'Send message');
 if(chatScroll.follow)scheduleChatBottom();else chatViewport.scrollTop=previousScroll;
}
async function submitMessage(bot,text,id=crypto.randomUUID()){
 if(running.has(bot.id)||pendingSends.get(bot.id)&&!pendingSends.get(bot.id).failed)return;
 if(selected===bot.id)chatScroll.follow=true;
 const pending={id,text,failed:false};pendingSends.set(bot.id,pending);drafts.set(bot.id,text);persistDrafts();renderMessages(bot);
 try{workspace=await result(bridge.send(bot.id,text,id));pendingSends.delete(bot.id);if(drafts.get(bot.id)===text){drafts.delete(bot.id);if(selected===bot.id&&$('#draft').value.trim()===text)$('#draft').value='';}persistDrafts();render();if(selected===bot.id)$('#draft').focus();}
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
 if(inspectorTab==='Details'){
  body.append(button('Set up / open Linux VM',()=>showBotVM(bot)));
  append(body,node('h3','','Local browser'),node('p','muted','A visible browser on this computer, with a separate cookie/login profile for this Bot.'),button('Open local browser',async()=>{try{await result(bridge.openBrowser(bot.id));}catch(error){toast(error.message);}}));
  append(body,node('h3','','Scheduled tasks'),node('p','muted','Ask this Bot to schedule a one-time or recurring task, or run when another Bot messages it. Tasks run while this desktop app is running; missed times catch up once.'));
  for(const task of bot.schedules||[]){const history=node('details'),summary=node('summary','','Run history');history.append(summary);for(const run of task.history||[])history.append(node('p','muted',`${run.date} · ${run.status}`));if(task.history?.length)body.append(history);append(body,node('p','',`${task.name} · ${task.enabled?(task.nextRun||'Incoming Bot message'):'Paused'} · ${task.recurrence} · ${task.timezone}${task.lastRun?' · Last run: '+task.lastRun+' · '+(task.lastResult||'outcome unavailable'):''}`),button('Cancel task',async()=>{await result(bridge.cancelTask(bot.id,task.id));}));}
  if(bot.memberIDs){body.append(node('h3','','Group members'));for(const member of workspace.bots.filter(x=>bot.memberIDs.includes(x.id)))body.append(button(member.name,()=>selectBot(member.id)));body.append(node('p','muted','Each member answers with its own provider and model.'));}
  else{
   append(body,node('h3','','Providers & models'),node('p','muted','Choose available providers and select the one provider and model that answers for this Bot.'));
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
   body.append(node('p','muted','Only the active provider’s selected model responds to this Bot’s messages.'));
  }
  if(!bot.isMain)body.append(node('p','',bot.purpose));
  for(const [title,memory] of [['This Bot’s memory',bot.memory],['Shared memory',workspace.sharedMemory]])if(memory?.length){body.append(node('h3','',title));for(const fact of memory)body.append(node('p','memory-fact',fact));}
  body.append(button(isPinned(bot)?'Unpin Bot':'Pin to top',()=>organize(bot,{isPinned:!isPinned(bot)})));body.append(button('Organize Bot…',()=>showBotActions(bot)));
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
  for (const [name, glyph] of [['General','⚙'],['Computer','▣'],['Permissions','♧'],['Vault','⚿'],['Voice','♫'],['Usage & Billing','▥'],['Updates','⇩']]) nav.append(append(button('', () => showSettings(name), name === tab ? 'active' : ''), node('span','',glyph), node('div','',name)));
  append(page, append(node('header','panel-head'), node('h1','',tab), button('×', () => dialog.close(), 'close-panel')));
  append(layout, nav, page); dialog.append(layout); if (!dialog.open) dialog.showModal();
  if (tab === 'General') {
    const promo = node('div','promo');
    append(promo, append(node('div'), node('h3','','A free app for your AI CLIs'), node('p','','Choose Codex, Claude Code, Grok Build, OpenCode, or Gemini CLI on this computer. Optionally connect tools with Composio.'), button('Set up AI and tools', () => showConnection(), 'pill primary')), append(node('div','brand-tile'), node('span','','⬡'), node('span','','✧'), avatar(), node('span','','𝕏')));
    const profile = node('input'); profile.value = localStorage.getItem('profile') || 'Local workspace'; profile.setAttribute('aria-label','Local display name'); profile.addEventListener('change', () => localStorage.setItem('profile',profile.value));
    const account = append(node('div','settings-card'), append(node('div','setting-row'), node('span','profile-icon',(localStorage.getItem('profile')||'You').slice(0,2).toUpperCase()), append(node('div','profile-text'),profile,node('small','','Uses your CLI account')),button('Connection status', () => showConnection())));
    const appearance = node('div','settings-card'); const select = node('select'); select.setAttribute('aria-label','Theme');
    for (const [value,label] of [['system','Follow System'],['dark','Dark'],['light','Light']]) { const option=node('option','',label); option.value=value; select.append(option); } select.value=localStorage.getItem('appearance') || 'dark'; select.addEventListener('change',()=>applyTheme(select.value));
    append(appearance, append(node('div','setting-row'),node('label','','Theme'),select),append(node('div','setting-row'),node('label','','Accent'),node('span','muted','Bot color')),append(node('div','setting-row'),node('label','','Language'),node('span','muted','English')));
    append(page,promo,node('p','settings-label','Account'),account,node('p','settings-label','Appearance'),appearance,button('Reset conversations…',()=>confirmReset()));
  } else if (tab === 'Computer') { page.append(button('View another computer on this account',async()=>{try{await result(bridge.openMirror());}catch(error){toast(error.message);}})); page.append(unavailable('This computer', 'AI CLIs run on this computer in a private folder for each Bot.')); renderRemoteAccess(page); page.append(node('p','muted','Each Bot has its own visible local browser with separate cookies and login storage. Open it from Bot details. No cloud browser account is required.')); }
  else if (tab === 'Permissions') page.append(unavailable('CLI tool permissions', 'Codex runs with read-only workspace access. Other CLIs retain their own permissions. The app does not add approval bypass flags. Composio tools follow your CLI’s MCP permission settings.'));
  else if (tab === 'Usage & Billing') page.append(unavailable('No usage to report', 'Usage is billed or limited by your AI provider and Composio project. Check those accounts for current usage; the app does not invent a percentage.'));
  else if (tab === 'Updates') renderUpdates(page);
  else if (tab === 'Vault') renderVault(page);
  else if (tab === 'Voice') voice.renderSettings(page);
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
async function renderUpdates(page){
 const body=append(node('section','settings-card'),node('h2','','App updates'),node('p','muted','Download updates from the official project. Installers do not replace your saved workspace.'));page.append(body);
 const check=button('Check for updates',async()=>{check.disabled=true;try{const update=await result(bridge.checkUpdates());body.append(node('p','',update.available?`${update.version} is available${update.prerelease?' (development release)':''}.`:`You’re using ${update.current}. No newer release is published.`));if(update.available)body.append(button('Open download page',()=>bridge.openUpdate(update.url)));}catch(error){toast(error.message);}finally{check.disabled=false;}});body.append(check);
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
function showBotActions(bot){
 const content=panel(bot.name),folder=node('input','field');folder.value=bot.folder||'';folder.maxLength=80;folder.placeholder='Folder · blank for Unfiled';folder.setAttribute('aria-label','Bot folder');
 append(content,button(isPinned(bot)?'Unpin Bot':'Pin to top',async()=>{await organize(bot,{isPinned:!isPinned(bot)});dialog.close();}),folder,button('Save folder',async()=>{await organize(bot,{folder:folder.value.trim()});dialog.close();}),button('Change avatar',()=>showAvatarPicker(bot)),button('Export conversation…',()=>exportConversation(bot)));
 if(!bot.isMain)content.append(button('Delete Bot…',()=>{const confirm=panel(`Delete ${bot.name}?`);append(confirm,node('p','','This removes this Bot and its local conversations.'),button('Delete Bot',async()=>{const next=structuredClone(workspace);next.bots=next.bots.filter(x=>x.id!==bot.id);next.entries=next.entries.filter(x=>x.botID!==bot.id);if(await persist(next)){if(selected===bot.id)selected=workspace.bots[0]?.id;render();dialog.close();}}),button('Cancel',()=>dialog.close()));}));
}
function showAvatarPicker(bot){
 const content=panel('Bot avatar');let draft=structuredClone(bot.appearance||{shape:'hexagon',color:bot.color}),preview=avatar({...bot,appearance:draft});preview.classList.add('avatar-preview');content.append(preview);const refresh=()=>{const next=avatar({...bot,appearance:draft});next.classList.add('avatar-preview');preview.replaceWith(next);preview=next;};
 const shapes=node('div','avatar-grid');for(const shape of avatarShapes){const choice=append(button('',()=>{draft.shape=shape;delete draft.imageData;refresh();}),avatar({appearance:{shape,color:draft.color}}));choice.setAttribute('aria-label',shape);shapes.append(choice);}content.append(shapes);
 const colors=node('div','colors');for(const[color,hex]of Object.entries(avatarColors)){const swatch=button('',()=>{draft.color=color;delete draft.imageData;refresh();},'color-choice');swatch.style.background=hex;swatch.setAttribute('aria-label',color);colors.append(swatch);}content.append(colors);
 const upload=node('input','field');upload.type='file';upload.accept='image/png,image/jpeg,image/webp,image/heic';upload.setAttribute('aria-label','Upload avatar image');upload.addEventListener('change',async()=>{try{const file=upload.files[0];if(!file)return;if(file.size>12000000)throw new Error('Choose an image under 12 MB.');const image=await createImageBitmap(file);const canvas=document.createElement('canvas'),scale=Math.min(1,192/Math.max(image.width,image.height));canvas.width=Math.max(1,Math.round(image.width*scale));canvas.height=Math.max(1,Math.round(image.height*scale));canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);image.close();let data;for(const q of [.8,.6,.4,.2]){data=canvas.toDataURL('image/jpeg',q).split(',')[1];if(data.length<=32768)break;}if(data.length>32768)throw new Error('Choose a smaller image.');draft.imageData=data;refresh();}catch(error){toast(error.message);}});
 append(content,upload,button('Generate a look',()=>{draft={shape:avatarShapes[Math.floor(Math.random()*avatarShapes.length)],color:Object.keys(avatarColors)[Math.floor(Math.random()*Object.keys(avatarColors).length)]};refresh();}),button('Reset',async()=>{await organize(bot,{appearance:null,color:bot.isMain?'white':'purple'});dialog.close();}),button('Save avatar',async()=>{await organize(bot,{appearance:draft,color:draft.color});dialog.close();},'pill primary'));
}
async function exportConversation(bot=currentBot()) { if(!bot)return; const text='OpenGrokBot — Local AI conversation\n\n'+entries(bot).map(x=>`${x.kind==='user'?'You':x.senderName||bot.name}: ${x.text}`).join('\n\n'); try { if(await result(bridge.export(text)))toast('Conversation exported.'); }catch(error){toast(error.message);} }
const voice = createVoice({
  get bridge() { return window.desktop || {}; }, result, toast, currentBot,
  latestReply: bot => { const entry = entries(bot).findLast(x => x.kind === 'bot'); return entry ? { id: entry.id, text: entry.text, finished: entry.state !== 'streaming' && !running.has(bot.id) } : null; },
  sendText: (bot, text) => submitMessage(bot, text),
  openSettings: () => showSettings('Voice')
});
$('#voice-button').addEventListener('click', () => { if (!window.desktop) { toast('Voice mode is available in the installed app.'); return; } if (!setup.installed.length) { showConnection(); return; } voice.start(); });
$('#composer').addEventListener('submit',event=>{event.preventDefault();const bot=currentBot(),text=$('#draft').value.trim();if(!bot||!text||running.has(bot.id))return;if(!window.desktop||!setup.installed.length){showConnection();return;}submitMessage(bot,text,pendingSends.get(bot.id)?.text===text?pendingSends.get(bot.id).id:undefined);});
$('#draft').addEventListener('input',()=>{ drafts.set(selected,$('#draft').value);persistDrafts(); $('#draft').style.height='auto';$('#draft').style.height=Math.min(180,$('#draft').scrollHeight)+'px'; });
$('#search-button').addEventListener('click',()=>{const slot=$('#search-slot');if(slot.firstChild){slot.replaceChildren();search='';render();return;}const field=node('input','search-input');field.placeholder='Search Bots';field.setAttribute('aria-label','Search Bots');field.addEventListener('input',()=>{search=field.value;render();});slot.append(field);field.focus();});
$('#new-button').addEventListener('click',showNewBot); $('#profile-button').addEventListener('click',()=>showSettings()); $('#apps-button').addEventListener('click',showApps); $('#status-button').addEventListener('click',()=>showConnection()); $('#attachment-button').addEventListener('click',()=>{const content=panel('Conversation actions');append(content,button('Export conversation…',()=>exportConversation()),button('Attachment status',()=>toast('Paste text into your message. File attachments are not supported yet.')));});
for(const control of document.querySelectorAll('[data-window]')) control.addEventListener('click',async()=>{if(control.dataset.window==='close'&&bridge.saveDrafts){clearTimeout(draftTimer);try{await result(bridge.saveDrafts(Object.fromEntries(drafts)));}catch(error){toast(error.message);return;}}window.desktop?.windowAction(control.dataset.window);});
window.addEventListener('blur',()=>{focusGeneration++;for(const secret of document.querySelectorAll('.revealed-secret')){secret.textContent='';secret.hidden=true;}for(const field of document.querySelectorAll('input[type=password]'))field.value='';});
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey))return;if(event.key==='n'){event.preventDefault();showNewBot();}else if(event.key===','){event.preventDefault();showSettings();}else if(event.key==='f'){event.preventDefault();$('#search-button').click();}else if(event.key==='Enter'&&!dialog.open){event.preventDefault();$('#composer').requestSubmit();}});
bridge.onChange?.(value=>{workspace=value.workspace;running=new Set(value.running);render();});
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
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey)||event.altKey||dialog.open)return;if(event.key.toLowerCase()==='k'){event.preventDefault();const content=panel('Switch Bot');const field=node('input','field'),results=node('div','switcher-results');field.placeholder='Find a Bot…';field.setAttribute('aria-label','Find a Bot');const draw=()=>{results.replaceChildren();for(const bot of orderedBots().filter(x=>x.name.toLowerCase().includes(field.value.toLowerCase())))results.append(button(bot.name,()=>{dialog.close();selectBot(bot.id);}));};field.addEventListener('input',draw);append(content,field,results);draw();field.focus();}});


if(bridge.openMirror){const switcher=button('This computer ▾',async()=>{try{await result(bridge.openMirror());}catch(error){toast(error.message);}});switcher.className='folder-filter';switcher.setAttribute('aria-label','Switch to another computer on this account');$('#search-slot').before(switcher);}

async function showBotVM(bot){
 const content=panel(bot.name+' · Linux VM');append(content,node('p','muted','Install VirtualBox 7.2+, then download an Ubuntu 24.04 desktop ISO (x64) or supply a prepared Linux OVA. Setup creates a VM for this Bot: 2 CPU cores, 4 GB RAM and a 32 GB disk for ISO installs. OVA imports keep their disk size.'));
 append(content,button('Download VirtualBox',()=>bridge.openDocs('https://www.virtualbox.org/wiki/Downloads')),button('Download Ubuntu Linux',()=>bridge.openDocs('https://releases.ubuntu.com/24.04/')));
 const info=node('p','muted','Loading VM settings…'),controls=node('div');append(content,info,controls,node('p','muted','The console opens locally in VirtualBox. The AI CLI remains on the host. Optional Bot commands run inside Linux through Guest Additions; no separate guest AI agent is installed. ISO installation takes time inside the console. Copy guest login after setup.'));
 const draw=async()=>{const state=await result(bridge.vmStatus(bot.id));info.textContent=state.assigned?'VM: '+state.name+' · '+state.state:state.installed?'VirtualBox found. Choose a Linux guest image to set up.':'Install VirtualBox, then reopen this panel.';controls.replaceChildren();
  const setup=button(state.assigned?'Open VM console':'Choose image and set up VM…',async()=>{setup.disabled=true;info.textContent=state.assigned?'Opening console…':'Setting up VM. This may take several minutes…';try{await result(state.assigned?bridge.vmOpen(bot.id):bridge.vmSetup(bot.id));await draw();}catch(error){info.textContent=error.message;setup.disabled=false;}});setup.disabled=!state.installed||state.busy;controls.append(setup);
  if(state.hasCredentials){const checkbox=node('input');checkbox.type='checkbox';checkbox.checked=state.commandsEnabled;checkbox.addEventListener('change',async()=>{try{await result(bridge.vmCommands(bot.id,checkbox.checked));}catch(error){info.textContent=error.message;}});append(controls,append(node('label'),checkbox,node('span','',' Allow this Bot to run guest commands (requires Guest Additions)')));}
  if(state.hasCredentials)controls.append(button('Copy guest login',async()=>{try{const login=await result(bridge.vmCredentials(bot.id));await navigator.clipboard.writeText('Username: '+login.username+'\nPassword: '+login.password);info.textContent='Guest login copied.';}catch(error){info.textContent=error.message;}}));
 };try{await draw();}catch(error){info.textContent=error.message;}
}
