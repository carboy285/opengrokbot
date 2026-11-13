// Browser check of the heads-up UI against a fixture desktop bridge.
// Run: CHROMIUM_PATH=/path/to/chromium node scripts/test-heads-ups-ui.cjs
const {chromium}=require('@playwright/test');const {spawn}=require('node:child_process');const fs=require('node:fs/promises');const assert=require('node:assert/strict');
const {previewWorkspace}=require('../desktop-windows/app/workspace.cjs');
(async()=>{
 const server=spawn('python3',['-m','http.server','4175','--bind','127.0.0.1','--directory','desktop-windows/renderer'],{stdio:'ignore'});let browser;
 try{
  await new Promise((resolve,reject)=>{server.once('error',reject);setTimeout(resolve,400);});
  browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1370,height:940},deviceScaleFactor:Number(process.env.SCALE||1)});page.setDefaultTimeout(10000);
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const seed=previewWorkspace();const main=seed.bots[0];
  seed.bots.push({id:'11111111-1111-4111-8111-111111111111',name:'School',purpose:'Homework help',color:'purple'});
  const now=new Date().toISOString();
  seed.entries.push(
   {id:'e1',botID:main.id,kind:'user',text:'Heads-up check: long prompt with untrusted email text',delivery:'proactive',label:'Checked your inbox · 2 new emails',date:now},
   {id:'e2',botID:main.id,kind:'bot',text:'Ana Ruiz needs your signature on the lease by Friday. Want me to draft a reply?',state:'complete',provider:'Codex',headsUp:{kind:'email',title:'Checked your inbox · 2 new emails'},date:now},
   {id:'e3',botID:main.id,kind:'activity',text:'Checked 3 new emails · nothing needs you right now',headsUp:{kind:'email',title:'x'},date:now},
   {id:'e4',botID:main.id,kind:'bot',text:'Standup starts in 10 min (9:30 AM).\nJoin: https://meet.google.com/abc',state:'complete',provider:'Heads-up',headsUp:{kind:'meeting',title:'Standup'},date:now});
  await page.addInitScript(seed=>{
   let listener,proactiveListener;let workspace=seed;
   let proactive={config:{enabled:false,email:true,meetings:true,leadMinutes:10,conflicts:true,brief:true,briefTime:'08:00',quietHours:true,quietStart:'22:00',quietEnd:'07:00',intervalMinutes:3,openAtLogin:false},composio:true,checking:false,lastCheck:null,nextCheck:null,gmail:'off',calendar:'off',error:null};
   const status={providers:[],installed:[{id:'codex:fixture',provider:'codex',name:'Codex',path:'/fixture/codex',version:'fixture'}],selected:'codex:fixture',complete:true};
   window.configureCalls=[];
   window.desktop={load:async()=>({ok:true,value:workspace}),save:async value=>{workspace=value;return {ok:true,value};},setupStatus:async()=>({ok:true,value:status}),scanCLIs:async()=>({ok:true,value:status}),onChange:callback=>listener=callback,touchBot:async()=>({ok:true}),
    composioStatus:async()=>({ok:true,value:{configured:true,toolkits:[{slug:'gmail',name:'Gmail',enabled:true,connected:true},{slug:'googlecalendar',name:'Google Calendar',enabled:true,connected:true}]}}),composioRefresh:async()=>({ok:true,value:{}}),
    proactiveStatus:async()=>({ok:true,value:proactive}),
    proactiveConfigure:async changes=>{window.configureCalls.push(changes);proactive={...proactive,config:{...proactive.config,...changes},gmail:changes.enabled?'ok':proactive.gmail,calendar:changes.enabled?'ok':proactive.calendar,lastCheck:changes.enabled?new Date().toISOString():proactive.lastCheck};return {ok:true,value:proactive};},
    proactiveCheck:async()=>({ok:true,value:proactive}),organizeBot:async(id,changes)=>{const bot=workspace.bots.find(x=>x.id===id);for(const [k,v] of Object.entries(changes)){if(v===null)delete bot[k];else bot[k]=v;}return {ok:true,value:workspace};},onProactiveChange:callback=>proactiveListener=callback,onHeadsUpOpen:()=>{}};
   window.pushWorkspace=next=>{workspace=next;listener({workspace:next,running:[]});};
  },seed);
  await page.goto('http://127.0.0.1:4175');
  await page.locator('#chat-heading').getByText('Grok Bot',{exact:true}).waitFor();

  // Automatic turns show their short label, never the raw prompt with email text.
  await page.getByText('Checked your inbox · 2 new emails',{exact:true}).waitFor();
  assert.equal(await page.getByText('long prompt with untrusted email text').count(),0);
  assert.equal(await page.locator('.message-row.heads-up').count(),2);
  assert.equal(await page.locator('.heads-up-tag[data-kind=email]').count(),1);
  assert.equal(await page.locator('.heads-up-tag[data-kind=meeting]').count(),1);
  await page.getByText('Checked 3 new emails · nothing needs you right now').waitFor();
  await fs.mkdir('artifacts/visuals-web',{recursive:true});
  await page.screenshot({animations:'disabled',path:'artifacts/visuals-web/heads-ups-chat.png'});

  // A heads-up arriving while another chat is open: dot + banner, and the banner opens the chat.
  await page.locator('#bot-list .bot-row').filter({hasText:'School'}).click();
  await page.locator('#chat-heading').getByText('School',{exact:true}).waitFor();
  await page.evaluate(seed=>{seed.entries.push({id:'e5',botID:seed.bots[0].id,kind:'bot',text:'Morning! One thing first: your dentist moved to 3 PM.\nThen: standup 9:30, lunch with Sam at noon.',state:'complete',provider:'Codex',headsUp:{kind:'brief',title:'Morning brief'},date:new Date().toISOString()});window.pushWorkspace(seed);},seed);
  await page.locator('.heads-up-banner.visible').waitFor();
  await page.locator('.heads-up-banner').getByText('Morning! One thing first: your dentist moved to 3 PM.').waitFor();
  assert.equal(await page.locator('.primary-card.unread').count(),1);
  await page.waitForTimeout(450);
  await page.screenshot({animations:'disabled',path:'artifacts/visuals-web/heads-ups-banner.png'});
  await page.locator('.heads-up-open').click();
  await page.locator('#chat-heading').getByText('Grok Bot',{exact:true}).waitFor();
  assert.equal(await page.locator('.primary-card.unread').count(),0);
  assert.equal(await page.locator('.heads-up-banner.visible').count(),0);

  // Settings: off by default, sub-options disabled until the master switch is on.
  await page.getByRole('button',{name:'Settings',exact:true}).click();
  await page.getByRole('button',{name:'Heads-ups',exact:true}).click();
  await page.getByRole('heading',{name:'Let Grok Bot reach out first'}).waitFor();
  assert.equal(await page.getByRole('switch',{name:'Heads-ups'}).isChecked(),false);
  assert.equal(await page.getByRole('switch',{name:'Important new email'}).isDisabled(),true);
  await page.getByRole('switch',{name:'Heads-ups'}).click();
  await page.getByText(/On · last checked/).waitFor();
  assert.equal(await page.getByRole('switch',{name:'Important new email'}).isDisabled(),false);
  await page.getByText('Connected',{exact:true}).first().waitFor();
  await page.getByRole('combobox',{name:'Minutes before a meeting'}).selectOption('15');
  await page.getByLabel('Morning brief time').fill('07:30');await page.getByLabel('Morning brief time').dispatchEvent('change');
  await page.waitForTimeout(100);
  const calls=await page.evaluate(()=>window.configureCalls);
  assert.equal(calls.at(-1).briefTime,'07:30');
  assert.equal(calls.find(x=>x.leadMinutes===15)?.enabled,true,'changes keep the rest of the config');
  // Clicking the time field must not toggle its row's switch.
  const before=await page.getByRole('switch',{name:'Quiet hours'}).isChecked();
  await page.getByLabel('Quiet hours start').click();
  assert.equal(await page.getByRole('switch',{name:'Quiet hours'}).isChecked(),before);
  await page.screenshot({animations:'disabled',path:'artifacts/visuals-web/heads-ups-settings.png'});
  await page.keyboard.press('Escape');
  await page.locator('#headsup-state').getByText('✦ Heads-ups on').waitFor();

  // Connect apps nudges toward heads-ups once Gmail or Calendar is connected.
  await page.getByRole('button',{name:'Connect apps',exact:false}).click();
  await page.getByRole('button',{name:'Set up heads-ups'}).waitFor();
  await page.keyboard.press('Escape');

  // Reduced motion still shows the banner (cross-fade, no slide).
  await page.emulateMedia({reducedMotion:'reduce'});
  await page.locator('#bot-list .bot-row').filter({hasText:'School'}).click();
  await page.evaluate(seed=>{seed.entries.push({id:'e6',botID:seed.bots[0].id,kind:'bot',text:'Design review and 1:1 overlap at 2 PM.',state:'complete',provider:'Heads-up',headsUp:{kind:'conflict',title:'Calendar overlap'},date:new Date().toISOString()});window.pushWorkspace(seed);},seed);
  await page.locator('.heads-up-banner.visible').waitFor();
  assert.equal(await page.locator('.heads-up-banner').evaluate(x=>getComputedStyle(x).transform),'matrix(1, 0, 0, 1, -270, 0)');

  // The plain browser preview explains heads-ups need the desktop app.
  const plain=await browser.newPage();await plain.goto('http://127.0.0.1:4175');
  await plain.getByRole('button',{name:'Settings',exact:true}).click();await plain.getByRole('button',{name:'Heads-ups',exact:true}).click();
  await plain.getByText('Open the installed desktop app to turn on heads-ups.',{exact:false}).waitFor();

  assert.deepEqual(errors,[]);
  console.log('PASS: heads-up cards, labels hide prompts, quiet lines, arrival banner + dot, settings switches, nudge, reduced motion, browser preview.');
 }finally{if(browser)await browser.close();server.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
