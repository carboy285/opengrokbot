const {_electron:electron}=require('@playwright/test');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');const assert=require('node:assert/strict');
(async()=>{
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'opengrokbot-smoke-'));let desktop;
 const npmDir=path.join(directory,'fixture-bin'),packageDir=path.join(npmDir,'node_modules','@openai','codex');
 await fs.mkdir(packageDir,{recursive:true});await fs.writeFile(path.join(npmDir,'codex.cmd'),'@echo off\r\n');await fs.writeFile(path.join(packageDir,'package.json'),JSON.stringify({bin:{codex:'fixture.cjs'}}));
 await fs.writeFile(path.join(packageDir,'fixture.cjs'),`
 const fs=require('node:fs');const path=require('node:path');const args=process.argv.slice(2);
 if(args[0]==='--version'){console.log('codex-cli fixture');process.exit(0);}
 if(args[0]==='login'){process.exit(0);}
 if(args[0]==='app-server'){const readline=require('node:readline');readline.createInterface({input:process.stdin}).on('line',line=>{const value=JSON.parse(line);if(value.id===1)console.log(JSON.stringify({id:1,result:{}}));if(value.id===2)console.log(JSON.stringify({id:2,result:{data:[{id:'fixture-model',model:'fixture-model',displayName:'Fixture model'}]}}));});}else{
 let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',data=>text+=data);process.stdin.on('end',()=>{
 fs.appendFileSync(${JSON.stringify(path.join(directory,'invocations.jsonl'))},JSON.stringify({args,text})+'\\n');
 if(text.endsWith('slow stop test')){console.log(JSON.stringify({type:'item.completed',item:{id:'answer',type:'agent_message',text:'Partial fixture reply'}}));setInterval(()=>{},1000);return;}
 console.log(JSON.stringify({type:'thread.started',thread_id:'native-fixture-session'}));
 let answer='Native CLI reply 🌎';const block=value=>String.fromCharCode(96).repeat(3)+'opengrokbot-action\\n'+JSON.stringify(value)+'\\n'+String.fromCharCode(96).repeat(3);
 if(text.startsWith('You are Travel.'))answer='Specialist weekend plan';
 else if(text.endsWith('Create team fixture'))answer='Creating a specialist.\\n'+block({action:'create_bot',name:'Travel',purpose:'Plan trips without booking'})+'\\n'+block({action:'message_bot',to:'Travel',text:'Suggest a trip'});
 else if(text.endsWith('Create group fixture'))answer=block({action:'create_group',name:'Project',members:['Grok Bot','Travel']});
 console.log(JSON.stringify({type:'item.completed',item:{id:'answer',type:'agent_message',text:answer}}));});}
 `);
 await fs.writeFile(path.join(directory,'settings.json'),JSON.stringify({complete:false,selected:'',overrides:{codex:path.join(npmDir,'codex.cmd')},composioUserID:'native-test-unique-user'}));
 const launch=()=>electron.launch({args:[path.resolve(__dirname,'..')],env:{...process.env,OPENGROKBOT_TEST_DATA_DIR:directory}});
 try{
  desktop=await launch();const page=await desktop.firstWindow();page.setDefaultTimeout(20000);page.setDefaultNavigationTimeout(20000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.getByRole('heading',{name:'A free app for your AI CLIs'}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('heading',{name:'Choose an AI CLI'}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByText('Already installed:',{exact:false}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('button',{name:'Check sign-in',exact:true}).click();await page.getByText('Ready to continue.',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('textbox',{name:'Composio project API key'}).waitFor();
  await page.getByRole('button',{name:'Continue to chat',exact:true}).click();await page.getByRole('button',{name:'Start chatting',exact:true}).click();
  assert.equal(await page.locator('.bubble').count(),0);assert.equal(await page.locator('#bot-list .bot-row').count(),0);
  assert.equal(await page.evaluate(()=>typeof window.require),'undefined');assert.equal((await page.evaluate(()=>window.desktop.save({version:0}))).ok,false);
  await page.locator('#draft').fill('Native IPC persistence smoke test');await page.locator('#draft').press('Enter');await page.locator('.bubble').getByText('Native CLI reply 🌎',{exact:true}).waitFor();
  await page.waitForFunction(()=>!document.querySelector('#messages')?.textContent.includes('Stop response'));
  await page.locator('#draft').fill('Remember this conversation');await page.locator('#draft').press('Enter');
  await page.waitForFunction(()=>document.querySelectorAll('.bubble').length===4&&!document.querySelector('#messages').textContent.includes('Stop response'));
  const calls=(await fs.readFile(path.join(directory,'invocations.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);assert.equal(calls.length,2);assert.ok(calls[1].args.includes('resume'));assert.ok(calls[1].args.includes('native-fixture-session'));assert.ok(calls[1].text.endsWith('Remember this conversation'));assert.ok(!calls[0].args.join(' ').includes('Native IPC'));
  await page.locator('#draft').fill('slow stop test');await page.locator('#draft').press('Enter');await page.locator('.bubble').getByText('Partial fixture reply',{exact:true}).waitFor();await page.getByRole('button',{name:'Stop response',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('#messages').textContent.includes('Stop response'));
  assert.equal((await page.evaluate(()=>window.desktop.load())).value.entries.at(-1).state,'stopped');
  await page.locator('#draft').fill('Keep draft');await page.locator('#chat-heading').click();await page.getByRole('heading',{name:'Providers & models'}).waitFor();assert.equal(await page.locator('#draft').inputValue(),'Keep draft');
  await page.getByRole('button',{name:'Load Codex models',exact:true}).click();await page.getByRole('combobox',{name:'Codex model',exact:true}).selectOption('fixture-model');
  const mainID=(await page.evaluate(()=>window.desktop.load())).value.bots[0].id;
  assert.equal((await page.evaluate(id=>window.desktop.configureBot(id,{providers:[{provider:'codex',model:'fixture-model'},{provider:'claude',model:'must-not-run'}],activeProvider:'codex',replyMode:'all'}),mainID)).ok,true);
  await page.getByRole('button',{name:'Library',exact:true}).click();await page.getByRole('heading',{name:'No files yet'}).waitFor();await page.getByRole('button',{name:'Computer',exact:true}).click();await page.getByText('Runs on this device',{exact:true}).waitFor();await page.keyboard.press('Escape');
  await page.locator('#draft').fill('Create team fixture');await page.locator('#draft').press('Enter');await page.locator('.bubble').getByText('Specialist weekend plan',{exact:true}).waitFor();
  await page.waitForFunction(async()=>{const r=await window.desktop.load();return r.value.teamMessages?.[0]?.status==='complete';});
  let saved=(await page.evaluate(()=>window.desktop.load())).value;const specialist=saved.bots.find(x=>x.name==='Travel');assert.ok(specialist);assert.equal(specialist.aiConfiguration.activeProvider,'codex');assert.equal(specialist.aiConfiguration.providers[0].model,'fixture-model');assert.equal(saved.entries.at(-1).senderBotID,specialist.id);
  await page.locator('#draft').fill('Create group fixture');await page.locator('#draft').press('Enter');await page.locator('#bot-list').getByRole('button',{name:'Project',exact:false}).click();
  await page.locator('#draft').fill('Group fixture request');await page.locator('#draft').press('Enter');await page.locator('.bubble').getByText('Specialist weekend plan',{exact:true}).waitFor();
  await page.waitForFunction(async()=>{const r=await window.desktop.load();return r.value.teamMessages.every(x=>x.status==='complete');});
  const teamCalls=(await fs.readFile(path.join(directory,'invocations.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);assert.equal(teamCalls.filter(x=>x.text.endsWith('Create team fixture')).length,1);assert.ok(teamCalls.filter(x=>x.args.includes('fixture-model')).length>=4);assert.ok(teamCalls.every(x=>!x.args.includes('must-not-run')));
  await page.locator('#primary-bot button').click();
  await page.evaluate(()=>window.desktop.windowAction('close')); // Closing the window must leave the app running in the tray.
  await desktop.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()[0].show());
  const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  const stored=await page.evaluate(([id,data])=>window.desktop.attachData(id,'image/png',data),[mainID,png]);assert.equal(stored.ok,true);
  const attached=await page.evaluate(([id,name])=>window.desktop.send(id,'Attachment fixture',crypto.randomUUID(),[name]),[mainID,stored.value]);assert.equal(attached.ok,true);
  assert.ok(attached.value.entries.some(x=>x.kind==='user'&&x.text.includes('Attachments/'+stored.value)));
  assert.equal((await page.evaluate(id=>window.desktop.send(id,'Bad attachment',crypto.randomUUID(),['../outside.txt']),mainID)).ok,false);
  await page.waitForFunction(async()=>{const r=await window.desktop.load();return r.value.entries.at(-1)?.state!=='streaming';});
  const secret='encrypted-smoke-'+Date.now();assert.equal((await page.evaluate(value=>window.desktop.vaultSave('Test secret',value),secret)).ok,true);
  const item=(await page.evaluate(()=>window.desktop.vaultList())).value.find(x=>x.title==='Test secret');assert.ok(item);assert.equal((await page.evaluate(id=>window.desktop.vaultRead(id),item.id)).value,secret);assert.equal((await fs.readFile(path.join(directory,'vault.json'),'utf8')).includes(secret),false);
  await page.evaluate(id=>window.desktop.vaultDelete(id),item.id);assert.deepEqual(errors,[]);
  await desktop.close();desktop=await launch();const relaunched=await desktop.firstWindow();await relaunched.locator('.bubble').getByText('Remember this conversation',{exact:true}).waitFor();
  console.log('PASS: native setup, single empty Bot, real fixture CLI subprocess, Unicode reply, resumed session, cancellation, isolated renderer, persistence, encrypted vault, tray close/reopen, and image attachments with path validation.');
 }finally{if(desktop)await desktop.close();await fs.rm(directory,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
