const {test}=require('node:test');const assert=require('node:assert/strict');const {createProxy}=require('./composio-bridge.cjs');
test('MCP proxy forwards initialize, notifications, session headers and streamed tool replies',async()=>{
 const output=[],requests=[];
 const handle=createProxy('https://connect.composio.dev/mcp/test',{send:value=>output.push(value),fetcher:async(url,request)=>{
   requests.push(request);const value=JSON.parse(request.body);
   if(value.method==='initialize')return new Response(JSON.stringify({jsonrpc:'2.0',id:value.id,result:{protocolVersion:'2025-03-26',capabilities:{},serverInfo:{name:'test',version:'1'}}}),{headers:{'Content-Type':'application/json','Mcp-Session-Id':'fixture-session'}});
   if(value.id===undefined)return new Response(null,{status:202});
   return new Response('event: message\ndata: '+JSON.stringify({jsonrpc:'2.0',id:value.id,result:{content:[{type:'text',text:'tool result 🌎'}]}})+'\n\n',{headers:{'Content-Type':'text/event-stream'}});
 }});
 await handle(JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'test',version:'1'}}}));
 await handle(JSON.stringify({jsonrpc:'2.0',method:'notifications/initialized'}));await handle(JSON.stringify({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'test',arguments:{}}}));
 assert.equal(output.length,2);assert.equal(output[1].result.content[0].text,'tool result 🌎');assert.equal(requests[2].headers['Mcp-Session-Id'],'fixture-session');assert.equal(requests[2].headers['MCP-Protocol-Version'],'2025-03-26');assert.equal(requests[2].redirect,'error');assert.equal(requests[2].headers['x-api-key'],undefined);
});
test('MCP errors do not expose capability URLs, project keys or remote error bodies',async()=>{
 const output=[];const handle=createProxy('https://connect.composio.dev/mcp/private-capability',{send:value=>output.push(value),fetcher:async()=>new Response('private-capability and project-key',{status:401})});
 await handle(JSON.stringify({jsonrpc:'2.0',id:7,method:'tools/list'}));assert.equal(output[0].id,7);assert.equal(output[0].error.code,-32000);assert.ok(!JSON.stringify(output).includes('private-capability'));assert.ok(!JSON.stringify(output).includes('project-key'));
});
