const {trustedURL,variable}=require('./composio.cjs');
const readline=require('node:readline');
function createProxy(endpoint,{fetcher=fetch,send}={}){
if(!trustedURL(String(endpoint)))throw new Error('Invalid Composio session.');
let sessionID,protocolVersion;
return async function handle(line){
  let value;try{value=JSON.parse(line);}catch{return;}
  if(!value||value.jsonrpc!=='2.0')return;
  const reply=text=>{
    let message;try{message=JSON.parse(text);}catch{return false;}
    if(message.jsonrpc!=='2.0'||message.method||message.id!==value.id)return false;
    if(typeof message.result?.protocolVersion==='string')protocolVersion=message.result.protocolVersion;
    send(message);return true;
  };
  try{
    if(line.length>4000000)throw new Error();
    const headers={'Content-Type':'application/json',Accept:'application/json, text/event-stream'};
    if(sessionID)headers['Mcp-Session-Id']=sessionID;if(protocolVersion)headers['MCP-Protocol-Version']=protocolVersion;
    const response=await fetcher(endpoint,{method:'POST',body:line,headers,redirect:'error',signal:AbortSignal.timeout(180000)});
    if(!response.ok)throw new Error();
    sessionID=response.headers.get('mcp-session-id')||sessionID;
    if(response.status===202||value.id===undefined){await response.body?.cancel();return;}
    if(response.headers.get('content-type')?.includes('text/event-stream')){
      let event='',pending='',size=0;const decoder=new TextDecoder();
      for await(const chunk of response.body){
        size+=chunk.length;if(size>16000000)throw new Error();pending+=decoder.decode(chunk,{stream:true});
        let end;while((end=pending.indexOf('\n'))>=0){const part=pending.slice(0,end).replace(/\r$/,'');pending=pending.slice(end+1);
          if(!part){if(event&&reply(event)){await response.body.cancel().catch(()=>{});return;}event='';}
          else if(part.startsWith('data:'))event+=(event?'\n':'')+part.slice(5).trimStart();
        }
      }
      if(event&&reply(event))return;throw new Error();
    }
    const text=await response.text();if(text.length>16000000||!reply(text))throw new Error();
  }catch{
    if(value.id!==undefined)send({jsonrpc:'2.0',id:value.id,error:{code:-32000,message:'Composio tool request failed. Refresh connections in OpenGrokBot and try again.'}});
  }
};
}
module.exports={createProxy};
if(require.main===module){
const endpoint=trustedURL(process.env[variable]);if(!endpoint)process.exit(1);
const handle=createProxy(endpoint,{send:value=>process.stdout.write(JSON.stringify(value)+'\n')});
// Sequential requests preserve initialization and MCP session headers.
(async()=>{for await(const line of readline.createInterface({input:process.stdin,crlfDelay:Infinity}))await handle(line);})();

}
