const api=window.botBrowser,$=id=>document.getElementById(id);
async function run(promise){const response=await promise;if(!response.ok)$('state').textContent=response.error;}
$('bar').addEventListener('submit',event=>{event.preventDefault();run(api.navigate($('address').value.trim()));});
for(const key of ['back','forward','reload','clear'])$(key).addEventListener('click',()=>run(api[key]()));
api.onState(value=>{if(document.activeElement!==$('address'))$('address').value=value.url;$('back').disabled=!value.back;$('forward').disabled=!value.forward;$('state').textContent=value.loading?'Loading…':'Local browser';});
api.ready();
