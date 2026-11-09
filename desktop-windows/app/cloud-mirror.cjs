const {randomUUID}=require('node:crypto');
const os=require('node:os');
const {identity,seal,open,fingerprint}=require('./cloud-host.cjs');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
class CloudMirror{
 constructor(cloud,changed,{slot=''}={}){this.slot=slot;this.cloud=cloud;this.changed=changed;this.generation=0;this.snapshot=null;this.devices=[];this.peer=null;this.phase='Choose a computer';this.inFlight=false;this.accountGeneration=cloud.accountGeneration;this.lastError='';this.receivedAt=null;this.stage='idle';}
 accountChanged(){if(this.accountGeneration!==this.cloud.accountGeneration){this.accountGeneration=this.cloud.accountGeneration;this.devices=[];this.stop();}}
 get owner(){return this.cloud.data.session?.user.id;}
 get local(){return this.cloud.data.controllers?.[this.owner?.toLowerCase()+this.slot];}
 status(){return {phase:this.phase,stage:this.stage,error:this.lastError,receivedAt:this.receivedAt,host:this.peer?.name,hostID:this.peer?.id,hosts:newestByName(this.devices.filter(x=>x.kind==='host'&&x.id!==this.cloud.local?.id)).map(({id,name,available,last_seen})=>({id,name,online:available&&Date.now()-Date.parse(last_seen)<90000})),fingerprint:this.local?fingerprint(this.local.publicKey):null,snapshot:this.snapshot};}
 emit(){this.changed(this.status());}
 async discover(){
  if(!this.owner)throw new Error('Sign in under Settings → Computer first.');
  const owner=this.owner,epoch=this.cloud.accountGeneration;
  this.cloud.data.controllers||={};this.cloud.data.controllers[owner.toLowerCase()+this.slot]||=identity();await this.cloud.persist();
  const local=this.local;
  await this.cloud.request('/rest/v1/rpc/opengrok_register_device',{device_id:local.id,device_name:os.hostname()+(this.slot?' · remote VM':' · remote view'),device_kind:'controller',device_key:local.publicKey,is_available:'true'});
  const devices=await this.cloud.request('/rest/v1/opengrok_devices?select=id,name,kind,public_key,last_seen,available&order=last_seen.desc',null,'GET');
  if(epoch!==this.cloud.accountGeneration||owner!==this.owner)throw new Error('The account changed.');
  if(!Array.isArray(devices))throw new Error('Invalid device list.');this.devices=devices;this.emit();return this.status();
 }
 async select(id){
  this.stop();const epoch=this.generation,account=this.cloud.accountGeneration;await this.discover();if(epoch!==this.generation||account!==this.cloud.accountGeneration)throw new Error('The selected computer changed.');const peer=this.devices.find(x=>x.kind==='host'&&x.id===id&&x.id!==this.cloud.local?.id);if(!peer)throw new Error('Choose another computer on this account.');
  const key=this.owner.toLowerCase()+'|'+peer.id.toLowerCase();this.cloud.data.mirrorPins||={};const pin=this.cloud.data.mirrorPins[key];if(pin&&pin!==peer.public_key)throw new Error('This computer’s encryption identity changed. Re-register it on the server before connecting.');
  this.cloud.data.mirrorPins[key]=peer.public_key;await this.cloud.persist();if(epoch!==this.generation||account!==this.cloud.accountGeneration)throw new Error('The selected computer changed.');this.peer=peer;const generation=++this.generation;this.phase='Requesting Bots from '+peer.name+'…';this.stage='requesting';this.lastError='';this.emit();this.worker(generation,account).catch(()=>{});return this.status();
 }
/** Connects to one computer without starting the live Bot-list worker. Used for sending commands (such as running something in a shared VM). */
 async attach(id){
  this.stop();const account=this.cloud.accountGeneration;await this.discover();
  const peer=this.devices.find(x=>x.kind==='host'&&x.id===id&&x.id!==this.cloud.local?.id);if(!peer)throw new Error('That computer is not available right now. Make sure it is awake with OpenGrokBot open and remote access on.');
  const key=this.owner.toLowerCase()+'|'+peer.id.toLowerCase();this.cloud.data.mirrorPins||={};const pin=this.cloud.data.mirrorPins[key];
  if(pin&&pin!==peer.public_key)throw new Error('This computer’s encryption identity changed. Re-register it on the server before connecting.');
  this.cloud.data.mirrorPins[key]=peer.public_key;await this.cloud.persist();
  if(account!==this.cloud.accountGeneration)throw new Error('The account changed.');
  this.peer=peer;this.generation++;return peer;
 }
 async fetch(target,command){
  const generation=this.generation,account=this.cloud.accountGeneration,owner=this.owner,peer=this.peer,local=this.local;
  const current=()=>generation===this.generation&&account===this.cloud.accountGeneration&&this.owner===owner;
  while(this.inFlight){await sleep(50);if(!current())throw new Error('The selected computer changed.');}
  if(!peer||!local||!current())throw new Error('Choose a computer first.');this.inFlight=true;
  try{
   const id=randomUUID(),body={method:command?'POST':'GET',target,body:command?Buffer.from(JSON.stringify(command)).toString('base64'):''};
   const payload=seal(local,peer,owner,id,body,'request');await this.cloud.request('/rest/v1/rpc/opengrok_send',{packet_id:id,from_device:local.id,to_device:peer.id,packet_kind:'request',payload});
   const deadline=Date.now()+(command?35000:12000);let nextResend=Date.now()+2000;
   while(current()&&Date.now()<deadline){
    const packets=await this.cloud.request('/rest/v1/rpc/opengrok_poll',{device_id:local.id});
    if(!Array.isArray(packets))throw new Error('Invalid mailbox response.');
    for(const packet of packets){
     if(!current())throw new Error('The selected computer changed.');
     if(packet.id!==id||packet.sender!==peer.id||packet.kind!=='response'){await this.cloud.request('/rest/v1/rpc/opengrok_ack',{device_id:local.id,packet_id:packet.id,packet_kind:packet.kind});continue;}
     let response;try{response=open(local,peer,owner,packet,'response');}catch{await this.cloud.request('/rest/v1/rpc/opengrok_ack',{device_id:local.id,packet_id:packet.id,packet_kind:packet.kind});throw new Error('The server reply could not be verified. Quit older app copies on the host, reopen 0.7.2 and reconnect.');}await this.cloud.request('/rest/v1/rpc/opengrok_ack',{device_id:local.id,packet_id:packet.id,packet_kind:packet.kind});
     if(!current())throw new Error('The selected computer changed.');
     const value=response.body?JSON.parse(Buffer.from(response.body,'base64').toString('utf8')):null;
     if(response.status===403)throw new Error('Approve this computer on the server after comparing the controller fingerprint below.');
     if(response.status<200||response.status>=300)throw new Error(value?.error||'The server could not complete the request.');return {status:response.status,value};
    }
    if(Date.now()>=nextResend){await this.cloud.request('/rest/v1/rpc/opengrok_send',{packet_id:id,from_device:local.id,to_device:peer.id,packet_kind:'request',payload});nextResend=Date.now()+3000;}
    await sleep(150);
   }
   throw new Error('The server did not respond. Keep it awake with remote access enabled.');
  }finally{this.inFlight=false;}
 }
 async worker(generation,account){
  let heartbeat=0;
  while(generation===this.generation&&account===this.cloud.accountGeneration&&this.peer){
   try{
    if(Date.now()>heartbeat){await this.discover();heartbeat=Date.now()+20000;}
    const {status,value}=await this.fetch('/v1/state'+(this.snapshot?'?since='+encodeURIComponent(this.snapshot.revision):'?overview=true'));
    if(generation!==this.generation||account!==this.cloud.accountGeneration)return;
    if(status===204&&!this.snapshot)throw new Error('The server did not provide an initial workspace. Reconnect to request a fresh copy.');
    if(status!==204){
     const patch=value?.snapshot?value:value?.workspace?{snapshot:value,removedEntries:[]}:null;
     if(!patch?.snapshot?.workspace||!Array.isArray(patch.snapshot.workspace.bots)||!Array.isArray(patch.snapshot.workspace.entries))throw new Error('Invalid server workspace.');
     const next=patch.snapshot;
     if(patch.baseRevision){if(this.snapshot?.revision!==patch.baseRevision){this.snapshot=null;continue;}const changes=new Map(next.workspace.entries.map(x=>[x.id,x])),removed=new Set(patch.removedEntries||[]),old=this.snapshot.workspace.entries,existing=new Set(old.map(x=>x.id));next.workspace.entries=old.filter(x=>!removed.has(x.id)).map(x=>changes.get(x.id)||x).concat(next.workspace.entries.filter(x=>!existing.has(x.id)));}
     const ids=new Set(next.workspace.bots.map(x=>x.id)),entryIDs=new Set(next.workspace.entries.map(x=>x.id));if(ids.size!==next.workspace.bots.length||entryIDs.size!==next.workspace.entries.length||next.workspace.entries.some(x=>!ids.has(x.botID)))throw new Error('Inconsistent server workspace.');
     this.snapshot=next;
    }
    this.phase='Connected to '+this.peer.name+(this.snapshot?.overview?' · loading chat history…':'');this.stage='connected';this.lastError='';this.receivedAt=new Date().toISOString();this.emit();
   }catch(error){if(generation!==this.generation||account!==this.cloud.accountGeneration)return;this.lastError=error.message;this.phase=error.message+' Retrying…';this.stage=/[Aa]pprove/.test(error.message)?'approval-required':'retrying';this.emit();await sleep(1500);}
   await sleep(400);
  }
  if(account!==this.cloud.accountGeneration)this.stop();
 }
 async command(command){const result=await this.fetch('/v1/command',{...command,requestID:command.requestID||randomUUID()});return result.value;}
 async pin(bot,value){if(!this.peer||!this.owner)throw new Error('Choose a server.');await this.cloud.request('/rest/v1/rpc/opengrok_set_bot_pin',{host_device:this.peer.id,bot,pinned:value});return true;}
 stop(){this.generation++;this.peer=null;this.snapshot=null;this.phase='Choose a computer';this.stage='idle';this.lastError='';this.receivedAt=null;this.emit();}
}
/** The same computer can be registered twice (after a reinstall): keep only its most recently seen entry. */
function newestByName(list){const best=new Map();for(const device of list){const known=best.get(device.name);if(!known||Date.parse(device.last_seen)>Date.parse(known.last_seen))best.set(device.name,device);}return list.filter(device=>best.get(device.name)===device);}
module.exports={CloudMirror};
