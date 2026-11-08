const {BrowserWindow,WebContentsView,ipcMain,dialog}=require('electron');
const path=require('node:path');
const {fileURLToPath}=require('node:url');
const attachments=require('./attachments.cjs');
const chromeFile=path.resolve(__dirname,'../renderer/browser.html');
const allowed=value=>{try{const url=new URL(value);return ['https:','http:'].includes(url.protocol)&&!url.username&&!url.password&&value.length<=4000;}catch{return false;}};
const expression='JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText||"").slice(0,16000),links:[...document.links].slice(0,25).map(a=>({text:a.innerText.slice(0,100),url:a.href}))})';
const settleExpression='document.readyState+"|"+(document.body?.innerText||"").length';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
/** Dynamic pages (fantasy draft rooms, dashboards) keep rendering after the load event. Wait until the page stops loading and its text length stops changing. */
async function settle(web,{interval=300,limit=5000}={}){
 let previous=null,stable=0;const end=Date.now()+limit;
 while(Date.now()<end){
  let state;try{state=await web.executeJavaScript(settleExpression);}catch{return;}
  const ready=!web.isLoading()&&String(state).startsWith('complete|');
  stable=ready&&state===previous?stable+1:0;previous=state;
  if(stable>=2)return;
  await pause(interval);
 }
}
/** Captures what the page looks like and stores it where the Bot's CLI can open it. Never throws; the text result is still useful without it. */
async function captureView(web,directory){
 try{
  const image=await web.capturePage();
  if(!image||image.isEmpty())return {error:'The browser window has nothing to capture. Make sure it is not minimized.'};
  const size=image.getSize();
  const jpeg=(size.width>1400?image.resize({width:1400}):image).toJPEG(80);
  return {path:await attachments.savePageScreenshot(directory,jpeg)};
 }catch{return {error:'The screenshot could not be captured.'};}
}
/** A saved login may only be used on its own site or a subdomain of it, never on a look-alike. */
function hostMatches(loginHost,pageHost){const login=String(loginHost||'').toLowerCase(),page=String(pageHost||'').toLowerCase();return !!login&&(page===login||page.endsWith('.'+login));}
/** Shapes what the Bot receives. A failed load becomes a readable result (not a thrown error) so the Bot can try another way. */
function finishPage(address,page,{loadError,note}={}){
 const result=page&&typeof page==='object'?{...page}:{url:address,title:'',text:'',links:[]};
 if(loadError){return {url:address,title:'',text:'',links:[],loadError};}
 if(note)result.loadNote=note;
 return result;
}

// Scripts that run inside the page. Each is a plain function serialized with its arguments, so nothing is spliced into code.
function pageClick({ target, mode }) {
  const visible = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const label = el => String(el.innerText || el.value || el.getAttribute('aria-label') || el.title || '').trim().replace(/\s+/g, ' ');
  const nodes = [...document.querySelectorAll('a, button, input[type=button], input[type=submit], [role=button], [role=link], [role=tab], [role=menuitem], summary, label')].filter(visible);
  const q = target.trim().toLowerCase();
  let match = nodes.find(el => label(el).toLowerCase() === q) || nodes.find(el => label(el).toLowerCase().includes(q));
  if (!match) { try { const bySelector = document.querySelector(target); if (bySelector && visible(bySelector)) match = bySelector; } catch (e) {} }
  if (!match) return { ok: false, error: 'No visible link or button matched that text.', candidates: nodes.slice(0, 20).map(label).filter(Boolean) };
  const form = match.closest('form');
  const submits = !!form && ((match.tagName === 'BUTTON' && (!match.type || match.type === 'submit')) || match.type === 'submit');
  if (mode === 'click') { match.scrollIntoView({ block: 'center' }); match.click(); }
  return { ok: true, label: label(match).slice(0, 100), tag: match.tagName.toLowerCase(), submits };
}
function pageField({ target, mode, value, submit }) {
  const visible = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !el.disabled && !el.readOnly; };
  const fields = [...document.querySelectorAll('input, textarea, [contenteditable=true]')].filter(visible).filter(el => !['hidden', 'checkbox', 'radio', 'button', 'submit', 'file'].includes(el.type));
  const hint = el => ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || '') + ' ' + (el.getAttribute('aria-label') || '') + ' ' + ((el.labels && el.labels[0] && el.labels[0].innerText) || '')).toLowerCase();
  const q = target.trim().toLowerCase();
  const field = q ? fields.find(el => hint(el).includes(q)) : (fields.includes(document.activeElement) ? document.activeElement : fields[0]);
  if (!field) return { ok: false, error: 'No visible text field matched.', candidates: fields.slice(0, 15).map(el => hint(el).trim().slice(0, 60)).filter(Boolean) };
  const type = (field.type || 'text').toLowerCase();
  const isSearch = type === 'search' || /search|query|(^|\s)q(\s|$)/.test(hint(field));
  if (mode === 'type') {
    field.scrollIntoView({ block: 'center' }); field.focus();
    if (field.isContentEditable) field.textContent = value;
    else { const proto = field.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, 'value').set.call(field, value); }
    field.dispatchEvent(new Event('input', { bubbles: true })); field.dispatchEvent(new Event('change', { bubbles: true }));
    if (submit) { const form = field.closest('form'); field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true })); if (form && form.requestSubmit) form.requestSubmit(); }
  }
  return { ok: true, type, hint: hint(field).trim().slice(0, 120), isSearch };
}
function pageScroll({ direction }) {
  const step = Math.max(200, Math.round(window.innerHeight * 0.8));
  if (direction === 'top') window.scrollTo(0, 0); else if (direction === 'bottom') window.scrollTo(0, document.documentElement.scrollHeight);
  else window.scrollBy(0, direction === 'up' ? -step : step);
  return { y: Math.round(window.scrollY) };
}
function pageSearch() {
  return [...document.querySelectorAll('.result')].slice(0, 12).map(el => {
    const link = el.querySelector('a.result__a'); if (!link) return null;
    let url = link.href;
    try { const u = new URL(link.href); const target = u.searchParams.get('uddg'); if (target) url = decodeURIComponent(target); } catch (e) {}
    const snippet = el.querySelector('.result__snippet');
    return { title: link.innerText.trim().slice(0, 140), url, snippet: snippet ? snippet.innerText.trim().slice(0, 240) : '' };
  }).filter(Boolean).slice(0, 8);
}
function pageFill({ username, password }) {
  const visible = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !el.disabled && !el.readOnly; };
  const setValue = (el, value) => { const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; el.focus(); setter.call(el, value); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); };
  const all = [...document.querySelectorAll('input')].filter(visible);
  const pw = all.find(el => el.type === 'password');
  const inputs = pw && pw.form ? all.filter(el => el.form === pw.form) : all;
  const hint = el => ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
  const userField = inputs.find(el => ['text', 'email', 'tel'].includes(el.type) && /user|email|login|account|name/.test(hint(el))) || inputs.find(el => ['text', 'email'].includes(el.type));
  const submit = field => {
    const form = field.closest('form'), scope = form || document;
    const button = scope.querySelector('button[type=submit], input[type=submit]') || [...scope.querySelectorAll('button, [role=button]')].find(b => visible(b) && /sign in|log in|login|continue|next|submit/i.test(b.innerText || b.value || ''));
    if (button) { button.click(); return true; }
    if (form && form.requestSubmit) { form.requestSubmit(); return true; }
    return false;
  };
  if (pw) { if (userField && !userField.value) setValue(userField, username); setValue(pw, password); return submit(pw) ? 'submitted' : 'filled'; }
  if (userField) { setValue(userField, username); return submit(userField) ? 'username-submitted' : 'username-filled'; }
  return 'no-form';
}
const inPage = (fn, args) => `(${fn.toString()})(${JSON.stringify(args)})`;
class LocalBrowsers{
 constructor(getBot,getDirectory){this.getBot=getBot;this.getDirectory=getDirectory;this.entries=new Map();
  for(const name of ['ready','navigate','back','forward','reload','clear'])ipcMain.handle('bot-browser:'+name,async(event,value)=>{
   const entry=[...this.entries.values()].find(entry=>entry.window.webContents===event.sender&&event.senderFrame===event.sender.mainFrame);
   try{if(!entry||fileURLToPath(event.senderFrame.url)!==chromeFile)throw new Error('Unknown browser window.');
    const contents=entry.view.webContents;
    if(name==='ready')this.update(entry);
    if(name==='navigate'){if(!allowed(value))throw new Error('Enter an HTTP or HTTPS address without embedded credentials.');contents.loadURL(value).catch(()=>{});}
    if(name==='back'&&contents.navigationHistory.canGoBack())contents.navigationHistory.goBack();
    if(name==='forward'&&contents.navigationHistory.canGoForward())contents.navigationHistory.goForward();
    if(name==='reload')contents.reload();
    if(name==='clear'){const response=await dialog.showMessageBox(entry.window,{type:'question',message:'Clear this Bot’s browser cookies and login storage?',buttons:['Cancel','Clear browser data'],defaultId:0,cancelId:0});if(response.response===1){await contents.session.clearStorageData();await contents.session.clearCache();contents.reload();}}
    return {ok:true};
   }catch(error){return {ok:false,error:error.message};}
  });
 }
 update(entry){if(entry.window.isDestroyed()||entry.view.webContents.isDestroyed())return;const web=entry.view.webContents;entry.window.webContents.send('bot-browser:state',{url:web.getURL(),title:web.getTitle(),loading:web.isLoading(),back:web.navigationHistory.canGoBack(),forward:web.navigationHistory.canGoForward()});}
 open(id,address){
  const bot=this.getBot(id);if(!bot)throw new Error('Choose a Bot.');if(address!=null&&!allowed(address))throw new Error('Enter an HTTP or HTTPS page.');
  let entry=this.entries.get(bot.id);
  if(!entry||entry.window.isDestroyed()){
   if(this.entries.size>=8)throw new Error('Close a Bot browser before opening another. Up to eight browser windows can be open.');
   const window=new BrowserWindow({width:1150,height:820,minWidth:650,minHeight:450,title:bot.name+' · Local browser',webPreferences:{preload:path.join(__dirname,'browser-preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false}});
   const view=new WebContentsView({webPreferences:{partition:'persist:opengrokbot-browser-'+bot.id.toLowerCase(),contextIsolation:true,sandbox:true,nodeIntegration:false,webSecurity:true}});
   entry={window,view,reading:false};this.entries.set(bot.id,entry);window.contentView.addChildView(view);
   const size=()=>{const bounds=window.getContentBounds();view.setBounds({x:0,y:64,width:bounds.width,height:Math.max(0,bounds.height-64)});};window.on('resize',size);size();
   window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',event=>event.preventDefault());
   view.webContents.setWindowOpenHandler(({url})=>{if(allowed(url))view.webContents.loadURL(url).catch(()=>{});return {action:'deny'};});
   for(const event of ['will-navigate','will-redirect'])view.webContents.on(event,(event,url)=>{if(!allowed(url))event.preventDefault();});
   view.webContents.session.setPermissionRequestHandler((_web,_permission,callback)=>callback(false));view.webContents.session.setPermissionCheckHandler(()=>false);
   const blockDownload=event=>event.preventDefault();view.webContents.session.on('will-download',blockDownload);entry.blockDownload=blockDownload;
   for(const event of ['did-start-loading','did-stop-loading','did-navigate','did-navigate-in-page','page-title-updated'])view.webContents.on(event,()=>this.update(entry));
   window.on('closed',()=>{if(!view.webContents.isDestroyed()){view.webContents.session.removeListener('will-download',entry.blockDownload);view.webContents.close();}this.entries.delete(bot.id);});
   window.loadFile(chromeFile).catch(()=>{});view.webContents.loadURL(address||'https://duckduckgo.com').catch(()=>{});
  }else{entry.window.show();entry.window.focus();if(address)entry.view.webContents.loadURL(address).catch(()=>{});}
  return entry;
 }
 async read(id,address){
  if(!allowed(address))throw new Error('Choose an HTTP or HTTPS page.');
  const entry=this.open(id);if(entry.reading)throw new Error('This Bot’s browser is already reading a page.');entry.reading=true;
  const web=entry.view.webContents;let timer,note,loadError;
  try{
   try{
    // A slow page is not a failure: after 45 seconds stop loading and use whatever has rendered so far.
    await Promise.race([web.loadURL(address),new Promise(resolve=>{timer=setTimeout(()=>{web.stop();note='The page was slow to load, so this is what had loaded when I stopped waiting. If something is missing, try another page or approach.';resolve();},45000);})]);
   }catch(error){
    // ERR_ABORTED is a redirect or a stop; anything else is a real failure the Bot should hear about so it can try another way.
    if(error?.code!=='ERR_ABORTED'&&error?.errno!==-3)loadError=String(error?.message||'The page could not be loaded.').slice(0,200);
   }finally{clearTimeout(timer);}
   await settle(web);
   let page;try{page=JSON.parse(await web.executeJavaScript(expression));}catch{page=null;}
   page=finishPage(address,page,{loadError,note});
   const shot=this.getDirectory?await captureView(web,this.getDirectory(this.getBot(id).id)):{error:'Screenshots are unavailable.'};
   if(shot.path){page.screenshot=shot.path;page.screenshotNote='A screenshot of the page exactly as rendered (layout, images, charts, scores, canvas content that text extraction misses). Open this image file with your file or image viewing tool and use it together with the text.';}
   else page.screenshotError=shot.error;
   return JSON.stringify(page);
  }catch{throw new Error('The local browser could not finish reading the page. Its window stays open so you can inspect it or sign in, then retry.');}
  finally{entry.reading=false;}
 }
 _entry(id){const bot=this.getBot(id);if(!bot)throw new Error('Choose a Bot.');const entry=this.open(id);if(entry.reading)throw new Error('This Bot’s browser is busy. Try again in a moment.');return {entry,bot,web:entry.view.webContents};}
 /** The address of the page a Bot's browser is on, or an empty string. Used to match written approval rules. */
 pageHost(id){try{return new URL(this._entry(id).web.getURL()).host;}catch{return '';}}
 async inspectClick(id,target){const {web}=this._entry(id);return web.executeJavaScript(inPage(pageClick,{target,mode:'inspect'}));}
 async click(id,target){const {web}=this._entry(id);return web.executeJavaScript(inPage(pageClick,{target,mode:'click'}));}
 async inspectField(id,target,submit){const {web}=this._entry(id);return web.executeJavaScript(inPage(pageField,{target,mode:'inspect',value:'',submit:!!submit}));}
 async type(id,target,value,submit){const {web}=this._entry(id);return web.executeJavaScript(inPage(pageField,{target,mode:'type',value,submit:!!submit}));}
 async scroll(id,direction){const {web}=this._entry(id);return web.executeJavaScript(inPage(pageScroll,{direction}));}
 async back(id){const {web}=this._entry(id);if(web.navigationHistory.canGoBack())web.navigationHistory.goBack();}
 /** The page as it looks now (text, links, screenshot), after waiting for it to settle. Used after every interaction. */
 async snapshot(id){
  const {bot,web}=this._entry(id);await pause(500);await settle(web);
  let page;try{page=JSON.parse(await web.executeJavaScript(expression));}catch{page=null;}
  page=finishPage(web.getURL(),page,{});
  const shot=this.getDirectory?await captureView(web,this.getDirectory(bot.id)):{error:'Screenshots are unavailable.'};
  if(shot.path){page.screenshot=shot.path;page.screenshotNote='A screenshot of the page as it looks now. Open this image file to see the result of your action.';}else page.screenshotError=shot.error;
  return JSON.stringify(page);
 }
 /** Web search through the Bot's own browser (no key needed). Up to eight results. */
 async search(id,query){
  const {web}=this._entry(id);
  try{await web.loadURL('https://duckduckgo.com/html/?q='+encodeURIComponent(String(query).slice(0,200)));}catch(error){if(error?.code!=='ERR_ABORTED')throw new Error('The search page could not be loaded.');}
  await settle(web,{limit:3000});
  return web.executeJavaScript(inPage(pageSearch,{}));
 }
 /** Opens the page and types a saved login into it. Credentials go straight into the page from this process and are never returned. Only on loginHost (or a subdomain), re-checked after every redirect. */
 async fillLogin(id,{url,loginHost,username,password}){
  const {web}=this._entry(id);if(!allowed(url))throw new Error('Choose an HTTPS page.');
  try{await web.loadURL(url);}catch(error){if(error?.code!=='ERR_ABORTED')throw new Error('The sign-in page could not be loaded.');}
  await settle(web);let step='no-form';
  for(let attempt=0;attempt<3;attempt++){
   let host='';try{host=new URL(web.getURL()).hostname;}catch{}
   if(!hostMatches(loginHost,host))throw new Error(`The page moved to ${host||'another site'}, which is not the site this login was saved for. Nothing was filled in.`);
   step=await web.executeJavaScript(inPage(pageFill,{username,password}))||'no-form';
   if(step!=='username-submitted'||attempt===2)break;
   await pause(3000);await settle(web);
  }
  if(step==='submitted')return `Entered the saved username and password for ${loginHost} and submitted the form. Read the page to see whether sign-in worked; a verification code may still be needed.`;
  if(step==='username-submitted')return `Entered the username for ${loginHost} and continued, but no password step appeared. Read the page to see where it stopped.`;
  if(step==='filled'||step==='username-filled')return `Filled in the login fields for ${loginHost} but found no button to submit. Ask the user to press the sign-in button in the Bot browser.`;
  return 'No login form was found on the page.';
 }
 async preview(id){const bot=this.getBot(id),entry=bot&&this.entries.get(bot.id);if(!entry||entry.window.isDestroyed())return {title:'Browser not open',url:'',imageData:null};const image=await entry.view.webContents.capturePage();return {title:entry.view.webContents.getTitle(),url:entry.view.webContents.getURL(),imageData:image.resize({width:900}).toJPEG(60).toString('base64')};}
 close(id){this.entries.get(id)?.window.close();}
 closeAll(){for(const entry of [...this.entries.values()])entry.window.close();}
}
module.exports={LocalBrowsers,settle,captureView,finishPage,hostMatches};
