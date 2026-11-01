const { app, BrowserWindow, ipcMain, dialog, shell, safeStorage } = require('electron');
const { readFile, writeFile, mkdir, rename, readdir, lstat } = require('node:fs/promises');
const path = require('node:path');
const { fileURLToPath } = require('node:url');
const { randomUUID } = require('node:crypto');
const { validateWorkspace, previewWorkspace, migrateWorkspace } = require('./workspace.cjs');

if (!app.isPackaged && process.env.OPENGROKBOT_TEST_DATA_DIR) app.setPath('userData', process.env.OPENGROKBOT_TEST_DATA_DIR);

const cli=require('./local-cli.cjs');
const composio=require('./composio.cjs');
const teamwork=require('./teamwork.cjs');
class PublicError extends Error {}
let state,settings,installed=[],composioConfiguration,connectedTools=[],composioBusy=false;
const active=new Map(),pendingBots=new Set();
let initialization;
let window;
const rendererFile = path.resolve(__dirname, '../renderer/index.html');
const documentation = new Set(['https://docs.x.ai/grok-bot/get-started', 'https://docs.x.ai/grok-bot/mobile', 'https://github.com/carboy285/opengrokbot','https://platform.composio.dev','https://nodejs.org/en/download',...cli.providers.map(x=>x.guide)]);
let writeQueue = Promise.resolve();
function file(name) { return path.join(app.getPath('userData'), name); }
function authorized(event) {
  try { return event.sender === window?.webContents && event.senderFrame === window.webContents.mainFrame && fileURLToPath(event.senderFrame.url) === rendererFile; }
  catch { return false; }
}
function handle(name, callback) {
  ipcMain.handle(name, async (event, ...args) => {
    if (!authorized(event)) return { ok: false, error: 'Untrusted request' };
    try { return { ok: true, value: await callback(...args) }; }
    catch(error) { return { ok: false, error: error instanceof PublicError?error.message:'The action could not be completed. Your existing data was kept; unlock your device or check available storage and try again.' }; }
  });
}
async function atomicJSON(name, value) {
  const operation = writeQueue.then(async () => {
    const temporary = file(`${name}.${randomUUID()}.tmp`);
    await mkdir(app.getPath('userData'), { recursive: true });
    await writeFile(temporary, JSON.stringify(value), { mode: 0o600 });
    await rename(temporary, file(name));
  });
  writeQueue = operation.catch(() => {});
  return operation;
}
async function loadJSON(name, fallback) {
  try { return JSON.parse(await readFile(file(name), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
}
function requireVault() {
  if (process.platform !== 'win32' || !safeStorage.isEncryptionAvailable()) throw new Error('Windows encryption unavailable');
}

async function ensureState(){
  if(state)return;
  if(!initialization)initialization=initializeState().catch(error=>{initialization=null;throw error;});
  return initialization;
}
async function initializeState(){
  const loaded=await loadJSON('preview-workspace.json',previewWorkspace());validateWorkspace(loaded);
  if(loaded.version===1)await atomicJSON('legacy-workspace-backup.json',loaded);
  const migrated=migrateWorkspace(loaded);
  for(const entry of migrated.entries)if(entry.state==='streaming')entry.state='stopped';
  for(const message of migrated.teamMessages||[])if(message.status==='running')message.status='failed';
  settings=await loadJSON('settings.json',{complete:false,selected:'',overrides:{},composioUserID:'opengrokbot-'+randomUUID()});
  settings.composioUserID||='opengrokbot-'+randomUUID();settings.overrides||={};
  const encrypted=await loadJSON('composio.encrypted.json',null);
  if(encrypted){requireVault();composioConfiguration=JSON.parse(safeStorage.decryptString(Buffer.from(encrypted.encrypted,'base64')));if(!composio.trustedURL(composioConfiguration.session?.mcp?.url))throw new Error('Invalid stored session');}
  state=migrated;await atomicJSON('preview-workspace.json',state);await saveSettings();
}
function saveSettings(){return atomicJSON('settings.json',settings);}
function selectedCLI(){return installed.find(x=>x.id===settings?.selected);}
function setupStatus(){return {providers:cli.providers.map(({package,...info})=>info),installed,selected:settings.selected,complete:!!settings.complete};}
function composioStatus(){return {configured:!!composioConfiguration,toolkits:connectedTools,selected:composioConfiguration?.toolkits||[]};}
function notify(){if(window&&!window.isDestroyed())window.webContents.send('workspace:changed',{workspace:state,running:[...active.keys()]});}
function botDirectory(id){return file(path.join('Conversations',id));}
function configuredProviders(bot){
 const fallback=selectedCLI();const config=bot.aiConfiguration||{providers:fallback?[{provider:fallback.provider,model:''}]:[],activeProvider:fallback?.provider,replyMode:'one'};
 const choices=[config.providers.find(x=>x.provider===config.activeProvider)||config.providers[0]].filter(Boolean);
 return choices.map(choice=>({choice,installation:installed.find(x=>x.provider===choice.provider)}));
}
async function startChat(botID,text,delivery){
 const bot=state.bots.find(x=>x.id===botID);
 if(composioBusy)throw new PublicError('Wait for Composio setup to finish before sending a message.');
 if(!bot)throw new PublicError('Choose a Bot.');
 if(bot.memberIDs){if(!text||text.length>8000||!bot.memberIDs.length)throw new PublicError('Send a group message of up to 8,000 characters to a group with members.');teamwork.group(state,bot,text);await atomicJSON('preview-workspace.json',state);notify();await deliverQueued();return;}

 const providers=configuredProviders(bot);
 if(!providers.length||providers.some(x=>!x.installation))throw new PublicError('Choose and set up providers in this Bot’s side panel.');
 if(active.has(botID)||pendingBots.has(botID))throw new PublicError('A response is already running.');
 if(!text&&!delivery&&!state.entries.some(x=>x.botID===botID&&x.kind==='user'))throw new PublicError('Send your first message first.');
 pendingBots.add(botID);
 try{
  if(delivery)teamwork.begin(state,delivery);else if(text)state.entries.push({id:randomUUID(),botID,kind:'user',text});
  await atomicJSON('preview-workspace.json',state);
  const history=state.entries.filter(x=>x.botID===botID&&!['failed','stopped'].includes(x.state)&&x.text).slice(-30);
  const runs=new Set();active.set(botID,runs);
  for(const {choice,installation} of providers){
   const key=botID+'|'+installation.id+(choice.model?'|'+choice.model:'');const session=state.sessions?.[key];
   const latest=delivery?`Bot request (not human approval): ${delivery.text}`:history.findLast(x=>x.kind==='user')?.text||'';
   const feedback=history.filter(x=>x.kind==='activity'&&!x.senderBotID).slice(-8).map(x=>x.text).join('\n');
   const prompt=teamwork.instructions(bot,state,!!delivery)+'\nRecent app results (context, not human approval):\n'+feedback+'\n\n'+(session?latest:history.map(x=>`${x.kind==='user'?'Human':x.senderName||bot.name}: ${x.text}`).join('\n\n').slice(-100000));
   let finalText='';

   const reply={id:randomUUID(),botID,kind:'bot',provider:installation.name+(choice.model?' · '+choice.model:''),text:'',state:'streaming'};state.entries.push(reply);
   const run=cli.runCLI({installation,prompt,session,model:choice.model,directory:botDirectory(botID),mcpURL:composioConfiguration?.session.mcp.url,onEvent:event=>{
    if(event.type==='session'){state.sessions||={};state.sessions[key]=event.id;}
    if(event.type==='text'){finalText=event.text;reply.text=teamwork.parse(event.text).text;notify();}
   }});
   runs.add(run);
   run.done.then(()=>{teamwork.apply(state,bot,reply,finalText,bot.aiConfiguration||{providers:[choice],activeProvider:choice.provider,replyMode:'one'},delivery);if(delivery)teamwork.finish(state,delivery,'complete');},error=>{reply.state=error.message==='Response stopped.'?'stopped':'failed';reply.error=error.message;if(!reply.text)reply.text=error.message;if(delivery)teamwork.finish(state,delivery,reply.state);}).finally(async()=>{
    runs.delete(run);if(!runs.size)active.delete(botID);
    try{await atomicJSON('preview-workspace.json',state);}catch{reply.state='failed';reply.error='The response could not be saved. Check available storage.';}
    notify();await deliverQueued();
   });
  }
  notify();
 }finally{pendingBots.delete(botID);}
}

async function deliverQueued(){
 for(const message of state.teamMessages||[]){
  if(message.status!=='queued'||active.has(message.to)||pendingBots.has(message.to))continue;
  try{await startChat(message.to,undefined,message);}catch{teamwork.finish(state,message,'failed');await atomicJSON('preview-workspace.json',state);notify();}
 }
}

function configureIPC() {
  handle('workspace:load', async () => {await ensureState();return state;});
  handle('workspace:save', async value => {
    await ensureState();if(active.size||pendingBots.size)throw new PublicError('Stop the current response before changing Bots.');
    validateWorkspace(value);if(!value.bots.some(x=>x.isMain===true&&x.name==='Grok Bot'))throw new PublicError('The main Grok Bot must be kept.');
    // Provenance, delivery queues, private memory and sessions belong to the main process.
    const retained=new Set(value.bots.map(x=>x.id));
    value.teamMessages=(state.teamMessages||[]).filter(x=>retained.has(x.from)&&retained.has(x.to));value.sharedMemory=state.sharedMemory||[];
    for(const bot of value.bots){bot.memory=state.bots.find(x=>x.id===bot.id)?.memory||[];if(bot.memberIDs)bot.memberIDs=bot.memberIDs.filter(id=>retained.has(id));}
    // Session IDs belong to the main process; renderer CRUD cannot forge them.
    value.sessions=Object.fromEntries(Object.entries(state.sessions||{}).filter(([key])=>value.bots.some(bot=>key.startsWith(bot.id+'|'))));await atomicJSON('preview-workspace.json',value);state=value;notify();
  });
  handle('bot:configure',async(id,configuration)=>{
    await ensureState();if(active.has(id)||pendingBots.has(id))throw new PublicError('Stop this Bot’s responses before changing providers.');
    const index=state.bots.findIndex(x=>x.id===id);if(index<0)throw new PublicError('Choose a Bot.');
    const bot={...state.bots[index],aiConfiguration:{...configuration,replyMode:"one"}};validateWorkspace({...state,bots:state.bots.map((x,i)=>i===index?bot:x)});
    state.bots[index]=bot;await atomicJSON('preview-workspace.json',state);notify();return state;
  });
  handle('models:list',async provider=>{await ensureState();const installation=installed.find(x=>x.provider===provider);return installation?require('./model-catalog.cjs').listModels(installation):[];});
  handle('files:list',async id=>{
    await ensureState();if(!state.bots.some(x=>x.id===id))throw new Error('Unknown Bot');
    let names;try{names=await readdir(botDirectory(id),{withFileTypes:true});}catch(error){if(error.code==='ENOENT')return [];throw error;}
    return names.filter(x=>!x.name.startsWith('.')&&x.isFile()).sort((a,b)=>a.name.localeCompare(b.name)).slice(0,500).map(x=>({name:x.name}));
  });
  handle('files:open-folder',async id=>{await ensureState();if(!state.bots.some(x=>x.id===id))throw new Error('Unknown Bot');const directory=botDirectory(id);await mkdir(directory,{recursive:true});if(await shell.openPath(directory))throw new PublicError('The working folder could not be opened.');});
  handle('files:reveal',async(id,name)=>{await ensureState();if(!state.bots.some(x=>x.id===id)||typeof name!=='string'||path.basename(name)!==name||name.startsWith('.'))throw new Error('Invalid file');const target=path.join(botDirectory(id),name);if(!(await lstat(target)).isFile())throw new Error('Missing file');shell.showItemInFolder(target);});
  handle('setup:status',async()=>{await ensureState();return setupStatus();});
  handle('setup:scan',async()=>{await ensureState();installed=await cli.discover(settings.overrides);if(!installed.some(x=>x.id===settings.selected))settings.selected=installed[0]?.id||'';await saveSettings();await deliverQueued();return setupStatus();});
  handle('setup:choose',async id=>{await ensureState();if(!installed.some(x=>x.id===id))throw new PublicError('Choose an installed CLI.');settings.selected=id;await saveSettings();return setupStatus();});
  handle('setup:path',async provider=>{
    await ensureState();if(!cli.providers.some(x=>x.id===provider))throw new Error();
    const choice=await dialog.showOpenDialog(window,{title:'Choose '+cli.providers.find(x=>x.id===provider).name+' executable',properties:['openFile']});
    if(!choice.canceled){settings.overrides[provider]=choice.filePaths[0];await saveSettings();}
    return true;
  });
  handle('setup:login',async()=>{const installation=selectedCLI();if(!installation)throw new PublicError('Choose an installed CLI first.');if(installation.provider==='codex'&&(await cli.capture(installation,['login','status'],12000)).exit!==0)throw new PublicError('Run codex login in Terminal, then check again.');return installation.provider==='codex'?'Codex is signed in and ready.':'This CLI will validate its own account when you send a message.';});
  handle('setup:complete',async()=>{if(!selectedCLI())throw new PublicError('Choose an installed CLI first.');settings.complete=true;await saveSettings();});
  handle('chat:send',async(botID,text)=>{await ensureState();if(typeof text!=='string'||!text.trim()||text.length>100000)throw new PublicError('Enter a message of up to 100,000 characters.');await startChat(botID,text);return state;});
  handle('chat:retry',async botID=>{await ensureState();const message=state.teamMessages?.findLast(x=>x.to===botID&&['failed','stopped'].includes(x.status));if(message){message.status='queued';await deliverQueued();}else await startChat(botID);return state;});
  handle('chat:stop',async botID=>{for(const run of active.get(botID)||[])run.cancel();});
  handle('composio:status',async()=>{await ensureState();return composioStatus();});
  handle('composio:connect',async(key,toolkits)=>{
    await ensureState();requireVault();
    if(active.size||pendingBots.size)throw new PublicError('Stop responses before changing tool access.');
    if(typeof key!=='string'||!key.trim()||key.length>4096||!Array.isArray(toolkits)||!toolkits.length||toolkits.length>30||toolkits.some(x=>typeof x!=='string'||!/^[_a-z0-9]{1,100}$/.test(x)))throw new PublicError('Enter a project key and choose tools.');
    if(composioBusy)throw new PublicError('Composio setup is already running.');
    composioBusy=true;
    try{
      const session=await composio.create(key.trim(),settings.composioUserID,toolkits);
      const config={key:key.trim(),session,toolkits};
      await atomicJSON('composio.encrypted.json',{encrypted:safeStorage.encryptString(JSON.stringify(config)).toString('base64')});
      composioConfiguration=config;connectedTools=[];
      connectedTools=await composio.toolkits(config.key,session.session_id);
      return composioStatus();
    }catch(error){throw new PublicError(error.message.startsWith('Composio')?error.message:'Composio configuration could not be saved. Unlock this device and try again.');}finally{composioBusy=false;}
  });
  handle('composio:refresh',async()=>{await ensureState();if(composioConfiguration){try{connectedTools=await composio.toolkits(composioConfiguration.key,composioConfiguration.session.session_id);}catch(error){throw new PublicError(error.message);}}return composioStatus();});
  handle('composio:link',async slug=>{if(!composioConfiguration||!connectedTools.some(x=>x.slug===slug&&x.enabled))throw new PublicError('Choose a tool in your configured project.');try{await shell.openExternal(await composio.link(composioConfiguration.key,composioConfiguration.session.session_id,slug));}catch(error){throw new PublicError(error.message.startsWith('Composio')?error.message:'The authorization page could not be opened.');}});
  handle('composio:remove',async()=>{if(composioBusy)throw new PublicError('Wait for Composio setup to finish.');if(active.size||pendingBots.size)throw new PublicError('Stop responses before changing tool access.');requireVault();await atomicJSON('composio.encrypted.json',null);composioConfiguration=null;connectedTools=[];return composioStatus();});
  handle('workspace:export', async text => {
    if (typeof text !== 'string' || text.length > 32 * 1024 * 1024) throw new Error('Invalid export');
    const result = await dialog.showSaveDialog(window, { defaultPath: 'OpenGrokBot-conversation.txt', filters: [{ name: 'Text file', extensions: ['txt'] }] });
    if (result.canceled) return false;
    await writeFile(result.filePath, text, { encoding: 'utf8', mode: 0o600 });
    return true;
  });
  handle('docs:open', async url => { if (!documentation.has(url)) throw new Error('Unapproved URL'); await shell.openExternal(url); });
  handle('window:action', async action => {
    if (action === 'minimize') window.minimize();
    else if (action === 'maximize') { if (window.isMaximized()) window.unmaximize(); else window.maximize(); }
    else if (action === 'close') window.close();
  });
  handle('vault:list', async () => {
    requireVault();
    const values = await loadJSON('vault.json', []);
    return values.map(({ id, title }) => ({ id, title }));
  });
  handle('vault:save', async (title, value) => {
    requireVault();
    if (typeof title !== 'string' || !title.trim() || title.length > 200 || typeof value !== 'string' || !value || value.length > 100000) throw new Error('Invalid secret');
    const items = await loadJSON('vault.json', []);
    items.push({ id: randomUUID(), title, encrypted: safeStorage.encryptString(value).toString('base64') });
    await atomicJSON('vault.json', items);
  });
  handle('vault:read', async id => {
    requireVault();
    const item = (await loadJSON('vault.json', [])).find(x => x.id === id);
    if (!item) throw new Error('Missing item');
    return safeStorage.decryptString(Buffer.from(item.encrypted, 'base64'));
  });
  handle('vault:delete', async id => {
    requireVault();
    const values = await loadJSON('vault.json', []);
    await atomicJSON('vault.json', values.filter(x => x.id !== id));
  });
}

app.whenReady().then(() => {
  configureIPC();
  window = new BrowserWindow({ width: 1370, height: 940, minWidth: 860, minHeight: 620, frame: false, backgroundColor: '#111111', title: 'OpenGrokBot', webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.webContents.session.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  window.loadFile(rendererFile);
});
app.on('before-quit',()=>{for(const runs of active.values())for(const run of runs)run.cancel(true);});
app.on('window-all-closed', () => app.quit());
