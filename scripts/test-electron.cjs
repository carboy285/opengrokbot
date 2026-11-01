const {_electron:electron}=require('@playwright/test');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');const assert=require('node:assert/strict');
(async()=>{
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'opengrokbot-smoke-'));let desktop;
 const npmDir=path.join(directory,'fixture-bin'),packageDir=path.join(npmDir,'node_modules','@openai','codex');
 await fs.mkdir(packageDir,{recursive:true});await fs.writeFile(path.join(npmDir,'codex.cmd'),'@echo off\r\n');await fs.writeFile(path.join(packageDir,'package.json'),JSON.stringify({bin:{codex:'fixture.cjs'}}));
 await fs.writeFile(path.join(packageDir,'fixture.cjs'),`
 const fs=require('node:fs');const path=require('node:path');const args=process.argv.slice(2);
 if(args[0]==='--version'){console.log('codex-cli fixture');process.exit(0);}
 if(args[0]==='login'){process.exit(0);}
 let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',data=>text+=data);process.stdin.on('end',()=>{
 fs.appendFileSync(${JSON.stringify(path.join(directory,'invocations.jsonl'))},JSON.stringify({args,text})+'\\n');
 console.log(JSON.stringify({type:'thread.started',thread_id:'native-fixture-session'}));
 console.log(JSON.stringify({type:'item.completed',item:{id:'answer',type:'agent_message',text:'Native CLI reply 🌎'}}));});
 `);
 await fs.writeFile(path.join(directory,'settings.json'),JSON.stringify({complete:false,selected:'',overrides:{codex:path.join(npmDir,'codex.cmd')},composioUserID:'native-test-unique-user'}));
 const launch=()=>electron.launch({args:[path.resolve(__dirname,'..')],env:{...process.env,OPENGROKBOT_TEST_DATA_DIR:directory}});
 try{
  desktop=await launch();const page=await desktop.firstWindow();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.getByRole('heading',{name:'A free app for your AI CLIs'}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('heading',{name:'Choose an AI CLI'}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByText('Already installed:',{exact:false}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('button',{name:'Check sign-in',exact:true}).click();await page.getByText('Ready to continue.',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByRole('textbox',{name:'Composio project API key'}).waitFor();
  await page.getByRole('button',{name:'Continue to chat',exact:true}).click();await page.getByRole('button',{name:'Start chatting',exact:true}).click();
  assert.equal(await page.locator('.bubble').count(),0);assert.equal(await page.locator('#bot-list .bot-row').count(),0);
  assert.equal(await page.evaluate(()=>typeof window.require),'undefined');assert.equal((await page.evaluate(()=>window.desktop.save({version:0}))).ok,false);
  await page.locator('#draft').fill('Native IPC persistence smoke test');await page.locator('#draft').press('Control+Enter');await page.locator('.bubble').getByText('Native CLI reply 🌎',{exact:true}).waitFor();
  await page.waitForFunction(()=>!document.querySelector('#messages')?.textContent.includes('Stop response'));
  await page.locator('#draft').fill('Remember this conversation');await page.locator('#draft').press('Control+Enter');
  await page.waitForFunction(()=>document.querySelectorAll('.bubble').length===4&&!document.querySelector('#messages').textContent.includes('Stop response'));
  const calls=(await fs.readFile(path.join(directory,'invocations.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);assert.equal(calls.length,2);assert.ok(calls[1].args.includes('resume'));assert.ok(calls[1].args.includes('native-fixture-session'));assert.equal(calls[1].text,'Remember this conversation');assert.ok(!calls[0].args.join(' ').includes('Native IPC'));
  const secret='encrypted-smoke-'+Date.now();assert.equal((await page.evaluate(value=>window.desktop.vaultSave('Test secret',value),secret)).ok,true);
  const item=(await page.evaluate(()=>window.desktop.vaultList())).value.find(x=>x.title==='Test secret');assert.ok(item);assert.equal((await page.evaluate(id=>window.desktop.vaultRead(id),item.id)).value,secret);assert.equal((await fs.readFile(path.join(directory,'vault.json'),'utf8')).includes(secret),false);
  await page.evaluate(id=>window.desktop.vaultDelete(id),item.id);assert.deepEqual(errors,[]);
  await desktop.close();desktop=await launch();const relaunched=await desktop.firstWindow();await relaunched.locator('.bubble').getByText('Remember this conversation',{exact:true}).waitFor();
  console.log('PASS: native setup, single empty Bot, real fixture CLI subprocess, Unicode reply, resumed session, isolated renderer, persistence, encrypted vault.');
 }finally{if(desktop)await desktop.close();await fs.rm(directory,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
