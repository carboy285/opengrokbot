const http=require('node:http'),crypto=require('node:crypto');
function localHost(host){
 const h=host.toLowerCase().replace(/^\[|\]$/g,'');if(h==='localhost'||h.endsWith('.local')||h==='::1'||/^(fc|fd|fe80:).*:/.test(h))return true;
 if(!/^\d{1,3}(\.\d{1,3}){3}$/.test(h))return false;const n=h.split('.').map(Number);if(n.some(x=>x>255))return false;
 return n[0]===10||n[0]===127||n[0]===192&&n[1]===168||n[0]===172&&n[1]>=16&&n[1]<=31||n[0]===169&&n[1]===254||n[0]===100&&n[1]>=64&&n[1]<=127;
}
function pairing(address,token){const url=new URL(address);if(url.username||url.password||url.search||url.hash||url.pathname!=='/'||!url.hostname||!['https:','http:'].includes(url.protocol)||url.protocol==='http:'&&!localHost(url.hostname)||!/^[A-Za-z0-9_-]{43,128}$/.test(token))throw new Error('Use HTTPS, or a private Wi-Fi address.');const link=new URL('opengrokbot://pair');link.searchParams.set('host',url.origin);link.hash=token;return link.href;}
class RemoteHost{
 constructor(){this.server=null;this.receipts=new Set();}
 async start({port=48291,lan=false,token,snapshot,execute,models,files}){
  if(this.server)throw new Error('Remote access is already running');if(typeof token!=='string'||!/^[A-Za-z0-9_-]{43,128}$/.test(token))throw new Error('Invalid pairing key');this.token=token;
  const respond=(res,status,value)=>{if(res.headersSent||res.destroyed)return;const bytes=status===204?Buffer.alloc(0):Buffer.from(JSON.stringify(value));res.writeHead(status,{'Content-Type':'application/json','Content-Length':bytes.length,'Connection':'close','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(bytes);};
  const server=http.createServer({maxHeaderSize:8192},async(req,res)=>{
   try{
    const expected=Buffer.from('Bearer '+this.token),actual=Buffer.from(req.headers.authorization||'');
    if(req.headers.origin||req.headers['transfer-encoding']||req.rawHeaders.filter((_,i)=>i%2===0&&req.rawHeaders[i].toLowerCase()==='authorization').length>1)return respond(res,400,{error:'Invalid request'});
    if(actual.length!==expected.length||!crypto.timingSafeEqual(actual,expected))return respond(res,401,{error:'Pairing key required'});
    if(!req.url.startsWith('/')||req.url.length>2048)return respond(res,400,{error:'Invalid request'});
    const url=new URL(req.url,'http://localhost');
    if(req.method==='GET'&&url.pathname==='/v1/state'){const value=await snapshot();return url.searchParams.get('since')===value.revision?respond(res,204):respond(res,200,value);}
    if(req.method==='GET'&&url.pathname==='/v1/models')return respond(res,200,await models(url.searchParams.get('provider')));
    if(req.method==='GET'&&url.pathname==='/v1/files')return respond(res,200,await files(url.searchParams.get('bot')));
    if(req.method!=='POST'||url.pathname!=='/v1/command')return respond(res,404,{error:'Unknown endpoint'});
    if(!/^\d+$/.test(req.headers['content-length']||'')||Number(req.headers['content-length'])>131072)return respond(res,413,{error:'Request too large'});
    const chunks=[];let size=0;for await(const data of req){size+=data.length;if(size>131072)return respond(res,413,{error:'Request too large'});chunks.push(data);}
    const command=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!command||typeof command.requestID!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(command.requestID))return respond(res,400,{error:'Invalid command'});
    if(this.receipts.has(command.requestID))return respond(res,200,{accepted:true});
    await execute(command);if(this.receipts.size>=256)this.receipts.clear();this.receipts.add(command.requestID);respond(res,200,{accepted:true});
   }catch(error){respond(res,409,{error:error.publicMessage||'The host could not complete this request. Check the desktop workspace.'});}
  });
  server.maxConnections=32;server.maxHeadersCount=32;server.headersTimeout=10000;server.requestTimeout=20000;server.keepAliveTimeout=1000;server.maxRequestsPerSocket=1;
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,lan?'0.0.0.0':'127.0.0.1',resolve);});this.server=server;return server.address().port;
 }
 async stop(){const server=this.server;this.server=null;if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}}
 get active(){return !!this.server;}
}
module.exports={RemoteHost,pairing,localHost};
