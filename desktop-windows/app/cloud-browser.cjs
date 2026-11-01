// Browsers run at Browserbase, never in an Electron window or the user's browser.
async function readPage(config,botID,address){
 if(!config?.key||!config.project)throw new Error('Cloud browser not connected. Open Settings → Computer and connect a Browserbase account.');
 let url;try{url=new URL(address);}catch{throw new Error('Choose an HTTPS page.');}
 if(url.protocol!=='https:'||url.username||url.password||address.length>4000)throw new Error('Choose an HTTPS page without embedded credentials.');
 const api=async(route,body)=>{const response=await fetch('https://api.browserbase.com/v1/'+route,{method:'POST',headers:{'Content-Type':'application/json','X-BB-API-Key':config.key},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});if(!response.ok)throw new Error('Browserbase could not complete the request. Check the project key, quota and service status.');return response.json();};
 const session=await api('sessions',{projectId:config.project,timeout:60,keepAlive:false,browserSettings:{recordSession:false,logSession:false},userMetadata:{botID}});
 let socket,timer;
 try{
  const endpoint=new URL(session.connectUrl);if(endpoint.protocol!=='wss:'||endpoint.hostname!=='connect.browserbase.com')throw new Error('Invalid cloud browser connection.');
  socket=new WebSocket(endpoint);let next=0,loaded=false;const pending=new Map();let loadResolve;
  const load=new Promise(resolve=>{loadResolve=resolve;});
  socket.addEventListener('message',event=>{try{const packet=JSON.parse(event.data);if(packet.method==='Page.loadEventFired'){loaded=true;loadResolve();}if(pending.has(packet.id)){const pair=pending.get(packet.id);pending.delete(packet.id);packet.error?pair.reject(new Error('The cloud browser could not read this page.')):pair.resolve(packet.result||{});}}catch{}});
  const failed=()=>{for(const pair of pending.values())pair.reject(new Error('Cloud browser connection ended.'));pending.clear();loadResolve();};socket.addEventListener('close',failed);socket.addEventListener('error',failed);
  const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{socket.close();reject(new Error('The cloud browser timed out.'));},35000);});
  const work=(async()=>{
   await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',()=>reject(new Error('Could not connect to cloud browser.')),{once:true});});
   const call=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
   const target=await call('Target.createTarget',{url:'about:blank'}),attached=await call('Target.attachToTarget',{targetId:target.targetId,flatten:true}),id=attached.sessionId;
   await call('Page.enable',{},id);loaded=false;const nav=await call('Page.navigate',{url:url.href},id);if(nav.errorText)throw new Error('This page could not be opened.');if(!loaded)await load;
   const result=await call('Runtime.evaluate',{expression:'JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText||"").slice(0,16000),links:[...document.links].slice(0,25).map(a=>({text:a.innerText.slice(0,100),url:a.href}))})',returnByValue:true},id);
   if(result.exceptionDetails||typeof result.result?.value!=='string')throw new Error('This page could not be read.');return result.result.value;
  })();
  return await Promise.race([work,deadline]);
 }finally{clearTimeout(timer);socket?.close();if(/^[a-z0-9-]{1,100}$/i.test(session.id))await api('sessions/'+session.id,{status:'REQUEST_RELEASE'}).catch(()=>{});}
}
module.exports={readPage};
