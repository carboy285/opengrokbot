const variable='OPENGROKBOT_COMPOSIO_MCP_URL';
function trustedURL(value){try{const url=new URL(value);return url.protocol==='https:'&&(url.hostname==='composio.dev'||url.hostname.endsWith('.composio.dev'))&&!url.username&&!url.password&&(!url.port||url.port==='443')?url:null;}catch{return null;}}
const validID=value=>typeof value==='string'&&/^[a-zA-Z0-9_-]{1,299}$/.test(value);
async function request(key,suffix,{method='GET',body,fetcher=fetch}={}){
  let response;
  try{response=await fetcher('https://backend.composio.dev/api/v3.1/tool_router/session'+suffix,{method,headers:{'x-api-key':key,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(30000)});}catch{throw new Error('Composio could not be reached. Check your connection and try again.');}
  if(!response.ok)throw Object.assign(new Error([401,403].includes(response.status)?'Composio rejected this project key or its permissions.':response.status===429?'Composio’s rate limit was reached. Try again later.':`Composio request failed (HTTP ${response.status}).`),{status:response.status});
  const text=await response.text();if(text.length>4000000)throw new Error('Composio returned an unsupported response.');
  try{return JSON.parse(text);}catch{throw new Error('Composio returned an unsupported response.');}
}
// Kept in step with TOOLKIT in composio-search.cjs. Not required from there: this file is unpacked next to the MCP helper, which must stay self-contained.
const searchToolkit='composio_search';
async function create(key,userID,toolkits,options={}){
  // Composio's own search toolkit is always added so Bots can look things up without opening a browser. It needs no sign-in.
  const withSearch=toolkits.includes(searchToolkit)?toolkits:[...toolkits,searchToolkit];
  const make=list=>request(key,'',{...options,method:'POST',body:{user_id:userID,toolkits:{enable:list},manage_connections:{enable:false}}});
  let session;
  try{session=await make(withSearch);}catch(error){if(error.status>=400&&error.status<500&&![401,403,429].includes(error.status))session=await make(toolkits);else throw error;}
  if(!validID(session.session_id)||!trustedURL(session.mcp?.url))throw new Error('Composio returned an unsupported session.');return session;
}
async function toolkits(key,sessionID,options={}){
  if(!validID(sessionID))throw new Error('Set up Composio again.');
  let cursor,items=[];
  for(let i=0;i<50;i++){
    const page=await request(key,`/${sessionID}/toolkits?limit=50${cursor?'&cursor='+encodeURIComponent(cursor):''}`,options);
    if(!Array.isArray(page.items))throw new Error('Composio returned an unsupported tool list.');
    items.push(...page.items.filter(x=>typeof x.slug==='string'&&typeof x.name==='string').map(x=>({slug:x.slug,name:x.name,enabled:!!x.enabled,noAuth:!!x.is_no_auth,status:x.connected_account?.status||null,connected:x.connected_account?.status?.toUpperCase()==='ACTIVE'})));
    if(!page.next_cursor||cursor===page.next_cursor)return items;cursor=page.next_cursor;
  }throw new Error('Composio returned too many tool pages.');
}
async function link(key,sessionID,toolkit,options={}){
  if(!validID(sessionID)||!validID(toolkit))throw new Error('Invalid toolkit.');
  const response=await request(key,`/${sessionID}/link`,{...options,method:'POST',body:{toolkit}});
  const url=trustedURL(response.redirect_url);if(!url)throw new Error('Composio returned an unsupported authorization URL.');return url.href;
}
module.exports={create,toolkits,link,trustedURL,variable};
