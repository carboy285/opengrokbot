const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const { StringDecoder } = require('node:string_decoder');
const { randomUUID } = require('node:crypto');

const providers = [
  { id:'codex',name:'Codex',install:'npm install -g @openai/codex',login:'codex login',guide:'https://github.com/openai/codex#quickstart',package:'@openai/codex' },
  { id:'claude',name:'Claude Code',install:'npm install -g @anthropic-ai/claude-code',login:'claude',guide:'https://code.claude.com/docs/en/setup',package:'@anthropic-ai/claude-code' },
  { id:'grok',name:'Grok Build',install:null,login:'grok',guide:'https://github.com/xai-org/grok-build#installing-the-released-binary' },
  { id:'opencode',name:'OpenCode',install:'npm install -g opencode-ai',login:'opencode auth login',guide:'https://opencode.ai/docs/',package:'opencode-ai' },
  { id:'gemini',name:'Gemini CLI',install:'npm install -g @google/gemini-cli',login:'gemini',guide:'https://geminicli.com/docs/get-started/installation/',package:'@google/gemini-cli' }
];
function provider(id) { const value=providers.find(x=>x.id===id);if(!value)throw new Error('Unknown CLI');return value; }
function directories() {
  const home=os.homedir(); const values=(process.env.PATH||process.env.Path||'').split(path.delimiter).filter(Boolean);
  if(process.platform==='win32') values.push(path.join(process.env.APPDATA||home,'npm'),path.join(home,'.local','bin'));
  else {
    values.push('/opt/homebrew/bin','/usr/local/bin',...['.local/bin','.npm-global/bin','.bun/bin','.opencode/bin','.volta/bin','.asdf/shims'].map(x=>path.join(home,x)));
    try {values.push(...fs.readdirSync(path.join(home,'.nvm/versions/node')).sort((a,b)=>b.localeCompare(a,undefined,{numeric:true})).slice(0,6).map(x=>path.join(home,'.nvm/versions/node',x,'bin')));}catch{}
  }
  return [...new Set(values)];
}
function invocation(file, definition) {
  if(!path.isAbsolute(file))throw new Error('Executable path must be absolute');
  if(process.platform==='win32' && /\.(cmd|bat)$/i.test(file)) {
    // Resolve known npm launchers without passing any prompt through cmd.exe.
    if(!definition.package)throw new Error('Choose the native executable');
    const packageDir=path.join(path.dirname(file),'node_modules',definition.package);
    const metadata=JSON.parse(fs.readFileSync(path.join(packageDir,'package.json'),'utf8'));
    const entry=typeof metadata.bin==='string'?metadata.bin:metadata.bin?.[definition.id];
    if(typeof entry!=='string')throw new Error('Missing npm entry point');
    const script=path.resolve(packageDir,entry);
    if(!script.startsWith(packageDir+path.sep)||!fs.statSync(script).isFile())throw new Error('Invalid npm entry point');
    return {executable:process.execPath,prefix:[script],extraEnv:{ELECTRON_RUN_AS_NODE:'1'}};
  }
  fs.accessSync(file,process.platform==='win32'?fs.constants.F_OK:fs.constants.X_OK);
  return {executable:file,prefix:[],extraEnv:{}};
}
function environment(extra={}) {return {...process.env,PATH:directories().join(path.delimiter),...extra};}
function capture(installation,args,timeout=4000) {
  return new Promise(resolve=>{
    let child, output='', done=false;
    const finish=(exit)=>{if(done)return;done=true;clearTimeout(timer);resolve({exit,text:output.slice(0,4096)});};
    const timer=setTimeout(()=>{if(child)child.kill();finish(-1);},timeout);
    try {
      const call=invocation(installation.path,provider(installation.provider));
      child=spawn(call.executable,[...call.prefix,...args],{env:environment(call.extraEnv),stdio:['ignore','pipe','pipe'],windowsHide:true,shell:false});
      child.stdout.on('data',data=>{if(output.length<4096)output+=data.toString('utf8');});child.stderr.resume();
      child.on('error',()=>finish(-1));child.on('close',code=>finish(code??-1));
    }catch{finish(-1);}
  });
}
async function discover(overrides={}) {
  const result=[];
  for(const definition of providers) {
    const extensions=process.platform==='win32'?['.exe','.cmd','']:[''];
    const candidates=overrides[definition.id]?[overrides[definition.id]]:directories().flatMap(dir=>extensions.map(ext=>path.join(dir,definition.id+ext)));
    for(const file of candidates) {
      try {invocation(file,definition);}catch{continue;}
      const installation={id:definition.id+':'+file,provider:definition.id,name:definition.name,path:file};
      const version=await capture(installation,['--version']);
      if(version.exit===0){result.push({...installation,version:version.text.trim().slice(0,100)});break;}
    }
  }
  return result;
}
function command(id,session,promptFile) {
  let args=[];
  if(id==='codex') {args=['exec','--sandbox','read-only'];if(session)args.push('resume',session);args.push('--json','--skip-git-repo-check','-');}
  else if(id==='claude'){args=['-p','--output-format','stream-json','--verbose','--include-partial-messages'];if(session)args.push('--resume',session);}
  else if(id==='grok'){args=['--prompt-file',promptFile,'--output-format','streaming-messages-json','--include-partial-messages'];if(session)args.push('--resume',session);}
  else if(id==='opencode'){args=['run','--format','json'];if(session)args.push('--session',session);}
  else if(id==='gemini'){args=['--output-format','stream-json'];if(session)args.push('--resume',session);}
  else throw new Error('Unknown provider');
  return args;
}
class EventParser {
  constructor(){this.text='';this.order=[];this.parts=new Map();}
  parse(line) {
    let value;try{value=JSON.parse(line);}catch{return [];}
    const events=[];const session=value.thread_id||value.session_id||value.sessionID;
    if(typeof session==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,199}$/.test(session))events.push({type:'session',id:session});
    if(value.type==='turn.failed'||(value.type==='result'&&(value.is_error===true||value.status==='error')))return [...events,{type:'failed'}];
    if(typeof value.parent_tool_use_id==='string')return events;
    const item=value.item;
    if((value.type==='item.completed'||value.type==='item.updated')&&item?.type==='agent_message'&&typeof item.text==='string')this.part(item.id||'answer',item.text);
    else if(value.type==='text'&&typeof value.part?.text==='string')this.part(value.part.id||'answer',value.part.text);
    else if(value.type==='stream_event'&&value.event?.delta?.type==='text_delta'&&typeof value.event.delta.text==='string')this.text+=value.event.delta.text;
    else if(value.type==='assistant'&&!this.text&&Array.isArray(value.message?.content))this.text=value.message.content.filter(x=>x.type==='text').map(x=>x.text||'').join('\n');
    else if(value.type==='message'&&value.role==='assistant'&&typeof value.content==='string')this.text=value.delta?this.text+value.content:value.content;
    else if(value.type==='result'&&typeof value.result==='string'&&value.result)this.text=value.result;
    else return events;
    return [...events,{type:'text',text:this.text}];
  }
  part(id,text){if(!this.parts.has(id))this.order.push(id);this.parts.set(id,text);this.text=this.order.map(x=>this.parts.get(x)).join('\n\n');}
}
function runCLI({installation,prompt,session,directory,onEvent,timeout=600000}) {
  let child, cancelled=false, timedOut=false, cancelTimer;
  const cancel=()=>{cancelled=true;if(child&&!child.killed){child.kill('SIGINT');cancelTimer=setTimeout(()=>{if(child.exitCode===null)child.kill('SIGKILL');},2000);cancelTimer.unref();}};
  const done=(async()=>{
    await fsp.mkdir(directory,{recursive:true});
    const promptFile=path.join(directory,'.prompt-'+randomUUID()+'.txt');
    if(installation.provider==='grok')await fsp.writeFile(promptFile,prompt,{mode:0o600});
    try {
      if(cancelled)throw new Error('Response stopped.');
      const call=invocation(installation.path,provider(installation.provider));
      const parser=new EventParser();let pending='',bytes=0,stderr='',protocolFailed=false;
      return await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>{timedOut=true;cancel();},timeout);timer.unref();
        const clean=()=>{clearTimeout(timer);clearTimeout(cancelTimer);};
        child=spawn(call.executable,[...call.prefix,...command(installation.provider,session,promptFile)],{cwd:directory,env:environment(call.extraEnv),stdio:['pipe','pipe','pipe'],windowsHide:true,shell:false});
        const decoder=new StringDecoder('utf8');
        const consume=line=>{for(const event of parser.parse(line)){if(event.type==='failed')protocolFailed=true;onEvent(event);}};
        child.stdout.on('data',data=>{
          bytes+=data.length;pending+=decoder.write(data);
          if(bytes>32*1024*1024||pending.length>2*1024*1024){protocolFailed=true;cancel();return;}
          let index;while((index=pending.indexOf('\n'))>=0){const line=pending.slice(0,index);pending=pending.slice(index+1);consume(line);}
        });
        child.stderr.on('data',data=>{if(stderr.length<32768)stderr+=data.toString('utf8');});
        child.stdin.on('error',()=>{});
        child.on('error',()=>{clean();reject(new Error('The CLI could not start. Check its installation path in setup.'));});
        child.on('close',code=>{
          clean();pending+=decoder.end();if(pending.trim())consume(pending);
          if(timedOut)return reject(new Error('The CLI did not finish within ten minutes. Check its connection and retry.'));
          if(cancelled)return reject(new Error('Response stopped.'));
          if(code!==0||protocolFailed){const auth=/not logged in|unauthorized|authentication|sign in|401/i.test(stderr);return reject(new Error(auth?'Sign in through your CLI, then retry.':`The CLI stopped (exit ${code??'unknown'}). Check its login and configuration in Terminal.`));}
          if(!parser.text.trim())return reject(new Error('The CLI did not return a supported response. Update it or choose another installation.'));
          resolve(parser.text);
        });
        child.stdin.end(installation.provider==='grok'?'':prompt);
      });
    } finally {if(installation.provider==='grok')await fsp.rm(promptFile,{force:true}).catch(()=>{});}
  })();
  return {done,cancel};
}
module.exports={providers,discover,capture,command,EventParser,runCLI,invocation};
