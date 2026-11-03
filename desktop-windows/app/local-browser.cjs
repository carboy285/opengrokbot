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
  const entry=this.open(id);if(entry.reading)throw new Error('This Bot’s browser is already reading a page.');entry.reading=true;let timer;
  try{
   await Promise.race([entry.view.webContents.loadURL(address),new Promise((_,reject)=>{timer=setTimeout(()=>{entry.view.webContents.stop();reject(new Error('The local browser timed out loading this page.'));},20000);})]);
   await settle(entry.view.webContents);
   const page=JSON.parse(await entry.view.webContents.executeJavaScript(expression));
   const shot=this.getDirectory?await captureView(entry.view.webContents,this.getDirectory(this.getBot(id).id)):{error:'Screenshots are unavailable.'};
   if(shot.path){page.screenshot=shot.path;page.screenshotNote='A screenshot of the page exactly as rendered (layout, images, charts, scores, canvas content that text extraction misses). Open this image file with your file or image viewing tool and use it together with the text.';}
   else page.screenshotError=shot.error;
   return JSON.stringify(page);
  }catch{throw new Error('The local browser could not finish reading the page. Its window stays open so you can inspect it or sign in, then retry.');}
  finally{clearTimeout(timer);entry.reading=false;}
 }
 async preview(id){const bot=this.getBot(id),entry=bot&&this.entries.get(bot.id);if(!entry||entry.window.isDestroyed())return {title:'Browser not open',url:'',imageData:null};const image=await entry.view.webContents.capturePage();return {title:entry.view.webContents.getTitle(),url:entry.view.webContents.getURL(),imageData:image.resize({width:900}).toJPEG(60).toString('base64')};}
 close(id){this.entries.get(id)?.window.close();}
 closeAll(){for(const entry of [...this.entries.values()])entry.window.close();}
}
module.exports={LocalBrowsers,settle,captureView};
