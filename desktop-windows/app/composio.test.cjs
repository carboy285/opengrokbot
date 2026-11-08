const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');
const api=require('./composio.cjs');const {configure}=require('./mcp-config.cjs');
test('project sessions use fixed origin, unique user, explicit tool allowlist and redirect protection',async()=>{
  const calls=[];const options={fetcher:async(url,request)=>{calls.push({url,request});return new Response(JSON.stringify(url.endsWith('/link')?{redirect_url:'https://connect.composio.dev/link/test'}:url.includes('/toolkits?')?{items:[{slug:'github',name:'GitHub',enabled:true,is_no_auth:false,connected_account:{status:'ACTIVE'}}]}:{session_id:'trs_fixture',mcp:{url:'https://connect.composio.dev/mcp/test'}}),{status:200});}};
  const session=await api.create('private-project-key','device-specific-user',['github'],options);
  assert.equal(calls[0].request.headers['x-api-key'],'private-project-key');assert.equal(calls[0].request.redirect,'error');
  assert.deepEqual(JSON.parse(calls[0].request.body),{user_id:'device-specific-user',toolkits:{enable:['github','composio_search']},manage_connections:{enable:false}});
  assert.equal((await api.toolkits('key',session.session_id,options))[0].connected,true);
  assert.equal(await api.link('key',session.session_id,'github',options),'https://connect.composio.dev/link/test');
  assert.ok(calls.every(x=>new URL(x.url).origin==='https://backend.composio.dev'));
});
test('if Composio does not accept its search toolkit the session is created again without it',async()=>{
  const bodies=[];const fetcher=async(url,request)=>{const body=JSON.parse(request.body);bodies.push(body.toolkits.enable);return body.toolkits.enable.includes('composio_search')?new Response('{}',{status:400}):new Response(JSON.stringify({session_id:'s1',mcp:{url:'https://backend.composio.dev/mcp/s1'}}),{status:200});};
  const session=await api.create('k','u',['github'],{fetcher});
  assert.equal(session.session_id,'s1');assert.deepEqual(bodies,[['github','composio_search'],['github']]);
  await assert.rejects(api.create('k','u',['github'],{fetcher:async()=>new Response('{}',{status:401})}),/rejected/);
});
test('rejects unsafe returned endpoints and never surfaces raw service errors',async()=>{
  for(const value of ['http://composio.dev/a','https://composio.dev.evil.example/a','https://user:secret@composio.dev/a','https://composio.dev:8443/a'])assert.equal(api.trustedURL(value),null);
  await assert.rejects(api.create('secret','unique',['github'],{fetcher:async()=>new Response('secret echoed here',{status:401})}),error=>!error.message.includes('secret'));
});
test('all five MCP provider configs omit capability URLs on disk and argv, then clean up',async()=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'composio-config-'));
  const url='https://connect.composio.dev/mcp/private-capability';
  try{for(const provider of ['codex','claude','grok','opencode','gemini']){
    const config=await configure(provider,directory,url);assert.equal(config.environment[api.variable],url);assert.ok(!JSON.stringify(config.arguments).includes(url));
    const visit=async dir=>{for(const item of await fs.readdir(dir,{withFileTypes:true})){const file=path.join(dir,item.name);if(item.isDirectory())await visit(file);else assert.ok(!(await fs.readFile(file,'utf8')).includes(url));}};await visit(directory);await config.cleanup();
  }}finally{await fs.rm(directory,{recursive:true,force:true});}
});
test('composio.cjs only requires files that are unpacked next to the MCP helper, and its search toolkit name matches',async()=>{
  const source=await fs.readFile(path.join(__dirname,'composio.cjs'),'utf8');
  const local=[...source.matchAll(/require\(['"](\.\/[^'"]+)['"]\)/g)].map(match=>match[1]);
  assert.deepEqual(local,[],'composio.cjs must stay self-contained: the packaged helper cannot load other app files');
  assert.ok(source.includes("'"+require('./composio-search.cjs').TOOLKIT+"'"));
});

