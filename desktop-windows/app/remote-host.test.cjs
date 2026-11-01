const test=require('node:test'),assert=require('node:assert/strict'),http=require('node:http'),{randomUUID}=require('node:crypto');
const {RemoteHost,pairing,localHost}=require('./remote-host.cjs');
const key='a'.repeat(64);
test('pairing keys stay in link fragments and public HTTP is refused',()=>{
 const link=new URL(pairing('https://desktop.example.ts.net:8443',key));assert.equal(link.hash,'#'+key);assert.equal(link.searchParams.get('host'),'https://desktop.example.ts.net:8443');
 for(const address of ['http://8.8.8.8','http://example.com','file:///tmp','https://user:password@example.com','https://example.com/path'])assert.throws(()=>pairing(address,key));
 for(const host of ['192.168.0.2','172.16.1.2','100.100.10.1','fd7a:115c:a1e0::1'])assert.equal(localHost(host),true);
 assert.equal(localHost('172.32.0.1'),false);assert.equal(localHost('100.128.1.2'),false);
});
test('real HTTP host authenticates snapshots, suppresses unchanged polls, executes once and rejects revoked keys and browser origins',async()=>{
 const host=new RemoteHost();let count=0,last;
 const port=await host.start({port:0,token:key,snapshot:()=>({protocolVersion:1,revision:'rev',workspace:{bots:[],entries:[]}}),execute:async command=>{count++;last=command;},models:()=>[],files:()=>[]});
 try{
  const base=`http://127.0.0.1:${port}`,headers={Authorization:'Bearer '+key};
  assert.equal((await fetch(base+'/v1/state')).status,401);
  const good=await fetch(base+'/v1/state',{headers});assert.equal(good.status,200);assert.equal((await good.json()).revision,'rev');
  assert.equal((await fetch(base+'/v1/state?since=rev',{headers})).status,204);
  assert.equal((await fetch(base+'/v1/state',{headers:{...headers,Origin:'https://evil.example'}})).status,400);
  const command={requestID:randomUUID(),action:'send',text:'café 🌎'};
  for(let i=0;i<2;i++)assert.equal((await fetch(base+'/v1/command',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify(command)})).status,200);
  assert.equal(count,1);assert.equal(last.text,'café 🌎');
  assert.equal((await fetch(base+'/v1/command',{method:'POST',headers,body:'x'.repeat(140000)})).status,413);
  host.token='b'.repeat(64);assert.equal((await fetch(base+'/v1/state',{headers})).status,401);assert.equal((await fetch(base+'/v1/state',{headers:{Authorization:'Bearer '+host.token}})).status,200);
 }finally{await host.stop();}
});
