// Regression check: the voice button must start dictation under the renderer's strict CSP.
// An inline onclick="toggleVoice()" is blocked by `script-src 'self'`, and toggleVoice lives
// inside an ES module, so the button has to be wired from app.js with addEventListener.
const {chromium}=require('@playwright/test');const {spawn}=require('node:child_process');const assert=require('node:assert/strict');
const {previewWorkspace}=require('../desktop-windows/app/workspace.cjs');
(async()=>{
 const server=spawn('python3',['-m','http.server','4175','--bind','127.0.0.1','--directory','desktop-windows/renderer'],{stdio:'ignore'});let browser;
 try{
  await new Promise((resolve,reject)=>{server.once('error',reject);setTimeout(resolve,300);});browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1370,height:940}});page.setDefaultTimeout(10000);
  const cspErrors=[],pageErrors=[];
  page.on('console',message=>{if(/Content Security Policy/i.test(message.text()))cspErrors.push(message.text());});
  page.on('pageerror',error=>pageErrors.push(error.message));
  await page.addInitScript(workspace=>{
   const status={providers:[],installed:[{id:'codex:fixture',provider:'codex',name:'Codex',path:'/fixture/codex',version:'fixture'}],selected:'codex:fixture',complete:true};
   window.desktop={load:async()=>({ok:true,value:workspace}),save:async value=>({ok:true,value}),scanCLIs:async()=>({ok:true,value:status}),setupStatus:async()=>({ok:true,value:status}),onChange(){}};
   window.cspViolations=[];document.addEventListener('securitypolicyviolation',event=>window.cspViolations.push(event.violatedDirective+' '+event.blockedURI));
   // Fake microphone so the test observes toggleVoice without real hardware.
   window.voiceCalls={getUserMedia:0,start:0,stop:0};
   const stream={getTracks:()=>[{stop(){}}]};
   Object.defineProperty(navigator,'mediaDevices',{configurable:true,value:{getUserMedia:async()=>{window.voiceCalls.getUserMedia++;return stream;}}});
   window.MediaRecorder=class{constructor(){this.state='inactive';}start(){this.state='recording';window.voiceCalls.start++;}stop(){this.state='inactive';window.voiceCalls.stop++;this.ondataavailable?.({data:new Blob()});this.onstop?.();}};
  },previewWorkspace());
  await page.goto('http://127.0.0.1:4175');const voice=page.locator('#voice-button');await voice.waitFor();
  assert.deepEqual(await page.evaluate(()=>[...document.querySelectorAll('*')].flatMap(el=>[...el.attributes].filter(a=>/^on/i.test(a.name)).map(a=>el.tagName+' '+a.name))),[],'Inline event handlers are blocked by the CSP; wire them in app.js');
  await voice.click();await page.waitForFunction(()=>document.getElementById('voice-button').classList.contains('recording'));
  assert.deepEqual(await page.evaluate(()=>window.voiceCalls),{getUserMedia:1,start:1,stop:0},'Clicking the voice button must reach toggleVoice and start recording');
  assert.equal(await voice.textContent(),'●');
  await voice.click();await page.waitForFunction(()=>!document.getElementById('voice-button').classList.contains('recording'));
  assert.equal((await page.evaluate(()=>window.voiceCalls)).stop,1,'Clicking again must stop recording');
  assert.match(await page.locator('#draft').inputValue(),/^\[Voice input\] /);
  assert.deepEqual(cspErrors,[],'No CSP violations in the console');assert.deepEqual(await page.evaluate(()=>window.cspViolations),[],'No securitypolicyviolation events');assert.deepEqual(pageErrors,[]);
  console.log('PASS: voice button starts and stops dictation under the strict renderer CSP with no inline handlers or CSP violations.');
 }finally{if(browser)await browser.close();server.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
