const api=window.mirror,$=s=>document.querySelector(s);
const make=(tag,text)=>{const element=document.createElement(tag);if(text!=null)element.textContent=text;return element;};
const action=(label,callback)=>{const button=make('button',label);button.type='button';button.addEventListener('click',()=>Promise.resolve().then(callback).catch(error=>{$('#feedback').textContent=error.message;}));return button;};
const result=async promise=>{const response=await promise;if(!response.ok)throw new Error(response.error);return response.value;};
let status={},selected=null,selectedHost=null,sending=false,follow=true,lastTop=0,content,signature='',lastRequest;
const drafts=new Map();
const bot=()=>status.snapshot?.workspace.bots.find(x=>x.id===selected);
const key=()=>selectedHost+'|'+selected;
$('#draft').addEventListener('input',()=>{drafts.set(key(),$('#draft').value);});
function bottom(){if(follow)requestAnimationFrame(()=>{if(follow)$('#messages').scrollTop=$('#messages').scrollHeight;});}
$('#messages').addEventListener('scroll',()=>{const top=$('#messages').scrollTop;if(top<lastTop-1)follow=false;else if(top>lastTop)follow=$('#messages').scrollHeight-top-$('#messages').clientHeight<70;lastTop=top;},{passive:true});
new ResizeObserver(bottom).observe($('#messages'));
function render(value){
 status=value;$('#status').textContent=value.phase;$('#fingerprint').textContent=value.fingerprint?'Controller fingerprint: '+value.fingerprint:'';
 if(value.hostID!==selectedHost){drafts.set(key(),$('#draft').value);selectedHost=value.hostID;selected=null;$('#draft').value='';signature='';}
 const picker=$('#hosts');picker.replaceChildren();const placeholder=make('option','Choose a computer');placeholder.value='';picker.append(placeholder);
 for(const host of value.hosts||[]){const option=make('option',host.name+(host.online?' · online':' · offline'));option.value=host.id;picker.append(option);}picker.value=value.hostID||'';
 const times=new Map();for(const entry of value.snapshot?.workspace.entries||[])times.set(entry.botID,Math.max(times.get(entry.botID)||0,Date.parse(entry.date)||0));
 const bots=[...(value.snapshot?.workspace.bots||[])].sort((a,b)=>{const ap=!!(a.isPinned??a.isMain),bp=!!(b.isPinned??b.isMain);return Number(bp)-Number(ap)||(ap?0:Math.max(times.get(b.id)||0,Date.parse(b.lastUsedAt)||0)-Math.max(times.get(a.id)||0,Date.parse(a.lastUsedAt)||0));});
 if(selected&&!bots.some(x=>x.id===selected)){selected=null;$('#draft').value='';}
 if(!selected&&bots.length){selected=bots[0].id;$('#draft').value=drafts.get(key())||'';follow=true;}
 $('#bots').replaceChildren();for(const item of bots){const row=action((item.isPinned??item.isMain?'★ ':'')+item.name,()=>{drafts.set(key(),$('#draft').value);selected=item.id;command({action:'touch_bot',botID:item.id}).catch(error=>{$('#feedback').textContent=error.message;});$('#draft').value=drafts.get(key())||'';follow=true;signature='';render(status);});row.classList.toggle('selected',item.id===selected);$('#bots').append(row);}
 const current=bot();$('#heading').replaceChildren();
 if(current){
  $('#heading').append(make('strong',current.name),action('Browser',async()=>{await command({action:'open_browser',botID:current.id});$('#browser-dialog').showModal();await browserPreview();}),action(current.isPinned??current.isMain?'Unpin':'Pin',async()=>{await result(api.pin(current.id,!(current.isPinned??current.isMain??false)));}),action('Provider',async()=>{const provider=prompt('Provider: codex, claude, grok, opencode or gemini',current.aiConfiguration?.activeProvider||value.snapshot.defaultProvider||'codex');if(provider==null)return;if(!['codex','claude','grok','opencode','gemini'].includes(provider))throw new Error('Choose a supported provider.');const model=prompt('Model ID (blank uses provider default)','');if(model==null)return;await command({action:'configure_bot',botID:current.id,configuration:{providers:[{provider,model}],activeProvider:provider,replyMode:'one'}});}));
  if(!current.isMain)$('#heading').append(action('Delete',async()=>{if(confirm('Delete '+current.name+' and its conversations on the server?'))await command({action:'delete_bot',botID:current.id});}));
 }
 const entries=current?(value.snapshot.workspace.entries||[]).filter(x=>x.botID===current.id):[];
 const next=JSON.stringify([selected,entries]);if(signature!==next){signature=next;if(!content){content=make('div');content.id='content';$('#messages').replaceChildren(content);new ResizeObserver(bottom).observe(content);}content.replaceChildren();for(const entry of entries){const bubble=make('div',entry.text||'Working…');bubble.className='bubble '+entry.kind;content.append(bubble);}if(!current)content.append(make('p','Choose a server, then a Bot. Work runs on the selected server.'));bottom();}
 $('#send').disabled=!current||sending||value.stage!=='connected';$('#stop').disabled=!current||value.stage!=='connected'||!value.snapshot?.running.includes(current.id);$('#new').disabled=value.stage!=='connected';
}
async function command(value){await result(api.command(value));}
$('#hosts').addEventListener('change',async()=>{try{if(!$('#hosts').value)return;$('#feedback').textContent='Connecting…';render(await result(api.select($('#hosts').value)));$('#feedback').textContent='';}catch(error){$('#feedback').textContent=error.message;}});
$('#refresh').addEventListener('click',async()=>{try{render(await result(api.discover()));}catch(error){$('#feedback').textContent=error.message;}});
$('#local').addEventListener('click',()=>api.close());
$('#new').addEventListener('click',async()=>{try{const name=prompt('New Bot name');if(!name)return;const purpose=prompt('What should this Bot do?','');if(purpose==null)return;await command({action:'create_bot',name,purpose,color:'purple'});}catch(error){$('#feedback').textContent=error.message;}});
$('#stop').addEventListener('click',async()=>{try{if(bot())await command({action:'stop',botID:bot().id});}catch(error){$('#feedback').textContent=error.message;}});
$('#composer').addEventListener('submit',async event=>{
 event.preventDefault();const current=bot(),text=$('#draft').value.trim(),host=selectedHost;if(sending||!current||!text)return;
 const request=lastRequest?.host===host&&lastRequest.bot===current.id&&lastRequest.text===text?lastRequest:{host,bot:current.id,text,id:crypto.randomUUID()};lastRequest=request;sending=true;follow=true;render(status);
 try{await command({requestID:request.id,action:'send',botID:current.id,text});if(selectedHost===host&&selected===current.id&&$('#draft').value.trim()===text){$('#draft').value='';drafts.delete(key());}lastRequest=null;$('#feedback').textContent='Message accepted by server.';}catch(error){$('#feedback').textContent=error.message;}finally{sending=false;render(status);}
});
api.onChange(render);result(api.discover()).then(render).catch(error=>{$('#feedback').textContent=error.message;});

$('#reconnect').addEventListener('click',async()=>{try{render(await result(api.retry()));$('#feedback').textContent='';}catch(error){$('#feedback').textContent=error.message;}});

async function browserPreview(){if(!bot())return;$('#browser-status').textContent='Getting current page…';try{const preview=await result(api.browser(bot().id));$('#browser-status').textContent=preview.title+' · '+preview.url;const image=$('#browser-preview');if(typeof preview.imageData==='string'&&/^[A-Za-z0-9+/]*={0,2}$/.test(preview.imageData)&&preview.imageData.length<=3000000){image.src='data:image/jpeg;base64,'+preview.imageData;image.hidden=false;}else{image.removeAttribute('src');image.hidden=true;}}catch(error){$('#browser-status').textContent=error.message;}}
$('#browser-refresh').addEventListener('click',browserPreview);$('#browser-close').addEventListener('click',()=>$('#browser-dialog').close());
