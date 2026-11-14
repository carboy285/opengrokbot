import { preview } from './seed.js';
import { createVoice } from './voice.js';
import { renderApiKeys } from './api-keys.js';
import { renderSecureLogins } from './secure-logins.js';
import { encodeWav, splitSuggestions, starters } from './voice-core.mjs';
import { renderMarkdown } from './markdown.js';
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
 const face=node('span','avatar custom-avatar');face.style.setProperty('--avatar-color',appearance.color==='white'?'var(--avatar-white,#fff)':avatarColors[appearance.color]||avatarColors.purple);face.setAttribute('aria-hidden','true');
 if(appearance.imageData){const img=node('img');img.src='data:image/jpeg;base64,'+appearance.imageData;img.alt='';face.append(img);}
 else{
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 100 100');
  const path=document.createElementNS(svg.namespaceURI,'path');let d='';
  if(appearance.shape==='heart')d='M50 94 C10 75 -10 55 4 30 C10 -2 40 1 50 22 C60 1 90 -2 96 30 C110 55 90 75 50 94 Z';
  else if(appearance.shape==='square')d='M22 8 Q12 8 12 18 L12 82 Q12 92 22 92 L78 92 Q88 92 88 82 L88 18 Q88 8 78 8 Z';
  else if(shapePaths.has(appearance.shape))d=shapePaths.get(appearance.shape);
  else {for(let i=0;i<120;i++){const a=i/120*2*Math.PI-Math.PI/2;let r=.46;switch(appearance.shape){case'hexagon':r=.42/Math.cos((a+2*Math.PI)%(Math.PI/3)-Math.PI/6);break;case'cloud':r=.42+.055*Math.cos(7*a)+.025*Math.sin(3*a);break;case'flower':r=.41+.07*Math.cos(5*a);break;case'star':r=.37+.105*Math.cos(6*a);break;case'sparkle':r=.37+.11*Math.cos(4*a);break;case'clover':r=.4+.085*Math.cos(4*a+.6);break;case'triangle':r=.37+.105*Math.cos(3*a);break;case'droplet':r=.39+.08*Math.cos(a)+.055*Math.cos(3*a);break;case'pebble':r=.43+.035*Math.cos(3*a)+.025*Math.sin(2*a);break;case'capsule':r=.45;break;}d+=(i?'L':'M')+(50+100*r*Math.cos(a))+','+(50+100*r*Math.sin(a));}d+='Z';shapePaths.set(appearance.shape,d);}
  path.setAttribute('d',d);path.setAttribute('fill','var(--avatar-color)');if(appearance.shape==='square')path.setAttribute('transform','rotate(-20 50 50)');if(appearance.shape==='capsule')path.setAttribute('transform','translate(0 12) scale(1 .76)');svg.append(path);
  for(const [x,y]of [[42,36],[63,32]]){const eye=document.createElementNS(svg.namespaceURI,'rect');for(const[k,v]of Object.entries({x,y,width:9,height:24,rx:4.5,fill:appearance.color==='white'?'var(--avatar-white-ink,#111)':'#fff',transform:'rotate(-25 50 50)'}))eye.setAttribute(k,v);svg.append(eye);}face.append(svg);
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
// ---------- Heads-ups ----------
const headsUpKinds={email:['✉','Inbox'],meeting:['◷','Up next'],conflict:['⚠','Calendar'],brief:['☀','Morning brief'],moved:['↻','Moved'],delivery:['▣','Delivery'],nudge:['↩','Waiting on you']};
const headsUpWorking={email:'Reading your new email',brief:'Putting your brief together'};
let knownHeadsUps=null,proactiveStatus=null,headsUpRefresh=null;
const banner={element:null,botID:null,timer:null};
const clock=iso=>{const date=new Date(iso||Date.now());return Number.isFinite(date.getTime())?date.toLocaleTimeString([],{hour:'numeric',minute:'2-digit'}):'';};
const ago=iso=>{if(!iso)return 'not yet';const minutes=Math.round((Date.now()-Date.parse(iso))/60000);return minutes<1?'just now':minutes===1?'1 min ago':minutes<60?`${minutes} min ago`:clock(iso);};
function headsUpTag(entry){
 const [glyph,label]=headsUpKinds[entry.headsUp.kind]||['✦','Heads-up'];
 const tag=node('div','heads-up-tag');tag.dataset.kind=entry.headsUp.kind;
 append(tag,node('span','heads-up-glyph',glyph),node('span','',label),entry.date&&node('time','',clock(entry.date)));tag.firstChild.setAttribute('aria-hidden','true');
 return tag;
}
// New heads-ups for a chat you're not looking at get a dot on the Bot and a banner that drops in from the top.
function noticeHeadsUps(){
 const arrived=workspace.entries.filter(x=>x.headsUp&&x.kind==='bot'&&x.state==='complete');
 if(!knownHeadsUps){knownHeadsUps=new Set(arrived.map(x=>x.id));return;}
 for(const entry of arrived){
  if(knownHeadsUps.has(entry.id))continue;knownHeadsUps.add(entry.id);
  if(entry.botID===selected&&document.hasFocus())continue;
  if(entry.botID!==selected){const bot=workspace.bots.find(x=>x.id===entry.botID);if(bot&&!bot.unread){bot.unread=true;bridge.organizeBot?.(bot.id,{unread:true}).catch?.(()=>{});}}
  showBanner(entry);
 }
}
// The banner can be flicked away. It tracks the pointer 1:1, resists a downward pull, projects the
// flick's momentum on release and hands the release velocity to a critically damped spring.
const reducedMotion=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;
const rubberband=(distance,dimension,constant=0.55)=>(distance*dimension*constant)/(dimension+constant*Math.abs(distance));
const projectFlick=(velocity,rate=0.998)=>velocity/1000*rate/(1-rate);
function springTo(element,from,target,velocity,done){
 const omega=2*Math.PI/0.35;let x=from,v=velocity,last=performance.now();
 cancelAnimationFrame(element.springFrame);
 const step=now=>{const dt=Math.min(0.032,(now-last)/1000);last=now;const a=-omega*omega*(x-target)-2*omega*v;v+=a*dt;x+=v*dt;
  element.style.transform=`translate(-50%,${x}px)`;element.dragY=x;
  if(Math.abs(x-target)<0.5&&Math.abs(v)<20){element.style.transform=`translate(-50%,${target}px)`;element.dragY=target;done?.();return;}
  element.springFrame=requestAnimationFrame(step);};
 element.springFrame=requestAnimationFrame(step);
}
function wireBannerGesture(element){
 let start=null,history=[];
 element.addEventListener('pointerdown',event=>{
  if(event.button!==0||event.target.closest('.heads-up-close'))return;
  cancelAnimationFrame(element.springFrame);clearTimeout(banner.timer);
  start={y:event.clientY-(element.dragY||0),moved:false,id:event.pointerId};history=[{y:event.clientY,t:event.timeStamp}];
  element.setPointerCapture(event.pointerId);element.classList.add('dragging');
 });
 element.addEventListener('pointermove',event=>{
  if(!start||event.pointerId!==start.id)return;
  const dy=event.clientY-start.y;if(Math.abs(dy)>6)start.moved=true;
  history.push({y:event.clientY,t:event.timeStamp});if(history.length>6)history.shift();
  const y=dy<0?dy:rubberband(dy,element.offsetHeight);
  element.style.transform=`translate(-50%,${y}px)`;element.dragY=y;
 });
 const release=event=>{
  if(!start||event.pointerId!==start.id)return;
  const moved=start.moved;start=null;element.classList.remove('dragging');
  const first=history[0],last=history.at(-1),dt=Math.max(1,last.t-first.t),velocity=(last.y-first.y)/dt*1000;
  if(!moved){element.style.transform='';element.dragY=0;if(event.type==='pointerup'&&!event.target.closest('.heads-up-close')){const id=banner.botID;hideBanner();if(id)selectBot(id);}return;}
  const y=element.dragY||0;
  if(y+projectFlick(velocity)< -40)springTo(element,y,-(element.offsetHeight+90),Math.min(velocity,-400),()=>hideBanner(true));
  else springTo(element,y,0,velocity,()=>{element.style.transform='';banner.timer=setTimeout(hideBanner,5000);});
 };
 element.addEventListener('pointerup',release);element.addEventListener('pointercancel',release);
}
function showBanner(entry){
 const bot=workspace.bots.find(x=>x.id===entry.botID);if(!bot)return;
 if(!banner.element){
  banner.element=node('div','heads-up-banner glass');banner.element.setAttribute('role','status');
  const open=node('div','heads-up-open');open.tabIndex=0;open.setAttribute('role','button');
  open.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();const id=banner.botID;hideBanner();if(id)selectBot(id);}});
  const close=button('×',()=>hideBanner(),'heads-up-close');close.setAttribute('aria-label','Dismiss heads-up');
  banner.element.append(open,close);
  banner.element.addEventListener('pointerenter',()=>clearTimeout(banner.timer));
  banner.element.addEventListener('pointerleave',()=>{if(!banner.element.classList.contains('dragging'))banner.timer=setTimeout(hideBanner,4000);});
  if(!reducedMotion())wireBannerGesture(banner.element);
  $('.conversation').append(banner.element);
 }
 // Several heads-ups at once become one banner: "3 heads-ups", showing the latest.
 const visible=banner.element.classList.contains('visible')&&banner.botID===bot.id;banner.count=visible?(banner.count||1)+1:1;
 const [glyph,label]=headsUpKinds[entry.headsUp.kind]||['✦','Heads-up'];
 const text=entry.text.split('\n').map(x=>x.trim()).find(Boolean)||'';
 const heading=banner.count>1?`${bot.name} · ${banner.count} heads-ups`:`${bot.name} · ${label}`;
 banner.botID=bot.id;
 const mark=node('span','heads-up-glyph',glyph);mark.dataset.kind=entry.headsUp.kind;mark.setAttribute('aria-hidden','true');
 banner.element.firstChild.replaceChildren(avatar(bot),append(node('span','heads-up-copy'),node('strong','',heading),node('span','',text)),mark);
 banner.element.firstChild.setAttribute('aria-label',`Open ${bot.name}: ${text}`);
 cancelAnimationFrame(banner.element.springFrame);banner.element.style.transform='';banner.element.dragY=0;
 banner.element.classList.add('visible');
 clearTimeout(banner.timer);banner.timer=setTimeout(hideBanner,8000);
}
function hideBanner(flicked=false){
 clearTimeout(banner.timer);const element=banner.element;if(!element)return;
 // A flicked banner has already left; drop it without sliding back in first.
 if(flicked){element.classList.add('instant');element.classList.remove('visible');element.style.transform='';element.dragY=0;requestAnimationFrame(()=>element.classList.remove('instant'));}
 else element.classList.remove('visible');
 banner.botID=null;banner.count=0;
}
// ---- Acting on a heads-up ----
// Draft and plan actions fill in the message box so you can read and edit before anything is sent.
function prefill(bot,text){drafts.set(bot.id,text);persistDrafts();if(selected!==bot.id)selectBot(bot.id);const draft=$('#draft');draft.value=text;draft.dispatchEvent(new Event('input'));draft.focus();draft.setSelectionRange(text.length,text.length);}
function toastAction(text,label,action){const box=$('#toast');box.replaceChildren(node('span','',text),button(label,()=>{box.classList.remove('visible');action();},'toast-action'));box.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>box.classList.remove('visible'),6000);}
// A small menu that grows out of the button that opened it.
function popover(anchor,items){
 document.querySelector('.heads-up-menu')?.remove();
 const menu=node('div','heads-up-menu');menu.setAttribute('role','menu');
 for(const [label,action] of items){const item=button(label,()=>{close();action();},'heads-up-menu-item');item.setAttribute('role','menuitem');menu.append(item);}
 const box=anchor.getBoundingClientRect(),host=$('.conversation').getBoundingClientRect();
 menu.style.left=`${box.left-host.left}px`;menu.style.top=`${box.bottom-host.top+6}px`;
 $('.conversation').append(menu);menu.querySelector('button')?.focus();
 const away=event=>{if(!menu.contains(event.target)&&event.target!==anchor)close();},key=event=>{if(event.key==='Escape'){close();anchor.focus();}};
 function close(){menu.remove();document.removeEventListener('pointerdown',away,true);document.removeEventListener('keydown',key,true);}
 document.addEventListener('pointerdown',away,true);document.addEventListener('keydown',key,true);
}
async function headsUpCall(operation,done){try{const value=await result(operation);if(value?.entries){workspace=value;render();}done?.(value);}catch(error){toast(error.message);}}
function headsUpActions(bot,entry){
 const tag=entry.headsUp,row=node('div','heads-up-actions'),senders=(tag.senders||[]).filter(x=>x.name||x.address);
 const reply=sender=>prefill(bot,`Draft a reply to ${sender.name||sender.address}${sender.subject?` about “${sender.subject}”`:''}. Show it to me before sending.`);
 if(tag.link&&['meeting','moved'].includes(tag.kind))row.append(button('Join',()=>headsUpCall(bridge.headsUpJoin(tag.link)),'pill primary'));
 if(senders.length===1)row.append(button('Draft a reply',()=>reply(senders[0]),'pill'));
 else if(senders.length>1){const pick=button('Draft a reply…',()=>popover(pick,senders.map(x=>[`Reply to ${x.name||x.address}`,()=>reply(x)])),'pill');pick.setAttribute('aria-haspopup','menu');row.append(pick);}
 if(tag.kind==='conflict')row.append(button('Help me choose',()=>prefill(bot,`Help me decide what to do about this overlap: ${entry.text.split('\n')[0]}`),'pill'));
 if(tag.kind==='brief')row.append(button('Plan my day',()=>prefill(bot,'Help me plan the rest of today around my calendar.'),'pill'));
 const later=button('Snooze',()=>popover(later,[['For 1 hour',()=>headsUpCall(bridge.headsUpSnooze(entry.id,60))],['For 3 hours',()=>headsUpCall(bridge.headsUpSnooze(entry.id,180))]]),'pill');later.setAttribute('aria-haspopup','menu');row.append(later);
 const mutable=senders.filter(x=>x.address);
 if(mutable.length){const more=button('⋯',()=>popover(more,mutable.map(x=>[`Stop heads-ups from ${x.name||x.address}`,()=>headsUpCall(bridge.headsUpMute(x.address,true),value=>{proactiveStatus=value;toastAction(`You won’t hear about mail from ${x.name||x.address}.`,'Undo',()=>headsUpCall(bridge.headsUpMute(x.address,false),next=>{proactiveStatus=next;}));})])),'pill icon-pill');more.setAttribute('aria-label','More actions');more.setAttribute('aria-haspopup','menu');row.append(more);}
 const done=button('Done',()=>headsUpCall(bridge.headsUpDismiss(entry.id)),'pill quiet-pill');done.title='Collapse this heads-up to one line';row.append(done);
 return row;
}
// ---- Today: a glance at the rest of the day, pinned to the top of the main Bot's chat ----
function relativeStart(iso){const minutes=Math.round((Date.parse(iso)-Date.now())/60000);return minutes<=0?'now':minutes<60?`in ${minutes} min`:`at ${clock(iso)}`;}
function todayCard(bot){
 const today=proactiveStatus?.config?.enabled&&proactiveStatus.today;if(!bot?.isMain||!today)return null;
 const card=node('section','today-card glass');card.setAttribute('aria-label','Today');
 const lead=node('div','today-next');
 if(today.next){append(lead,node('span','today-label','Next'),node('strong','',today.next.title),node('time','today-when',relativeStart(today.next.start)));if(today.next.link)lead.append(button('Join',()=>headsUpCall(bridge.headsUpJoin(today.next.link)),'pill primary today-join'));}
 else append(lead,node('span','today-label','Today'),node('strong','','No more meetings today'));
 const facts=node('div','today-facts');
 if(today.remaining>1)facts.append(node('span','',`${today.remaining} meetings left`));
 if(today.waiting!=null)facts.append(node('span','',today.waiting?`${today.waiting} email${today.waiting===1?'':'s'} waiting on you`:'Inbox clear'));
 if(today.overlaps)facts.append(Object.assign(node('span','today-warn',`${today.overlaps} overlap${today.overlaps===1?'':'s'}`),{title:'Two events overlap'}));
 append(card,lead,facts.children.length&&facts);return card;
}
setInterval(()=>{const when=document.querySelector('.today-when');if(when&&proactiveStatus?.today?.next)when.textContent=relativeStart(proactiveStatus.today.next.start);},30000);
function showHeadsUpBadge(value){
 let badge=$('#headsup-state');
 if(!value?.config?.enabled){badge?.remove();return;}
 if(!badge){badge=button('',()=>showSettings('Heads-ups'),'phone-state');badge.id='headsup-state';$('#status-button').before(badge);}
 const trouble=!value.composio||value.gmail==='error'||value.calendar==='error'||(value.gmail!=='ok'&&value.calendar!=='ok'&&value.lastCheck);
 badge.textContent=trouble?'Heads-ups need attention':'✦ Heads-ups on';badge.dataset.state=trouble?'offline':'ready';
 badge.title=value.error||(value.lastCheck?`Last checked ${ago(value.lastCheck)}`:'Waiting for the first check');
}
// Settings → Web access (0.9.7): use OpenGrokBot from a phone, tablet or another computer's browser.
async function renderWebAccess(page){
 const body=node('div','heads-up-settings web-access');page.append(body);
 if(window.desktop?.webAccess){append(body,node('h2','','Web access'),node('p','muted intro','You’re using OpenGrokBot from another device. Change web access on the computer that runs it.'));return;}
 if(!bridge.webStatus){append(body,node('h2','','Use OpenGrokBot from any device'),node('p','muted intro','Open the installed desktop app to turn on web access.'));return;}
 let status;
 async function draw(){
  try{status=await result(bridge.webStatus());}catch(error){body.replaceChildren(node('p','',error.message));return;}
  body.replaceChildren();
  append(body,node('h2','','Use OpenGrokBot from any device'),node('p','muted intro','Open the address below in a browser on your phone, tablet or another computer and sign in. Bots still run on this PC, so it needs to stay on with OpenGrokBot open (closing the window keeps it running in the tray).'));
  const save=async changes=>{try{status=await result(bridge.webConfigure(changes));draw();}catch(error){toast(error.message);draw();}};
  const user=node('input','field');user.value=status.username;user.placeholder='Username';user.autocomplete='off';user.setAttribute('aria-label','Web access username');
  const pass=node('input','field');pass.type='password';pass.autocomplete='new-password';pass.placeholder=status.configured?'Password saved — type a new one to change it':'Password (10+ characters)';pass.setAttribute('aria-label','Web access password');
  const keep=button(status.configured?'Save changes':'Save sign-in',()=>{const value={username:user.value};if(pass.value)value.password=pass.value;pass.value='';save(value);},'pill');
  const master=node('label','setting-row toggle-row');const check=node('input','switch');check.type='checkbox';check.setAttribute('role','switch');check.setAttribute('aria-label','Web access');check.checked=status.enabled;check.disabled=!status.configured;
  check.addEventListener('change',()=>save({enabled:check.checked}));
  append(master,append(node('span','toggle-text'),node('strong','','Web access'),node('small','muted',status.enabled?'On':status.configured?'Off':'Save a username and password first')),check);
  const where=node('div','web-modes');where.setAttribute('role','radiogroup');where.setAttribute('aria-label','Where it can be reached');
  for(const [value,title,detail] of [['wifi','Wi-Fi','Devices on the same network as this PC.'],['tailscale','Tailscale','Your devices anywhere on your tailnet, over HTTPS. Needs Tailscale on this PC and the other device.']]){
   const option=button('',()=>save({mode:value}),`web-mode ${status.mode===value?'selected':''}`);option.setAttribute('role','radio');option.setAttribute('aria-checked',String(status.mode===value));
   append(option,node('strong','',title),node('small','muted',detail));where.append(option);
  }
  append(body,append(node('div','settings-card'),master,append(node('div','web-signin'),user,pass,keep)),node('p','settings-label','Where'),where);
  if(status.error)body.append(node('p','heads-up-error',status.error));
  if(status.enabled&&status.urls.length){
   const list=node('div','settings-card web-urls');
   for(const url of status.urls)list.append(append(node('div','setting-row'),node('code','',url),button('Copy',async()=>{try{await navigator.clipboard.writeText(url);toast('Address copied.');}catch{toast(url);}},'pill')));
   append(body,node('p','settings-label','Open this address'),list);
  }
  if(status.configured)body.append(button('Sign out all devices',async()=>{try{await result(bridge.webSignOut());toast('Every device was signed out.');}catch(error){toast(error.message);}},'pill'));
  body.append(node('p','muted footnote','Sign-in is checked on this PC; the password is stored only as a hash. Five wrong tries lock that device out for a while. Over the web you can chat, use Bots, heads-ups and approvals. The vault, API keys, app connections and this page stay on this PC.'));
 }
 await draw();
}
async function renderHeadsUps(page){
 const body=node('div','heads-up-settings');page.append(body);
 if(!bridge.proactiveStatus){append(body,node('h2','','Let Grok Bot reach out first'),node('p','muted','Open the installed desktop app to turn on heads-ups. They run in the background on this computer.'));return;}
 const save=async changes=>{try{proactiveStatus=await result(bridge.proactiveConfigure({...proactiveStatus.config,...changes}));showHeadsUpBadge(proactiveStatus);if(currentBot()?.isMain)renderMessages(currentBot());draw();}catch(error){toast(error.message);draw();}};
 const toggle=(label,key,detail,extra)=>{
  const row=node('div','setting-row toggle-row');const check=node('input','switch');check.type='checkbox';check.setAttribute('role','switch');check.checked=!!proactiveStatus.config[key];check.disabled=key!=='enabled'&&!proactiveStatus.config.enabled;check.setAttribute('aria-label',label);
  check.addEventListener('change',()=>save({[key]:check.checked}));
  const text=append(node('span','toggle-text'),node('strong','',label),detail&&node('small','muted',detail));text.addEventListener('click',()=>{if(!check.disabled)check.click();});
  append(row,text,extra,check);return row;
 };
 const time=(key,label)=>{const field=node('input','time-field');field.type='time';field.value=proactiveStatus.config[key];field.setAttribute('aria-label',label);field.disabled=!proactiveStatus.config.enabled;field.addEventListener('change',()=>{if(/^\d\d:\d\d$/.test(field.value))save({[key]:field.value});});return field;};
 const account=(name,state)=>append(node('div','account-row'),node('span','account-dot'),node('span','',name),node('small','muted',state==='ok'?'Connected':state==='error'?'Couldn’t reach it':state==='not-connected'?'Not connected':proactiveStatus.composio?'Checks after you turn heads-ups on':'Not connected'));
 async function draw(){
  try{proactiveStatus=await result(bridge.proactiveStatus());}catch(error){body.replaceChildren(node('p','',error.message));return;}
  const config=proactiveStatus.config;body.replaceChildren();
  append(body,node('h2','','Let Grok Bot reach out first'),node('p','muted intro','Grok Bot watches your Gmail and Google Calendar in the background and messages you when something needs you, so you don’t have to keep checking.'));
  const master=append(node('div','settings-card master-card'),toggle('Heads-ups','enabled',config.enabled?(proactiveStatus.checking?'Checking now…':`On · last checked ${ago(proactiveStatus.lastCheck)}`):'Off'));
  body.append(master);
  if(config.enabled){const status=node('div','account-list');status.append(account('Gmail',proactiveStatus.gmail),account('Google Calendar',proactiveStatus.calendar));status.children[0].dataset.state=proactiveStatus.gmail;status.children[1].dataset.state=proactiveStatus.calendar;master.append(status);
   if(!proactiveStatus.composio||proactiveStatus.gmail==='not-connected'||proactiveStatus.calendar==='not-connected')master.append(append(node('div','setting-row'),node('small','muted','Connect Gmail and Google Calendar through Connect apps. Heads-ups use whichever ones are connected.'),button('Connect apps',()=>showApps(),'pill')));
   if(proactiveStatus.error)master.append(node('p','heads-up-error',proactiveStatus.error));
   master.append(append(node('div','setting-row'),button(proactiveStatus.checking?'Checking…':'Check now',async event=>{event.currentTarget.disabled=true;try{proactiveStatus=await result(bridge.proactiveCheck());showHeadsUpBadge(proactiveStatus);}catch(error){toast(error.message);}draw();},'pill')));}
  const lead=node('select');lead.setAttribute('aria-label','Minutes before a meeting');for(const minutes of [5,10,15,30]){const option=node('option','',`${minutes} min before`);option.value=minutes;lead.append(option);}lead.value=config.leadMinutes;lead.disabled=!config.enabled;lead.addEventListener('change',()=>save({leadMinutes:Number(lead.value)}));
  append(body,node('p','settings-label','Tell me about'),append(node('div','settings-card'),
   toggle('Important new email','email','Mail from real people and anything time-sensitive. Newsletters and promotions stay quiet.'),
   toggle('Upcoming meetings','meetings','A reminder with the join link.',lead),
   toggle('Double-bookings','conflicts','When two events on your calendar overlap.'),
   toggle('Morning brief','brief','Your day at a glance: meetings, gaps and email waiting on you.',time('briefTime','Morning brief time')),
   toggle('Still waiting on you','nudges','Mail from people you haven’t answered in two days.'),
   toggle('Deliveries','deliveries','Packages out for delivery or delivered today.')));
  if(proactiveStatus.muted?.length){const list=node('div','settings-card muted-list');for(const address of proactiveStatus.muted)list.append(append(node('div','setting-row'),node('span','',address),button('Unmute',()=>headsUpCall(bridge.headsUpMute(address,false),value=>{proactiveStatus=value;draw();}),'pill')));append(body,node('p','settings-label','Muted senders'),list);}
  append(body,node('p','settings-label','When'),append(node('div','settings-card'),
   toggle('Quiet hours','quietHours','Heads-ups still land in the chat, without a sound or banner.',append(node('span','time-range'),time('quietStart','Quiet hours start'),node('span','muted','to'),time('quietEnd','Quiet hours end'))),
   toggle('Open at sign-in','openAtLogin','Starts in the tray when you sign in to Windows. Closing the window keeps heads-ups running; quit from the tray icon.')));
  body.append(node('p','muted footnote','New email previews go to your selected AI CLI so it can decide what matters. Heads-up turns can’t use tools, send email or change anything. Ask Grok Bot directly when you want it to act.'));
 }
 headsUpRefresh=()=>{if(body.isConnected&&!body.contains(document.activeElement))draw();else if(!body.isConnected)headsUpRefresh=null;};
 await draw();
}
function currentBot() { return workspace.bots.find(bot => bot.id === selected); }
function entries(bot) { return workspace.entries.filter(entry => entry.botID === bot.id); }
function applyTheme(value) {
  document.documentElement.dataset.theme = value === 'system' ? (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark') : value;
  window.desktop?.setTitleBarTheme?.(document.documentElement.dataset.theme !== 'light').catch?.(() => {});
  localStorage.setItem('appearance', value);
}
applyTheme(localStorage.getItem('appearance') || 'dark');
matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => { if (localStorage.getItem('appearance') === 'system') applyTheme('system'); });
async function persist(next) {
  try { await result(bridge.save(next)); workspace = next; return true; }
  catch (error) { toast(error.message); return false; }
}
function selectBot(id) { if (currentBot()) drafts.set(selected, $('#draft').value); selected = id;window.closeSidebarOnNarrow?.();if(banner.botID===id)hideBanner();document.querySelector('.heads-up-menu')?.remove();const bot=currentBot();if(bot)bot.lastUsedAt=new Date().toISOString();bridge.touchBot?.(id).then(response=>{if(!response.ok)toast(response.error);}).catch(()=>{});if(bot?.unread){bot.unread=false;bridge.organizeBot?.(id,{unread:null}).catch?.(()=>{});}render(); }
function render() {
  const chatMatches=new Set(search?workspace.entries.filter(x=>x.text.toLowerCase().includes(search.toLowerCase())).map(x=>x.botID):[]);
  const matches=bot=>(!bot.hidden||!!search)&&(`${bot.name} ${bot.purpose}`.toLowerCase().includes(search.toLowerCase())||chatMatches.has(bot.id))&&(folderFilter==='*'||(bot.folder||'')===folderFilter);
  const primary=$('#primary-bot');primary.replaceChildren();
  const matching=orderedBots().filter(x=>matches(x));const heroes=[...matching.filter(x=>x.isMain&&isPinned(x)),...matching.filter(x=>!x.isMain&&isPinned(x))];
  for(const bot of heroes){const face=avatar(bot,true),state=waitingOn(bot)?'attention':running.has(bot.id)?'working':'';if(state)face.classList.add(state);const tile=append(button('',()=>selectBot(bot.id),`primary-card ${selected===bot.id?'selected':''}${bot.unread&&bot.id!==selected?' unread':''}`),face,node('span','',bot.name));tile.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});wireBotDrag(tile,bot);primary.append(tile);}
  const lastText=new Map();for(const entry of workspace.entries)lastText.set(entry.botID,entry.label||entry.text);
  const list=$('#bot-list');list.replaceChildren();
  const visible=recentBots(matching.filter(bot=>!isPinned(bot)));
  for(const bot of visible){
    const row=button('',()=>selectBot(bot.id),`bot-row ${bot.id===selected?'selected':''}`);row.draggable=true;
    const preview=(splitSuggestions(splitChoices(lastText.get(bot.id)||bot.purpose||'').text).text.split('\n').find(x=>x.trim())||'').slice(0,90);
    const state=waitingOn(bot)?'attention':running.has(bot.id)?'working':'';const face=avatar(bot);if(state)face.classList.add(state);
    append(row,face,append(node('span','details'),append(node('strong','',bot.name),...(isPinned(bot)?[node('i','pin','⚲')]:[])),node('small',state,state==='attention'?'Needs your OK':state==='working'?'Thinking it through…':preview)),...(bot.unread&&bot.id!==selected?[Object.assign(node('i','unread-dot'),{title:'Unread'})]:[]));
    row.addEventListener('contextmenu',event=>{event.preventDefault();showBotActions(bot);});
    wireBotDrag(row,bot);list.append(row);
  }
  if(!visible.length&&!primary.children.length)list.append(node('p','empty','No Bots found.'));
  renderFolderFilter();
  const bot = currentBot();
  $('#chat-heading').replaceChildren();
  const draft=$('#draft');if(displayedBot!==selected||document.activeElement!==draft){draft.value=drafts.get(selected)||'';displayedBot=selected;}renderChips();
  draft.disabled=!bot;if(!bot){$('#messages').replaceChildren(node('div','empty','Create a Bot to start chatting.'));return;}
  {const state=waitingOn(bot)?'attention':running.has(bot.id)?'working':'',face=avatar(bot);if(state)face.classList.add(state);const title=append(node('span','heading-text'),node('span','heading-name',bot.name));if(state)title.append(node('small',`heading-status ${state}`,state==='attention'?'Needs your OK':'Thinking it through…'));else if(bot.memberIDs)title.append(node('small','heading-status',`${bot.memberIDs.length} Bots`));append($('#chat-heading'),face,title,node('span','heading-chevron','⌄'));}draft.placeholder=`Ask ${bot.name}`;
  const accent=bot.appearance?.color||bot.color;
  document.documentElement.style.setProperty('--bot-accent',accent==='white'?'var(--avatar-white)':avatarColors[accent]||'#9355ff');
  document.documentElement.style.setProperty('--bot-ink',accent==='white'?'var(--avatar-white-ink)':['amber','orange','green','teal','gray'].includes(accent)?'#000':'#fff');
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
 const initial=chatScroll.bot!==bot.id;
 if(chatScroll.bot!==bot.id){chatScroll.bot=bot.id;chatScroll.follow=true;chatScroll.userUntil=0;messages.replaceChildren();messages.dataset.bot=bot.id;messages.rows=new Map();}
 const rows=messages.rows||=new Map();
 for(const el of messages.querySelectorAll('[data-extra]'))el.remove();
 const list=entries(bot),live=new Set();let index=0;const lastEntryID=list.at(-1)?.id;
 const lastUserID=list.findLast(x=>x.kind==='user'&&!['scheduled','proactive'].includes(x.delivery))?.id,lastTalkID=list.findLast(x=>x.kind!=='activity')?.id;
 for(const entry of list){
  live.add(entry.id);let row=rows.get(entry.id);const kind=entryKind(entry);
  if(!row||row.kind!==kind){row?.remove();row=node('div',kind==='activity'?'activity':`message-row ${kind==='botnote'?'bot botnote':entry.kind}${entry.senderBotID&&entry.kind==='bot'?' from-bot':''}`);row.kind=kind;row.dataset.entry=entry.id;row.append(node('div','message-body'));rows.set(entry.id,row);if(entry.headsUp&&entry.kind==='bot'){row.classList.add('heads-up');if(!initial)row.classList.add('arriving');}}
  const canAnswer=entry.id===lastTalkID&&entry.kind==='bot'&&entry.state!=='streaming'&&!running.has(bot.id);
  const key=[entry.text,entry.state||'',entry.id===lastUserID,canAnswer,entry.id===lastEntryID,entry.senderName||'',entry.provider||''].join('\u0001');
  const body=row.firstElementChild;if(row.renderKey!==key){row.renderKey=key;row.toolsKey='';body.replaceChildren();renderEntryBody(bot,entry,body,{isLastUser:entry.id===lastUserID,canAnswer,canSuggest:canAnswer&&entry.id===lastEntryID});if(entry.headsUp&&entry.kind==='bot'&&entry.state==='complete')(body.querySelector(':scope>.stack')||body).append(headsUpActions(bot,entry));row.dataset.state=entry.state||'';}
  if(kind==='message'&&!(entry.state==='streaming'&&!entry.text)){const key=`${entry.reaction||''}|${entry.pinned?1:0}|${entry.state||''}|${running.has(bot.id)}|${entry.id===lastEntryID}`;const stack=body.querySelector(':scope>.stack')||body;if(row.toolsKey!==key||!stack.querySelector(':scope>.message-tools')){stack.querySelector(':scope>.message-tools')?.remove();row.toolsKey=key;const tools=messageTools(bot,entry,entry.id===lastEntryID);const delivered=stack.querySelector(':scope>.delivery-state');if(delivered)tools.append(delivered);stack.append(tools);}}
  if(messages.children[index]!==row)messages.insertBefore(row,messages.children[index]||null);index++;
 }
 for(const [id,row] of rows)if(!live.has(id)){row.remove();rows.delete(id);}
 const today=todayCard(bot);if(today){today.dataset.extra='true';messages.prepend(today);}
 const pending=pendingSends.get(bot.id);
 if(pending&&!live.has(pending.id)){const row=append(node('div','message-row user pending'),append(node('div','message-body'),node('div','bubble',pending.text),node('small','delivery-state',pending.failed?'Failed to send':'Sending…')));row.dataset.extra='true';if(pending.failed)row.firstChild.append(button('Retry sending',()=>submitMessage(bot,pending.text,pending.id)));messages.append(row);}
 if(!entries(bot).length&&!pending){const cards=node('div','starters');for(const idea of starters(bot.name,bot.purpose))cards.append(append(button('',()=>submitMessage(bot,idea,undefined,[]),'starter'),node('span','',idea)));const empty=append(node('div','empty empty-chat'),avatar(bot),node('h2','',bot.name),node('p','',bot.purpose||'What’s on your mind?'),cards);empty.dataset.extra='true';messages.append(empty);}
 const busy=running.has(bot.id),send=$('#save-note');send.classList.toggle('stop',busy);send.textContent=busy?'■':'↑';send.title=busy?'Stop response':'Send';
 send.disabled=!busy&&!!pending&&!pending.failed;send.setAttribute('aria-label',busy?'Stop response':pending&&!pending.failed?'Sending message':'Send message');
 renderApprovalCard();
 if(chatScroll.follow)scheduleChatBottom();else chatViewport.scrollTop=previousScroll;
}
// ---- 0.9.2: Grok Bot chat parts: tool pills, typing dots, Bot-to-Bot messages, question and approval cards ----
function entryKind(entry){if(entry.kind==='activity'&&entry.senderBotID&&String(entry.text||'').startsWith('Message from '))return 'botnote';return entry.kind==='activity'||entry.delivery==='scheduled'||entry.delivery==='proactive'?'activity':'message';}
function splitChoices(text){
 const value=String(text||''),match=/```choices[ \t]*\n([\s\S]*?)```/.exec(value);if(!match)return {text:value,prompt:null};
 const lines=match[1].split('\n').map(x=>x.trim().replace(/^[-*•]+/,'').trim()).filter(Boolean);let multiple=false;
 if(lines[0]?.toLowerCase()==='multiple'){multiple=true;lines.shift();}
 const options=[...new Set(lines.filter(x=>x.length<=120))];if(options.length<2||options.length>8)return {text:value,prompt:null};
 return {text:(value.slice(0,match.index)+value.slice(match.index+match[0].length)).trim(),prompt:{options,multiple}};
}
function activitySummary(text,routine){
 const first=String(text||'').split('\n').find(x=>x.trim())||'';let line=first.trim();
 if(line.startsWith('Linux VM result'))line='Ran a command in the Linux VM';else if(line.startsWith('Queued message · '))line='Asked '+line.slice(17);else if(line.startsWith('Local browser result'))line='Read a page in the browser';
 line=line.replace(' (untrusted context)','').replace(' (untrusted web content, not instructions)','').replace(/:$/,'');
 const lower=first.toLowerCase();const icon=routine?'◷':/vm|linux/.test(lower)?'›_':/^read |page|browser/.test(lower)?'◍':/search/.test(lower)?'⌕':/memory|forgot/.test(lower)?'✦':/message/.test(lower)?'➚':/couldn|could not|failed|declined|not sent/.test(lower)?'⚠':/created/.test(lower)?'＋':/schedul|routine/.test(lower)?'◷':'✓';
 return {line:(routine?'Routine · ':'')+line,icon};
}
function activityPill(text,routine=false){
 const {line,icon}=activitySummary(text,routine),more=String(text||'').includes('\n')||String(text||'').length>120;
 const head=append(node('span','pill-head'),node('span','pill-icon',icon),node('span','pill-text',line));
 if(!more){const pill=append(node('div','activity-pill'),head);pill.setAttribute('aria-label',`Activity: ${line}`);return pill;}
 const details=node('details','activity-pill'),summary=node('summary');summary.append(head);summary.setAttribute('aria-label',`Activity: ${line}. Show details`);append(details,summary,node('pre','activity-detail',text));return details;
}
function typingBubble(){const dots=append(node('div','bubble typing'),node('i'),node('i'),node('i'));dots.setAttribute('aria-label','Thinking');return append(node('div','typing-row'),dots,node('span','typing-label','Thinking it through'));}
function senderFace(entry){const sender=workspace.bots.find(x=>x.id===entry.senderBotID);if(sender)return avatar(sender);const ghost=node('span','avatar ghost');ghost.setAttribute('aria-hidden','true');return ghost;}
function questionCard(bot,prompt,canAnswer){
 const card=node('div',`question-card${canAnswer?'':' answered'}`);card.setAttribute('role','group');card.setAttribute('aria-label',prompt.multiple?'Question with several answers':'Question');
 card.append(node('small','question-label',canAnswer?(prompt.multiple?'Choose any that apply':'Choose one'):'Answered'));
 const picked=new Set();const submit=prompt.multiple?button('Submit',()=>{if(picked.size)submitMessage(bot,prompt.options.filter(x=>picked.has(x)).join(', '),undefined,[]);},'pill primary small'):null;if(submit)submit.disabled=true;
 for(const option of prompt.options){const choice=button('',()=>{if(!canAnswer)return;if(prompt.multiple){picked.has(option)?picked.delete(option):picked.add(option);choice.classList.toggle('picked',picked.has(option));choice.setAttribute('aria-pressed',String(picked.has(option)));submit.disabled=!picked.size;}else submitMessage(bot,option,undefined,[]);},'choice');
  if(prompt.multiple){choice.append(node('span','check'));choice.setAttribute('aria-pressed','false');}choice.append(node('span','choice-text',option));if(!prompt.multiple)choice.append(node('span','choice-arrow','↗'));choice.disabled=!canAnswer;card.append(choice);}
 if(canAnswer)card.append(append(node('div','question-actions'),button('Something else…',()=>$('#draft').focus(),'link'),submit));
 return card;
}
const markdownContext=bot=>({openLink:url=>bridge.openLink?bridge.openLink(url).then(r=>{if(r&&!r.ok)toast(r.error);}).catch(()=>{}):window.open(url,'_blank','noopener'),loadImage:path=>bridge.botImage?result(bridge.botImage(bot.id,path)).catch(()=>null):Promise.resolve(null),loadVideo:path=>bridge.botMedia?result(bridge.botMedia(bot.id,path)).then(value=>value?URL.createObjectURL(new Blob([value.data],{type:value.type})):null).catch(()=>null):Promise.resolve(null)});
function renderEntryBody(bot,entry,body,{isLastUser,canAnswer,canSuggest}){
 const kind=entryKind(entry);
 // Automatic heads-up checks show their short label, never the prompt with email text.
 if(kind==='activity'){body.append(activityPill(entry.delivery==='proactive'?entry.label||'Automatic check':entry.text,entry.delivery==='scheduled'));return;}
 if(kind==='botnote'){
  const [,...rest]=String(entry.text).split('\n'),message=rest.join('\n')||entry.text,from=entry.senderName||'Another Bot';
  const label=append(node('small','sender-line'),node('strong','',from),node('span','arrow','→'),node('span','',bot.name));
  const note=node('div','bubble dashed md-bubble');note.append(renderMarkdown(message,markdownContext(bot)));
  append(body,senderFace(entry),append(node('div','stack'),label,note));body.setAttribute('aria-label',`Message from ${from} to ${bot.name}`);return;
 }
 const fromBot=entry.kind==='bot'&&entry.senderBotID,choice=entry.kind==='bot'?splitChoices(entry.text):{text:entry.text,prompt:null},prompt=choice.prompt;
 // Follow-up chips (0.9.5): the Bot's suggested next requests, shown under the latest reply only.
 const follow=entry.kind==='bot'?splitSuggestions(choice.text):{text:choice.text,suggestions:[]},text=follow.text;
 const stack=node('div','stack');
 if(entry.headsUp&&entry.kind==='bot')stack.append(headsUpTag(entry));
 if(fromBot){body.append(senderFace(entry));stack.append(node('small','sender-line',bot.memberIDs?(entry.senderName||'Bot'):`${entry.senderName||'Another Bot'} replied`));}
 if(!entry.text&&entry.state==='streaming')stack.append(typingBubble());
 else if(text){
  // Bot replies are Markdown (0.9.5): lists, tables, highlighted code, links and the Bot's own images. Your messages stay plain text.
  if(entry.kind==='bot'){const bubble=node('div',`bubble md-bubble${entry.state==='failed'?' failed':''}`);bubble.append(renderMarkdown(text,markdownContext(bot)));stack.append(bubble);}
  else stack.append(node('div',`bubble${entry.state==='failed'?' failed':''}`,text));
 }
 if(prompt)stack.append(questionCard(bot,prompt,canAnswer));
 if(canSuggest&&!prompt&&follow.suggestions.length){const chips=node('div','followups');chips.setAttribute('aria-label','Suggested follow-ups');for(const suggestion of follow.suggestions){const chip=button('',()=>submitMessage(bot,suggestion,undefined,[]),'followup');append(chip,node('span','followup-text',suggestion),node('span','followup-arrow','↗'));chips.append(chip);}stack.append(chips);}
 if(entry.state==='failed')stack.append(node('small','state-note failed',entry.provider?`Couldn’t finish · ${entry.provider}`:'Couldn’t finish'));
 if(entry.state==='stopped')stack.append(node('small','state-note','Stopped'));
 if(entry.kind==='user'&&isLastUser)stack.append(node('small','delivery-state','Delivered'));
 if(entry.state==='failed')stack.append(button('Retry response',async()=>{try{await result(bridge.retry(bot.id));}catch(error){toast(error.message);}},'pill small'));
 body.append(stack);
}
const approvals=new Map();
function renderApprovalCard(){
 const area=$('.composer-area');let card=$('#approval-card');const next=[...approvals.values()][0];
 if(!next){card?.remove();return;}
 if(card?.dataset.id===next.id)return;card?.remove();
 card=node('section','approval-card');card.id='approval-card';card.dataset.id=next.id;card.setAttribute('role','alertdialog');card.setAttribute('aria-label',`Approval needed: ${next.title}`);
 const who=workspace.bots.find(x=>next.title.startsWith(`Let ${x.name} `));
 const head=append(node('div','approval-head'),who?avatar(who):node('span','approval-icon','✋'),node('strong','','Needs your OK'));
 const answer=async approved=>{approvals.delete(next.id);renderApprovalCard();render();try{await result(bridge.answerApproval(next.id,approved));}catch(error){toast(error.message);}};
 const deny=button('Deny',()=>answer(false),'pill'),allow=button('Allow once',()=>answer(true),'pill primary');
 append(card,head,node('h3','',next.title),next.detail?node('pre','approval-detail',next.detail):null,append(node('div','approval-actions'),deny,allow));
 area.prepend(card);
}
$('#save-note').addEventListener('click',event=>{const bot=currentBot();if(bot&&running.has(bot.id)){event.preventDefault();bridge.stop(bot.id);}});
const waitingOn=bot=>[...approvals.values()].some(x=>x.title.startsWith(`Let ${bot.name} `));
bridge.onApproval?.(request=>{if(!request?.id)return;approvals.set(request.id,request);render();});
bridge.pendingApprovals?.().then(response=>{if(response?.ok)for(const request of response.value||[])approvals.set(request.id,request);if(approvals.size)render();}).catch(()=>{});
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
    if(!installed&&provider.local){
     // Ollama and LM Studio: a local server, not a CLI. Show where the app looks and let people change it.
     const address=node('input','field');address.value=provider.id==='ollama'?'http://127.0.0.1:11434':'http://127.0.0.1:1234';address.setAttribute('aria-label',`${provider.name} address`);
     append(card,node('small','muted',`Not running. Open ${provider.name} and start its server${provider.id==='ollama'?'':' (Developer tab)'}, then check again.`),address,
      append(node('div','row-actions'),button('Check again',async()=>{try{setup=await result(bridge.setupServer(provider.id,address.value));inspectorSignature='';renderInspector();toast(setup.installed.some(x=>x.provider===provider.id)?`${provider.name} found.`:`${provider.name} isn’t answering at that address yet.`);}catch(error){toast(error.message);}},'pill small'),button(`Get ${provider.name} ↗`,()=>bridge.openDocs(provider.guide),'pill small')));
    }
    else if(!installed)append(card,node('small','muted','Not installed on this device'),button('Set up',()=>showConnection()));
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
// A panel opened right after another closed must not be wiped by the old panel's late close event.
dialog.addEventListener('close', () => { if (!dialog.open) dialog.replaceChildren(); });
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
      if(status.toolkits.some(x=>['gmail','googlecalendar'].includes(x.slug)&&x.connected)&&bridge.proactiveStatus)body.append(append(node('div','heads-up-nudge'),append(node('div'),node('strong','','Want Grok Bot to keep an eye on these?'),node('p','muted','Turn on heads-ups and it will message you about important email and upcoming meetings.')),button('Set up heads-ups',()=>showSettings('Heads-ups'),'pill primary')));
      append(body,node('p','muted','Selected tools reach your CLI through MCP. Tool actions follow the CLI’s permission settings.'),button('Remove project from this device',async()=>{try{await result(bridge.composioRemove());draw();}catch(error){toast(error.message);}}),button('Manage or revoke accounts in Composio ↗',()=>bridge.openDocs('https://platform.composio.dev')));
    }
  };await draw();
}
async function showApps(){const content=panel('Connect Apps');await renderCatalog(content);}
function unavailable(title, detail) { return append(node('div', 'unavailable'), node('h2', '', title), node('p', '', detail), button('View connection status', () => showConnection())); }
function showSettings(tab = 'General') {
  dialog.replaceChildren();
  const layout = node('div', 'settings-layout'); const nav = node('nav', 'settings-nav'); const page = node('section', 'settings-page');
  for (const [name, glyph] of [['General','⚙'],['Heads-ups','✦'],['Computer','▣'],['Web access','⌂'],['Permissions','♧'],['API Keys','⚷'],['Secure Logins','⚿'],['Vault','⚿'],['Voice','♫'],['Local models','◫'],['Backup','⛁'],['Usage & Billing','▥'],['Updates','⇩']]) {const icon=node('span','',glyph);icon.setAttribute('aria-hidden','true');nav.append(append(button('', () => showSettings(name), name === tab ? 'active' : ''), icon, node('div','',name)));}
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
  else if (tab === 'Local models') renderLocalModels(page);
  else if (tab === 'Usage & Billing') page.append(unavailable('No usage to report', 'Usage is billed or limited by your AI provider and Composio project. Check those accounts for current usage; the app does not invent a percentage.'));
  else if (tab === 'Heads-ups') renderHeadsUps(page);
  else if (tab === 'Web access') renderWebAccess(page);
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
// 0.9.5: export as Markdown, or as a PDF of the rendered chat (lists, tables and code keep their shape).
async function exportConversation(bot=currentBot(),format='md') {
 if(!bot)return;
 const list=entries(bot).filter(x=>x.kind!=='activity'),clean=x=>splitSuggestions(splitChoices(x.text).text).text,when=x=>x.date?new Date(x.date).toLocaleString():'';
 let text;
 if(format==='pdf'){const page=node('div');page.append(node('h1','',bot.name));for(const x of list){page.append(node('div','who',`${x.kind==='user'?'You':x.senderName||bot.name} · ${when(x)}`));const body=x.kind==='user'?node('p','msg',clean(x)):renderMarkdown(clean(x),{});body.classList.add('msg');page.append(body);}text=page.innerHTML;}
 else text=`# ${bot.name}\n\n`+list.map(x=>`**${x.kind==='user'?'You':x.senderName||bot.name}** · ${when(x)}\n\n${clean(x)}`).join('\n\n---\n\n');
 try { if(await result(bridge.export(text,format,`${bot.name} conversation`)))toast(format==='pdf'?'PDF saved.':'Conversation exported.'); }catch(error){toast(error.message);}
}
// Jumps to a message from search or a pin and highlights it for a moment.
function jumpTo(botID,entryID){
 if(selected!==botID)selectBot(botID);
 requestAnimationFrame(()=>requestAnimationFrame(()=>{const row=document.querySelector(`[data-entry="${CSS.escape(entryID)}"]`);if(!row)return;chatScroll.follow=false;row.scrollIntoView({block:'center',behavior:'smooth'});row.classList.add('jump-flash');setTimeout(()=>row.classList.remove('jump-flash'),1800);}));
}
async function pinEntry(entry,on){try{if(bridge.pinEntry)workspace=await result(bridge.pinEntry(entry.id,on));else{const next=structuredClone(workspace);const item=next.entries.find(x=>x.id===entry.id);if(!item)return;if(on)item.pinned=true;else delete item.pinned;if(!await persist(next))return;}render();}catch(error){toast(error.message);}}
async function copyDiagnostics(){try{const text=bridge.diagnostics?await result(bridge.diagnostics()):`OpenGrokBot web preview · ${navigator.userAgent}`;await navigator.clipboard.writeText(text);toast('Diagnostics copied. Paste them into your bug report.');}catch(error){toast(error.message||'Diagnostics could not be copied.');}}
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
  activitySince: (bot, since) => entries(bot).filter(x => x.kind === 'activity' && Date.parse(x.date || 0) >= since - 500).map(x => ({ id: x.id, text: x.text })),
  sendText: (bot, text) => submitMessage(bot, text, undefined, []),
  openSettings: () => showSettings('Voice'),
  avatar: bot => avatar(bot),
  openBot: id => { if (workspace.bots.some(x => x.id === id)) selectBot(id); }
});
$('#voice-button').addEventListener('click', () => { if (!window.desktop) { toast('Voice mode is available in the installed app.'); return; } if (!setup.installed.length) { showConnection(); return; } voice.start(); });
$('#composer').addEventListener('submit',event=>{event.preventDefault();const bot=currentBot(),text=$('#draft').value.trim();if(!bot||(!text&&!(pendingFiles.get(bot.id)||[]).length)||running.has(bot.id))return;if(!window.desktop||!setup.installed.length){showConnection();return;}submitMessage(bot,text,pendingSends.get(bot.id)?.text===text?pendingSends.get(bot.id).id:undefined);});
$('#draft').addEventListener('input',()=>{ drafts.set(selected,$('#draft').value);persistDrafts(); $('#draft').style.height='auto';$('#draft').style.height=Math.min(180,$('#draft').scrollHeight)+'px'; });
$('#search-button').addEventListener('click',openPalette);
$('#new-button').addEventListener('click',showNewBot); $('#profile-button').addEventListener('click',()=>showSettings()); $('#apps-button').addEventListener('click',showApps); $('#status-button').addEventListener('click',()=>showConnection()); $('#attachment-button').addEventListener('click',()=>{const content=panel('Conversation actions');const bot=currentBot();append(content,button('Attach files…',()=>{dialog.close();attachFiles(bot);}),button('Export conversation…',()=>exportConversation()),node('p','muted','Tip: press Ctrl+V in the message box to paste an image.'));});
for(const control of document.querySelectorAll('[data-window]')) control.addEventListener('click',async()=>{if(control.dataset.window==='close'&&bridge.saveDrafts){clearTimeout(draftTimer);try{await result(bridge.saveDrafts(Object.fromEntries(drafts)));}catch(error){toast(error.message);return;}}window.desktop?.windowAction(control.dataset.window);});
window.addEventListener('blur',()=>{focusGeneration++;for(const secret of document.querySelectorAll('.revealed-secret')){secret.textContent='';secret.hidden=true;}for(const field of document.querySelectorAll('input[type=password]'))field.value='';});
document.addEventListener('keydown',event=>{if(!(event.ctrlKey||event.metaKey))return;if(event.key==='n'){event.preventDefault();showNewBot();}else if(event.key===','){event.preventDefault();showSettings();}else if(event.key==='f'){event.preventDefault();$('#search-button').click();}else if(event.key==='Enter'&&!dialog.open){event.preventDefault();$('#composer').requestSubmit();}});
bridge.onChange?.(value=>{workspace=value.workspace;running=new Set(value.running);noticeHeadsUps();render();});
// ---- Narrow screens and web access (0.9.7): the Bot list becomes a panel that slides in from the left ----
if(window.desktop?.webAccess)document.documentElement.classList.add('web');
{
 const workspaceNode=$('#workspace'),sidebar=$('.sidebar'),narrow=matchMedia('(max-width: 760px)');
 const toggle=button('☰',()=>setSidebar(!workspaceNode.classList.contains('show-sidebar')),'sidebar-toggle circle');toggle.setAttribute('aria-label','Show Bots');toggle.setAttribute('aria-expanded','false');
 const scrim=node('div','sidebar-scrim');scrim.addEventListener('click',()=>setSidebar(false));
 $('.conversation').append(toggle);workspaceNode.append(scrim);
 function setSidebar(open){workspaceNode.classList.toggle('show-sidebar',open);toggle.setAttribute('aria-expanded',String(open));sidebar.style.transform='';if(open)sidebar.querySelector('button')?.focus();}
 window.closeSidebarOnNarrow=()=>{if(narrow.matches)setSidebar(false);};
 document.addEventListener('keydown',event=>{if(event.key==='Escape'&&workspaceNode.classList.contains('show-sidebar'))setSidebar(false);});
 // Drag the panel closed: it follows the finger, and the flick's velocity decides whether it closes.
 let drag=null;
 sidebar.addEventListener('pointerdown',event=>{if(!narrow.matches||event.pointerType==='mouse'||!workspaceNode.classList.contains('show-sidebar'))return;drag={x:event.clientX,t:event.timeStamp,last:event.clientX,lastT:event.timeStamp,moved:false};});
 sidebar.addEventListener('pointermove',event=>{if(!drag)return;const dx=event.clientX-drag.x;if(!drag.moved&&Math.abs(dx)<10)return;if(!drag.moved){drag.moved=true;sidebar.setPointerCapture(event.pointerId);sidebar.classList.add('dragging');}drag.v=(event.clientX-drag.last)/Math.max(1,event.timeStamp-drag.lastT)*1000;drag.last=event.clientX;drag.lastT=event.timeStamp;sidebar.style.transform=`translateX(${Math.min(0,dx)}px)`;});
 const end=event=>{if(!drag)return;const moved=drag.moved,dx=event.clientX-drag.x,velocity=drag.v||0;drag=null;sidebar.classList.remove('dragging');if(!moved)return;const projected=dx+velocity/1000*0.998/(1-0.998);setSidebar(!(projected< -sidebar.offsetWidth/3));};
 sidebar.addEventListener('pointerup',end);sidebar.addEventListener('pointercancel',end);
}
bridge.onProactiveChange?.(value=>{proactiveStatus=value;showHeadsUpBadge(value);headsUpRefresh?.();if(currentBot()?.isMain)renderMessages(currentBot());});
bridge.proactiveStatus?.().then(response=>{if(response.ok){proactiveStatus=response.value;showHeadsUpBadge(response.value);if(currentBot()?.isMain)renderMessages(currentBot());}}).catch(()=>{});
bridge.onOpenBot?.(id=>{if(workspace.bots.some(bot=>bot.id===id))selectBot(id);});
function showCloudStatus(value){
 const old=cloudStatus?.phase;cloudStatus=value;let badge=$('#phone-state');if(!badge){badge=button('',()=>showSettings('Computer'),'phone-state');badge.id='phone-state';$('#status-button').before(badge);}badge.textContent=value.phase==='approval-required'?'Approve your iPhone':value.enabled?value.phase==='offline'?'Phone connection offline · retrying':value.phase==='connecting'?'Connecting your iPhone…':'Phone access ready':'Connect your iPhone';badge.title=value.feedback;badge.dataset.state=value.phase;if(value.phase==='approval-required'&&old!==value.phase)toast(value.feedback);
}
bridge.onCloudChange?.(showCloudStatus);
bridge.cloudStatus?.().then(response=>{if(response.ok)showCloudStatus(response.value);}).catch(()=>{});
try { workspace=await result(bridge.load());selected=workspace.bots[0]?.id; setup=await result(bridge.scanCLIs()); }catch(error){toast(error.message);}
noticeHeadsUps();
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
  const option=(text,checked,disabled,handler)=>{const box=node('input');box.type='checkbox';box.checked=checked;box.disabled=disabled;box.addEventListener('change',async()=>{try{await result(handler(box.checked));await draw();}catch(error){info.textContent=error.message;box.checked=!box.checked;}});controls.append(append(node('label','vm-option'),box,node('span','',' '+text)));};
  if(!state.assigned||state.missing){
   if(state.missing)info.textContent='The VM was deleted outside OpenGrokBot. Press Set up again to make a new one.';
   const setup=button(state.missing?'Set up again':'Set up shared Linux VM',async()=>{setup.disabled=true;try{await result(bridge.vmSetupAll());}catch(error){info.textContent=error.message;}setup.disabled=false;await draw().catch(()=>{});});controls.append(setup);
   controls.append(node('p','muted','These apply to the new VM. They make it easy to use, but anyone who can open this Windows account can then use the VM.'));
   option('Sign in to Ubuntu automatically',state.autoLogin!==false,false,value=>bridge.vmOptions({autoLogin:value}));
   option('No screen lock in the VM',state.noLock!==false,false,value=>bridge.vmOptions({noLock:value}));
   option('Let the VM’s bot account use sudo without a password',state.sudo!==false,false,value=>bridge.vmOptions({sudo:value}));
   return;
  }
  controls.append(button('Open VM console',async()=>{try{await result(bridge.vmOpen(botID));await draw();}catch(error){info.textContent=error.message;}}));
  if(state.hasCredentials)controls.append(button('Copy guest login',async()=>{try{const login=await result(bridge.vmCredentials(botID));await navigator.clipboard.writeText('Username: '+login.username+'\nPassword: '+login.password);info.textContent='Guest login copied (user '+login.username+').';}catch(error){info.textContent='Could not copy: '+error.message;}}));
  if(state.canRetry)controls.append(button('Retry',async()=>{try{await result(bridge.vmRetry());await draw();}catch(error){info.textContent=error.message;}}));
  option('Allow Bots to run commands in the VM',!!state.commandsEnabled,!state.hasCredentials,value=>bridge.vmCommands(botID,value));
  option('Let my other computers use this VM',!!state.shared,!state.commandsEnabled,value=>bridge.vmShare(botID,value));
  option('Start the VM when I sign in to Windows (so it is running when a Bot needs it)',!!state.autoStart,false,value=>bridge.vmAutoStart(botID,value));
  const clip=node('select');clip.id='vm-clipboard';for(const [value,label] of [['disabled','Off'],['hosttoguest','Windows to VM'],['guesttohost','VM to Windows'],['bidirectional','Both ways']]){const o=node('option','',label);o.value=value;o.selected=state.clipboard===value;clip.append(o);}
  clip.addEventListener('change',async()=>{clip.disabled=true;info.textContent='Restarting the VM to change copy and paste…';try{await result(bridge.vmClipboard(clip.value));info.textContent='Copy and paste setting saved.';}catch(error){info.textContent=error.message;}clip.disabled=false;await draw().catch(()=>{});});
  controls.append(append(node('label','vm-option'),node('span','','Copy and paste: '),clip));
  if(state.hasCredentials){const field=node('input');field.type='password';field.placeholder='New guest password';field.autocomplete='off';const save=button('Update guest password',async()=>{save.disabled=true;info.textContent='Checking the password in the VM…';try{await result(bridge.vmPassword(field.value));field.value='';info.textContent='Guest password updated and tested.';}catch(error){info.textContent=error.message;}save.disabled=false;await draw().catch(()=>{});});const reset=button('Reset guest password',async()=>{reset.disabled=true;info.textContent='Giving the VM a new password (about a minute)…';try{await result(bridge.vmResetPassword());info.textContent='New guest password set and tested. Copy guest login shows it.';}catch(error){info.textContent=error.message;}reset.disabled=false;await draw().catch(()=>{});});controls.append(append(node('div','vm-password'),field,save,reset));}
  controls.append(button('Delete VM…',async()=>{try{await result(bridge.vmRemove());await draw();}catch(error){info.textContent=error.message;}}));
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
  const field = node('input', 'palette-field'); field.placeholder = 'Search Bots, messages and actions'; field.setAttribute('aria-label', 'Search Bots and actions'); field.autocomplete = 'off';
  const list = node('div', 'palette-list'); list.setAttribute('role', 'listbox');
  const actions = [['Copy diagnostics', 'Versions, providers, voice settings and recent errors, for a bug report', '⚕', () => copyDiagnostics()], ['Export as PDF…', 'Save this chat as a PDF', '⇩', () => exportConversation(currentBot(), 'pdf')], ['New Bot', 'Create a Bot', '＋', () => showNewBot()], ['Settings…', 'Preferences', '⚙', () => showSettings()], ['Permissions…', 'What Bots may do without asking', '♧', () => showSettings('Permissions')], ['Connect apps', 'Add your tools', '⬡', () => showApps()], ['Keyboard shortcuts', 'See every shortcut', '⌨', () => showShortcuts()]];
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
    // 0.9.5: messages that match (newest first), or your pinned messages when nothing is typed. Choosing one jumps to it.
    const found = query.length >= 2 ? workspace.entries.filter(x => x.kind !== 'activity' && x.text.toLowerCase().includes(query)).slice(-12).reverse() : workspace.entries.filter(x => x.pinned).slice(-6).reverse();
    for (const entry of found) {
      const bot = workspace.bots.find(x => x.id === entry.botID); if (!bot) continue;
      const clean = splitSuggestions(splitChoices(entry.text).text).text.replace(/\s+/g, ' '), at = query ? clean.toLowerCase().indexOf(query) : 0;
      const snippet = (at > 30 ? '…' : '') + clean.slice(Math.max(0, at - 30), Math.max(0, at - 30) + 90);
      items.push({ title: snippet, sub: `${entry.kind === 'user' ? 'You' : entry.senderName || bot.name} in ${bot.name}${entry.date ? ' · ' + new Date(entry.date).toLocaleDateString() : ''}${entry.pinned ? ' · pinned' : ''}`, icon: entry.pinned ? '📌' : '⌕', run: () => { if (bot.hidden) organize(bot, { hidden: null }); jumpTo(bot.id, entry.id); } });
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
/** Puts your latest message back in the box and removes it and everything after it, like editing in ChatGPT. */
async function editAndResend(bot, entry) {
  const list = entries(bot), from = list.findIndex(x => x.id === entry.id);
  if (from < 0) return;
  for (const later of list.slice(from).reverse()) await deleteMessage(later);
  const draft = $('#draft'); draft.value = entry.text; drafts.set(bot.id, entry.text); persistDrafts();
  draft.focus(); draft.setSelectionRange(draft.value.length, draft.value.length);
}
function replyTo(bot, entry) {
  const quoted = entry.text.split('\n').filter(Boolean).slice(0, 3).map(line => '> ' + line.slice(0, 240)).join('\n');
  const draft = $('#draft'); draft.value = quoted + '\n\n' + draft.value; drafts.set(bot.id, draft.value); persistDrafts();
  draft.focus(); draft.setSelectionRange(draft.value.length, draft.value.length);
}
function messageTools(bot, entry, isLast) {
  const tools = node('div', 'message-tools');
  if (entry.pinned) tools.append(Object.assign(node('span', 'pin-mark', '📌'), { title: 'Pinned' }));
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
  const copy = button('⧉', async () => { try { await navigator.clipboard.writeText(entry.text); copy.textContent = '✓'; setTimeout(() => { copy.textContent = '⧉'; }, 1200); } catch { toast('It could not be copied.'); } }, 'tool'); copy.setAttribute('aria-label', 'Copy message'); copy.title = 'Copy';
  const tools2 = [];
  // Edit and resend your latest message, or regenerate the latest reply (0.9.5).
  if (entry.kind === 'user' && !running.has(bot.id) && entries(bot).findLast(x => x.kind === 'user')?.id === entry.id) {
    const edit = button('✎', () => editAndResend(bot, entry), 'tool'); edit.setAttribute('aria-label', 'Edit message'); edit.title = 'Edit and resend'; tools2.push(edit);
  }
  if (entry.kind === 'bot' && isLast && !running.has(bot.id)) {
    const again = button('↻', async () => { try { await result(bridge.retry(bot.id)); } catch (error) { toast(error.message); } }, 'tool'); again.setAttribute('aria-label', 'Regenerate reply'); again.title = 'Regenerate'; tools2.push(again);
  }
  bar.append(copy, ...tools2, react, reply, more);
  if (entry.kind === 'bot' && entry.provider) bar.append(Object.assign(node('span', 'provider-tag', entry.provider), { title: `Answered by ${entry.provider}` }));
  tools.append(bar); return tools;
}
function showMessageMenu(bot, entry, isLast) {
  const content = panel('Message');
  const copy = async text => { try { await navigator.clipboard.writeText(text); toast('Copied.'); } catch { toast('It could not be copied.'); } dialog.close(); };
  append(content, button('Copy text', () => copy(entry.text)), button('Copy as Markdown', () => copy((entry.kind === 'user' ? '**You:** ' : '') + entry.text)),
    button(entry.pinned ? 'Unpin' : 'Pin message', () => { dialog.close(); pinEntry(entry, !entry.pinned); }));
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
    button('Export as Markdown…', () => exportConversation(bot, 'md')), button('Export as PDF…', () => exportConversation(bot, 'pdf')));
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
  else { if ((connected.has('gmail') || connected.has('googlecalendar')) && bridge.proactiveStatus) setup.append(append(node('div', 'heads-up-nudge'), append(node('div'), node('strong', '', 'Want Grok Bot to keep an eye on these?'), node('p', 'muted', 'Turn on heads-ups and it will message you about important email and upcoming meetings.')), button('Set up heads-ups', () => showSettings('Heads-ups'), 'pill primary')));
    append(setup, node('p', 'muted', 'Apps are chosen when the project is connected. To change them, remove the project below and connect again.'), button('Remove project from this device', async () => { try { await result(bridge.composioRemove()); await showApps(); } catch (error) { toast(error.message); } }), button('Manage or revoke accounts in Composio ↗', () => bridge.openDocs('https://platform.composio.dev'))); addAllowToggle(setup); }
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

// ---- 0.9.5: Settings → Local models (Ollama manager) ----
async function renderLocalModels(page) {
  const body = node('div', 'local-models'); page.append(body);
  if (!bridge.ollamaModels) { body.append(node('p', 'muted', 'Local models are managed in the installed Windows app.')); return; }
  const draw = async () => {
    let info;
    try { info = await result(bridge.ollamaModels()); } catch (error) { body.replaceChildren(node('p', 'muted', error.message)); return; }
    body.replaceChildren(node('p', 'muted', 'Ollama runs AI models on this PC: private, free and quick. Pick it for any Bot in its side panel. LM Studio works too; manage its models in LM Studio itself.'));
    if (!info.running) {
      append(body, append(node('div', 'settings-card'), node('strong', '', 'Ollama isn’t running'), node('p', 'muted', `Install Ollama, open it, then check again. The app looks at ${info.base}.`),
        append(node('div', 'row-actions'), button('Get Ollama ↗', () => bridge.openDocs('https://ollama.com/download'), 'pill primary small'), button('Check again', draw, 'pill small'))));
      return;
    }
    const sizeOf = bytes => bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.round(bytes / 1e6)} MB`;
    const installedCard = append(node('div', 'settings-card'), node('h3', '', 'On this PC'));
    if (!info.models.length) installedCard.append(node('p', 'muted', 'No models yet. Download one below.'));
    for (const model of info.models) {
      const voice = button(info.voiceModel === model.name ? '★ Voice model' : 'Use for voice', async () => { try { await result(bridge.ollamaVoice(model.name)); draw(); } catch (error) { toast(error.message); } }, 'pill small');
      const remove = button('Remove', async () => { if (!confirm(`Remove ${model.name} from this PC?`)) return; try { await result(bridge.ollamaDelete(model.name)); draw(); } catch (error) { toast(error.message); } }, 'pill small');
      installedCard.append(append(node('div', 'model-row'), append(node('div', 'details'), node('strong', '', model.name), node('small', 'muted', [sizeOf(model.bytes), model.parameters].filter(Boolean).join(' · '))), voice, remove));
    }
    const recommended = append(node('div', 'settings-card'), node('h3', '', 'Recommended'), node('p', 'muted', `This PC has ${info.memoryGB} GB of memory. Models marked ⚡ are quick enough for voice mode.`));
    const have = new Set(info.models.map(m => m.name));
    for (const model of info.recommended) {
      const bar = node('div', 'pull-progress'); bar.hidden = true; const fill = node('i'); bar.append(fill);
      const status = node('small', 'muted', `${model.about} · ${model.sizeGB} GB${model.fits ? '' : ' · may be slow on this PC'}`);
      const action = button(have.has(model.name) ? 'Installed' : 'Download', async () => {
        action.disabled = true; bar.hidden = false;
        const stop = bridge.onOllamaProgress?.(p => { if (p.name !== model.name) return; if (p.total) { fill.style.width = `${Math.round(100 * p.completed / p.total)}%`; status.textContent = `${p.status} · ${sizeOf(p.completed)} of ${sizeOf(p.total)}`; } else status.textContent = p.status; });
        try { await result(bridge.ollamaPull(model.name)); toast(`${model.name} is ready.`); draw(); }
        catch (error) { status.textContent = error.message; action.disabled = false; }
        finally { stop?.(); }
      }, 'pill small');
      if (have.has(model.name)) action.disabled = true;
      recommended.append(append(node('div', 'model-row'), append(node('div', 'details'), node('strong', '', (model.voice ? '⚡ ' : '') + model.name), status, bar), action));
    }
    const custom = node('input', 'field'); custom.placeholder = 'Any model from ollama.com/library, e.g. mistral:7b'; custom.setAttribute('aria-label', 'Model to download');
    const pullCustom = button('Download', async () => { const name = custom.value.trim(); if (!name) return; pullCustom.disabled = true; try { await result(bridge.ollamaPull(name)); toast(`${name} is ready.`); draw(); } catch (error) { toast(error.message); pullCustom.disabled = false; } }, 'pill small');
    append(body, installedCard, recommended, append(node('div', 'settings-card'), node('h3', '', 'Other models'), append(node('div', 'model-entry'), custom, pullCustom)));
  };
  draw();
}

// 0.9.5: native Windows caption buttons replace the drawn ones; Ctrl+Shift+Space anywhere starts or stops voice.
if (window.desktop?.platform === 'win32') document.body.classList.add('native-titlebar');
bridge.onVoiceHotkey?.(() => { if (voice.active) voice.stop(); else if (setup.installed.length) voice.start(); else showConnection(); });
