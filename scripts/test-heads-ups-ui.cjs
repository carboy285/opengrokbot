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
   {id:'e2',botID:main.id,kind:'bot',text:'Ana Ruiz needs your signature on the lease by Friday. Want me to draft a reply?',state:'complete',provider:'Codex',headsUp:{kind:'email',title:'Checked your inbox · 2 new emails',senders:[{name:'Ana Ruiz',address:'ana@example.com',subject:'Lease'},{name:'Sam Lee',address:'sam@example.com',subject:'Lunch'}]},date:now},
   {id:'e3',botID:main.id,kind:'activity',text:'Checked 3 new emails · nothing needs you right now',headsUp:{kind:'email',title:'x'},date:now},
   {id:'e4',botID:main.id,kind:'bot',text:'Standup starts in 10 min (9:30 AM).\nJoin: https://meet.google.com/abc',state:'complete',provider:'Heads-up',headsUp:{kind:'meeting',title:'Standup',link:'https://meet.google.com/abc'},date:now});
  await page.addInitScript(seed=>{
   let listener,proactiveListener;let workspace=seed;
   let proactive={config:{enabled:false,email:true,meetings:true,leadMinutes:10,conflicts:true,brief:true,briefTime:'08:00',quietHours:true,quietStart:'22:00',quietEnd:'07:00',intervalMinutes:3,openAtLogin:false},composio:true,checking:false,lastCheck:null,nextCheck:null,gmail:'off',calendar:'off',error:null,muted:[],today:{next:{title:'Design review',start:new Date(Date.now()+12*60000).toISOString(),link:'https://meet.google.com/xyz'},remaining:3,waiting:2,overlaps:1}};
   window.calls=[];
   const status={providers:[],installed:[{id:'codex:fixture',provider:'codex',name:'Codex',path:'/fixture/codex',version:'fixture'}],selected:'codex:fixture',complete:true};
   window.configureCalls=[];
   window.desktop={load:async()=>({ok:true,value:workspace}),save:async value=>{workspace=value;return {ok:true,value};},setupStatus:async()=>({ok:true,value:status}),scanCLIs:async()=>({ok:true,value:status}),onChange:callback=>listener=callback,touchBot:async()=>({ok:true}),
    composioStatus:async()=>({ok:true,value:{configured:true,toolkits:[{slug:'gmail',name:'Gmail',enabled:true,connected:true},{slug:'googlecalendar',name:'Google Calendar',enabled:true,connected:true}]}}),composioRefresh:async()=>({ok:true,value:{}}),
    proactiveStatus:async()=>({ok:true,value:proactive}),
    proactiveConfigure:async changes=>{window.configureCalls.push(changes);proactive={...proactive,config:{...proactive.config,...changes},gmail:changes.enabled?'ok':proactive.gmail,calendar:changes.enabled?'ok':proactive.calendar,lastCheck:changes.enabled?new Date().toISOString():proactive.lastCheck};return {ok:true,value:proactive};},
    proactiveCheck:async()=>({ok:true,value:proactive}),headsUpJoin:async url=>{window.calls.push(['join',url]);return {ok:true};},headsUpSnooze:async(id,minutes)=>{window.calls.push(['snooze',id,minutes]);return {ok:true,value:workspace};},headsUpDismiss:async id=>{window.calls.push(['dismiss',id]);const e=workspace.entries.find(x=>x.id===id);e.kind='activity';e.text='Dismissed · '+e.headsUp.title;delete e.state;return {ok:true,value:workspace};},headsUpMute:async(address,muted)=>{window.calls.push(['mute',address,muted]);proactive={...proactive,muted:muted?[address]:[]};return {ok:true,value:proactive};},organizeBot:async(id,changes)=>{const bot=workspace.bots.find(x=>x.id===id);for(const [k,v] of Object.entries(changes)){if(v===null)delete bot[k];else bot[k]=v;}return {ok:true,value:workspace};},onProactiveChange:callback=>proactiveListener=callback,onHeadsUpOpen:()=>{}};
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

  // Today card is shown once heads-ups are on; actions on cards.
  assert.equal(await page.locator('.today-card').count(),0,'no Today card while heads-ups are off');
  await page.evaluate(()=>{window.proactiveOn=true;});
  await page.locator('.message-row.heads-up').filter({hasText:'Standup'}).getByRole('button',{name:'Join'}).click();
  assert.deepEqual((await page.evaluate(()=>window.calls)).at(-1),['join','https://meet.google.com/abc']);
  await page.locator('.message-row.heads-up').filter({hasText:'Ana Ruiz'}).getByRole('button',{name:'Draft a reply…'}).click();
  await page.getByRole('menuitem',{name:'Reply to Sam Lee'}).click();
  assert.equal(await page.locator('#draft').inputValue(),'Draft a reply to Sam Lee about “Lunch”. Show it to me before sending.');
  assert.equal(await page.evaluate(()=>window.calls.filter(x=>x[0]==='send').length),0,'drafting never sends');
  await page.locator('#draft').fill('');
  await page.locator('.message-row.heads-up').filter({hasText:'Ana Ruiz'}).getByRole('button',{name:'Snooze'}).click();
  await page.getByRole('menuitem',{name:'For 3 hours'}).click();
  assert.deepEqual((await page.evaluate(()=>window.calls)).at(-1),['snooze','e2',180]);
  await page.locator('.message-row.heads-up').filter({hasText:'Ana Ruiz'}).getByRole('button',{name:'More actions'}).click();
  await page.getByRole('menuitem',{name:'Stop heads-ups from Ana Ruiz'}).click();
  await page.getByRole('status').getByText('You won’t hear about mail from Ana Ruiz.').waitFor();
  await page.getByRole('button',{name:'Undo'}).click();
  assert.deepEqual((await page.evaluate(()=>window.calls)).at(-1),['mute','ana@example.com',false]);
  await page.locator('.message-row.heads-up').filter({hasText:'Standup'}).getByRole('button',{name:'Done'}).click();
  await page.getByText('Dismissed · Standup').waitFor();
  assert.equal(await page.locator('.message-row.heads-up').filter({hasText:'Standup'}).count(),0);

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
  await page.locator('.today-card').getByText('Design review').waitFor();
  await page.locator('.today-card').getByText('in 12 min').waitFor();
  await page.locator('.today-card').getByText('2 emails waiting on you').waitFor();
  await page.locator('.today-card').getByText('1 overlap').waitFor();
  await page.screenshot({animations:'disabled',path:'artifacts/visuals-web/heads-ups-today.png'});
  // Light theme keeps the cards and Today card readable.
  await page.evaluate(()=>{document.documentElement.dataset.theme='light';});
  await page.screenshot({animations:'disabled',path:'artifacts/visuals-web/heads-ups-light.png'});
  await page.evaluate(()=>{document.documentElement.dataset.theme='dark';});

  // Connect apps nudges toward heads-ups once Gmail or Calendar is connected.
  await page.getByRole('button',{name:'Connect apps',exact:false}).click();
  await page.getByRole('button',{name:'Set up heads-ups'}).waitFor();
  await page.keyboard.press('Escape');

  // Two heads-ups at once become one banner; a quick upward flick sends it away without opening the chat.
  await page.locator('#bot-list .bot-row').filter({hasText:'School'}).click();
  await page.evaluate(seed=>{for(const [id,text] of [['f1','Lunch moved to 1 PM.'],['f2','Your package is out for delivery']])seed.entries.push({id,botID:seed.bots[0].id,kind:'bot',text,state:'complete',provider:'Heads-up',headsUp:{kind:id==='f1'?'moved':'delivery',title:text},date:new Date().toISOString()});window.pushWorkspace(seed);},seed);
  await page.locator('.heads-up-banner.visible').getByText('Grok Bot · 2 heads-ups').waitFor();
  await page.waitForTimeout(450);
  const box=await page.locator('.heads-up-banner').boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();
  for(let i=1;i<=5;i++){await page.mouse.move(box.x+box.width/2,box.y+box.height/2-i*14);await page.waitForTimeout(8);}
  await page.mouse.up();
  await page.waitForFunction(()=>!document.querySelector('.heads-up-banner.visible'));
  await page.locator('#chat-heading').getByText('School').waitFor();
  // A small downward pull rubber-bands and springs back.
  await page.evaluate(seed=>{seed.entries.push({id:'f3',botID:seed.bots[0].id,kind:'bot',text:'Standup in 5 min.',state:'complete',provider:'Heads-up',headsUp:{kind:'meeting',title:'Standup'},date:new Date().toISOString()});window.pushWorkspace(seed);},seed);
  await page.locator('.heads-up-banner.visible').waitFor();await page.waitForTimeout(450);
  const box2=await page.locator('.heads-up-banner').boundingBox();
  await page.mouse.move(box2.x+40,box2.y+20);await page.mouse.down();await page.mouse.move(box2.x+40,box2.y+120,{steps:5});
  const pulled=await page.locator('.heads-up-banner').evaluate(x=>x.dragY);
  assert.ok(pulled>0&&pulled<100,'downward pull resists: '+pulled);
  await page.mouse.up();await page.waitForFunction(()=>Math.abs(document.querySelector('.heads-up-banner').dragY||0)<1);
  assert.equal(await page.locator('.heads-up-banner.visible').count(),1);
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
