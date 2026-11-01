const { randomUUID } = require('node:crypto');

const COLORS = new Set(['white','black','red','orange','amber','green','teal','blue','purple','pink','ochre','gray']);
const KINDS = new Set(['bot', 'user', 'activity']);
function validateWorkspace(value) {
  if (!value || ![1,2].includes(value.version) || !Array.isArray(value.bots) || !Array.isArray(value.entries) || value.bots.length > 100 || value.entries.length > 10000) throw new Error('Invalid workspace');
  if(value.sessions!==undefined&&(typeof value.sessions!=='object'||value.sessions===null||Array.isArray(value.sessions)||Object.keys(value.sessions).length>1000||Object.values(value.sessions).some(x=>typeof x!=='string'||!/^[-_a-zA-Z0-9]{1,200}$/.test(x))))throw new Error('Invalid sessions');
  const memory=value=>value===undefined||value===null||(Array.isArray(value)&&value.length<=100&&value.every(x=>typeof x==='string'&&x.length<=2000));
  if(!memory(value.sharedMemory))throw new Error('Invalid shared memory');
  const ids = new Set();
  for (const bot of value.bots) {
    if (typeof bot.id !== 'string' || !/^[a-f0-9-]{36}$/i.test(bot.id) || ids.has(bot.id.toLowerCase()) || typeof bot.name !== 'string' || !bot.name.trim() || bot.name.length > 200 || typeof bot.purpose !== 'string' || bot.purpose.length > 2000 || !COLORS.has(bot.color)) throw new Error('Invalid Bot');
    if(bot.schedules!=null&&(!Array.isArray(bot.schedules)||bot.schedules.length>100||bot.schedules.some(x=>!require('./schedules.cjs').valid(x))))throw new Error('Invalid scheduled tasks');
    if(bot.isPinned!=null&&typeof bot.isPinned!=='boolean'||bot.folder!=null&&(typeof bot.folder!=='string'||bot.folder.length>80)||bot.sortOrder!=null&&(!Number.isInteger(bot.sortOrder)||bot.sortOrder<0||bot.sortOrder>10000))throw new Error('Invalid Bot organization');
    if(bot.appearance!=null){const a=bot.appearance;if(!COLORS.has(a.color)||!['circle','cloud','square','sparkle','flower','heart','clover','droplet','capsule','triangle','pebble','star','hexagon','fruit'].includes(a.shape)||a.imageData!=null&&(typeof a.imageData!=='string'||!/^[A-Za-z0-9+/]*={0,2}$/.test(a.imageData)||a.imageData.length>32768||Buffer.from(a.imageData,'base64').length>24576))throw new Error('Invalid Bot avatar');}
    if(bot.aiConfiguration!==undefined&&bot.aiConfiguration!==null){const config=bot.aiConfiguration;
      if(!Array.isArray(config.providers)||config.providers.length>5||!['one','all'].includes(config.replyMode)||new Set(config.providers.map(x=>x.provider)).size!==config.providers.length||config.providers.some(x=>!['codex','claude','grok','opencode','gemini'].includes(x.provider)||typeof x.model!=='string'||x.model.length>200||/[\r\n]/.test(x.model))||(config.activeProvider!=null&&!config.providers.some(x=>x.provider===config.activeProvider)))throw new Error('Invalid provider settings');
    }
    if(!memory(bot.memory)||bot.memberIDs!==undefined&&(!Array.isArray(bot.memberIDs)||bot.memberIDs.length>8||bot.memberIDs.some(x=>typeof x!=='string')))throw new Error('Invalid Bot memory or group');
    ids.add(bot.id.toLowerCase());
  }
  const entries = new Set();
  for (const entry of value.entries) {
    if (typeof entry.id !== 'string' || entries.has(entry.id.toLowerCase()) || typeof entry.botID!=='string' || !ids.has(entry.botID.toLowerCase()) || !KINDS.has(entry.kind) || typeof entry.text !== 'string' || entry.text.length > (entry.kind === 'bot' ? 32 * 1024 * 1024 : 100000)) throw new Error('Invalid entry');
    if(entry.state!==undefined&&!['streaming','complete','stopped','failed'].includes(entry.state))throw new Error('Invalid message state');
    entries.add(entry.id.toLowerCase());
  }
  if(value.teamMessages!==undefined){if(!Array.isArray(value.teamMessages)||value.teamMessages.length>10000||value.teamMessages.some(x=>typeof x.from!=='string'||typeof x.to!=='string'||!ids.has(x.from.toLowerCase())||!ids.has(x.to.toLowerCase())||typeof x.id!=='string'||typeof x.rootID!=='string'||typeof x.text!=='string'||x.text.length>8000||!Number.isInteger(x.depth)||x.depth<1||x.depth>4||!['queued','running','complete','failed','stopped'].includes(x.status)))throw new Error('Invalid teamwork queue');}
  return value;
}

function legacyWorkspace() {
  const bots = [
    { id: randomUUID(), name: 'Grok Bot', purpose: 'A place to bring it all together', color: 'white' },
    { id: randomUUID(), name: 'Soccer & Percussion', purpose: 'Practice plans, one day at a time', color: 'purple' },
    { id: randomUUID(), name: 'AI Brief', purpose: 'Research worth your time', color: 'purple' },
    { id: randomUUID(), name: 'STEMBound', purpose: 'Make room for your next idea', color: 'pink' },
    { id: randomUUID(), name: 'School', purpose: 'Make a plan for the week ahead', color: 'ochre' }
  ];
  const message = (index, kind, text) => ({ id: randomUUID(), botID: bots[index].id, kind, text });
  return { version: 1, bots, entries: [
    message(0, 'bot', 'Your week is coming together. You’ve got percussion practice, a STEMBound meeting, and a Spanish test on Wednesday.\n\nWant me to have the School bot help you study for Wednesday’s Spanish test?'),
    message(0, 'user', 'Sure'),
    message(0, 'activity', 'Messaged · School'),
    message(0, 'bot', 'I sent it to the School bot. It’ll ask you in its own chat what the Spanish test covers, then put together a study plan for Sunday through Tuesday and some practice questions. Do you have a study guide or notes you can share with it?'),
    message(0, 'activity', 'Message from · School'),
    message(0, 'user', 'Yea'),
    message(0, 'bot', 'Nice! Send it right here, either a photo of the study guide or a quick list of the topics, and I’ll pass it to School so it can build your plan.'),
    message(1, 'bot', 'Want me to set up those snare drum routines for the week?'),
    message(2, 'bot', 'Which workflow do you want? A quick daily brief, a deeper research note, or a running list of ideas?'),
    message(3, 'bot', 'What’s on your plate right now?'),
    message(4, 'bot', 'What do you need help with for Wednesday’s Spanish test?')
  ] };
}
function previewWorkspace(){return {version:2,bots:[{id:randomUUID(),name:'Grok Bot',purpose:'Your AI assistant, powered by a CLI on this device.',color:'white',isMain:true}],entries:[],sessions:{}};}
function migrateWorkspace(value){
  validateWorkspace(value);if(value.version===2)return value;
  const fixtures=legacyWorkspace(),fixtureTexts=new Set(fixtures.entries.filter(x=>x.kind!=='user').map(x=>x.text));
  const seeded=new Set(value.bots.filter(bot=>fixtures.bots.some(x=>x.name===bot.name&&x.purpose===bot.purpose)).map(x=>x.id));
  const main=value.bots.find(x=>x.name==='Grok Bot'&&x.purpose===fixtures.bots[0].purpose);
  const legacyPrefix=main?value.entries.filter(x=>x.botID===main.id).slice(0,7):[];
  const fullFixture=legacyPrefix.length===7&&legacyPrefix.every((entry,index)=>entry.kind===fixtures.entries[index].kind&&entry.text===fixtures.entries[index].text);
  const discarded=new Set();
  for(const bot of value.bots){
    if(bot===main)continue;
    if(fixtures.bots.slice(1).some(x=>x.name===bot.name&&x.purpose===bot.purpose)&&value.entries.filter(x=>x.botID===bot.id).every(x=>x.kind!=='user'&&fixtureTexts.has(x.text)))discarded.add(bot.id);
  }
  value.bots=value.bots.filter(x=>!discarded.has(x.id));
  value.entries=value.entries.filter(x=>!discarded.has(x.botID)&&!(seeded.has(x.botID)&&x.kind!=='user'&&fixtureTexts.has(x.text))&&!(fullFixture&&legacyPrefix.indexOf(x)===1&&x.kind==='user'&&x.text==='Sure')&&!(fullFixture&&legacyPrefix.indexOf(x)===5&&x.kind==='user'&&x.text==='Yea'));
  if(main){main.isMain=true;main.purpose=previewWorkspace().bots[0].purpose;}else value.bots.unshift(previewWorkspace().bots[0]);
  value.version=2;value.sessions={};return value;
}
module.exports = { validateWorkspace, previewWorkspace, migrateWorkspace };
