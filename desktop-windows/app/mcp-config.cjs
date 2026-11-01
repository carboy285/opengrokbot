const fs=require('node:fs/promises');const path=require('node:path');const {randomUUID}=require('node:crypto');
const {trustedURL,variable}=require('./composio.cjs');
async function configure(provider,directory,url){
  if(!url)return {arguments:[],environment:{},cleanup:async()=>{}};
  if(!trustedURL(url))throw new Error('Set up Composio again.');
  const helper=path.join(__dirname,'composio-bridge.cjs'),name='opengrokbot-composio',command=process.execPath,args=[helper];
  const environment={[variable]:url};const result={arguments:[],environment};const files=[];
  result.cleanup=async()=>{for(const file of files)await fs.rm(file,{force:true}).catch(()=>{});};
  const write=async(relative,body)=>{const file=path.join(directory,relative);await fs.mkdir(path.dirname(file),{recursive:true,mode:0o700});try{await fs.writeFile(file,body,{flag:'wx',mode:0o600});}catch(error){if(error.code!=='EEXIST'||await fs.readFile(file,'utf8')!==body)throw error;}files.push(file);return file;};
  const server={command,args,env:{[variable]:'${'+variable+'}',ELECTRON_RUN_AS_NODE:'1'}};
  try{
    if(provider==='codex')result.arguments=['-c',`mcp_servers.${name}.command=${JSON.stringify(command)}`,'-c',`mcp_servers.${name}.args=${JSON.stringify(args)}`,'-c',`mcp_servers.${name}.env_vars=["${variable}"]`,'-c',`mcp_servers.${name}.env.ELECTRON_RUN_AS_NODE="1"`];
    else if(provider==='claude')result.arguments=['--mcp-config',await write('.composio-'+randomUUID()+'.json',JSON.stringify({mcpServers:{[name]:server}}))];
    else if(provider==='grok')await write('.grok/config.toml',`[mcp_servers.${name}]\ncommand = ${JSON.stringify(command)}\nargs = ${JSON.stringify(args)}\n[mcp_servers.${name}.env]\n${variable} = "\u0024{${variable}}"\nELECTRON_RUN_AS_NODE = "1"\n`);
    else if(provider==='opencode')environment.OPENCODE_CONFIG=await write('.composio-'+randomUUID()+'.json',JSON.stringify({mcp:{[name]:{type:'local',command:[command,...args],enabled:true,environment:{[variable]:'{env:'+variable+'}',ELECTRON_RUN_AS_NODE:'1'}}}}));
    else if(provider==='gemini')await write('.gemini/settings.json',JSON.stringify({mcpServers:{[name]:server}}));
    return result;
  }catch(error){await result.cleanup();throw error;}
}
module.exports={configure};
