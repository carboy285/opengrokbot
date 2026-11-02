const {randomUUID}=require('node:crypto');
const rules=new Set(['none','hourly','daily','weekly']);
function valid(task){return task&&typeof task.id==='string'&&typeof task.occurrence==='string'&&typeof task.name==='string'&&task.name.trim()&&task.name.length<=200&&typeof task.text==='string'&&task.text.trim()&&task.text.length<=8000&&typeof task.enabled==='boolean'&&rules.has(task.recurrence)&&typeof task.timezone==='string'&&(task.nextRun==null||typeof task.nextRun==='string'&&Number.isFinite(Date.parse(task.nextRun)))&&(task.contains==null||typeof task.contains==='string'&&task.contains.length<=200);}
function make(action){
 const recurrence=action.recurrence||'none',timezone=action.timezone||Intl.DateTimeFormat().resolvedOptions().timeZone;
 try{new Intl.DateTimeFormat('en',{timeZone:timezone}).format();}catch{return null;}
 const task={id:randomUUID(),occurrence:randomUUID(),name:action.name,text:action.text,recurrence,timezone,enabled:true};
 if(action.trigger==='message_received'){task.recurrence='none';task.contains=action.contains;}
 else {if(action.trigger!=null||typeof action.at!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(action.at)||!(Date.parse(action.at)>Date.now()))return null;task.nextRun=action.at;}
 return valid(task)?task:null;
}
function parts(date,zone){return Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(date).filter(x=>x.type!=='literal').map(x=>[x.type,Number(x.value)]));}
function advance(task,now=Date.now()){
 task.occurrence=randomUUID();if(task.nextRun==null||task.recurrence==='none'){task.enabled=false;return;}
 const previous=new Date(task.nextRun);
 if(task.recurrence==='hourly'){task.nextRun=new Date(previous.getTime()+(Math.floor((now-previous)/3600000)+1)*3600000).toISOString();return;}
 // Keep local wall-clock time across DST changes; coalesce missed intervals.
 const old=parts(previous,task.timezone),today=parts(new Date(now),task.timezone),step=task.recurrence==='weekly'?7:1;
 const oldDay=Date.UTC(old.year,old.month-1,old.day),todayDay=Date.UTC(today.year,today.month-1,today.day);
 let count=Math.max(1,Math.floor((todayDay-oldDay)/86400000/step));
 for(let attempt=0;attempt<3;attempt++,count++){
  const wanted=new Date(oldDay+count*step*86400000);wanted.setUTCHours(old.hour,old.minute,old.second,0);
  let candidate=wanted.getTime();
  for(let i=0;i<3;i++){const local=parts(new Date(candidate),task.timezone);candidate+=wanted.getTime()-Date.UTC(local.year,local.month-1,local.day,local.hour,local.minute,local.second);}
  if(candidate>now){task.nextRun=new Date(candidate).toISOString();return;}
 }
 task.nextRun=new Date(now+step*86400000).toISOString();
}
function firstMatchingEvent(events, task){
 const index=task.lastEvent?events.findIndex(event=>event.id===task.lastEvent):-1;
 const unseen=task.lastEvent?(index<0?events.slice(-1):events.slice(index+1)):events;
 return unseen.find(event=>!task.contains||event.text.toLowerCase().includes(task.contains.toLowerCase()));
}
module.exports={valid,make,advance,firstMatchingEvent};
