const {spawn}=require('node:child_process');const {StringDecoder}=require('node:string_decoder');
const cli=require('./local-cli.cjs');
const valid=value=>typeof value==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9_.\/:@+-]{0,199}$/.test(value);
async function listModels(installation){
 if(cli.isLocal(installation.provider)){const models=await require('./local-llm.cjs').listModels(installation.path,{timeout:4000});return (models||[]).filter(valid).map(id=>({id,name:id}));}
 if(installation.provider==='opencode'){
  const response=await cli.capture(installation,['models'],12000,262144);
  return response.exit===0?[...new Set(response.text.split(/\r?\n/).filter(x=>x.includes('/')&&valid(x)))].sort().slice(0,1000).map(id=>({id,name:id})):[];
 }
 if(installation.provider!=='codex')return [];
 return new Promise(resolve=>{
  let child,complete=false,pending='',size=0;const decoder=new StringDecoder('utf8');
  const finish=value=>{if(complete)return;complete=true;clearTimeout(timer);child?.stdin.end();child?.kill();const force=setTimeout(()=>{if(child&&child.exitCode===null)child.kill('SIGKILL');},1000);force.unref();resolve(value);};
  const timer=setTimeout(()=>finish([]),12000);timer.unref();
  const send=value=>child.stdin.write(JSON.stringify(value)+'\n');
  try{
   const call=cli.invocation(installation.path,cli.providers.find(x=>x.id===installation.provider));
   child=spawn(call.executable,[...call.prefix,'app-server'],{env:cli.environment(call.extraEnv),stdio:['pipe','pipe','ignore'],shell:false,windowsHide:true});
   child.stdin.on('error',()=>{});child.on('error',()=>finish([]));child.on('close',()=>finish([]));
   child.stdout.on('data',chunk=>{
    size+=chunk.length;if(size>2000000)return finish([]);pending+=decoder.write(chunk);let end;
    while((end=pending.indexOf('\n'))>=0){const line=pending.slice(0,end);pending=pending.slice(end+1);let value;try{value=JSON.parse(line);}catch{continue;}
     if(value.id===1){if(value.error)return finish([]);send({method:'initialized'});send({id:2,method:'model/list',params:{limit:100}});}
     else if(value.id===2){const data=value.result?.data||[];return finish(data.filter(x=>valid(x.model||x.id)).map(x=>({id:x.model||x.id,name:typeof x.displayName==='string'?x.displayName:(x.model||x.id)})));}
    }
   });
   send({id:1,method:'initialize',params:{clientInfo:{name:'opengrokbot-models',version:'0.4.0'}}});
  }catch{finish([]);}
 });
}
module.exports={listModels};
