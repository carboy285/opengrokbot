const { randomUUID } = require('node:crypto');

const COLORS = new Set(['white', 'purple', 'pink', 'ochre']);
const KINDS = new Set(['bot', 'user', 'activity']);
function validateWorkspace(value) {
  if (!value || ![1,2].includes(value.version) || !Array.isArray(value.bots) || !Array.isArray(value.entries) || value.bots.length > 100 || value.entries.length > 10000) throw new Error('Invalid workspace');
  if(value.sessions!==undefined&&(typeof value.sessions!=='object'||value.sessions===null||Array.isArray(value.sessions)||Object.keys(value.sessions).length>1000||Object.values(value.sessions).some(x=>typeof x!=='string'||!/^[-_a-zA-Z0-9]{1,200}$/.test(x))))throw new Error('Invalid sessions');
  const ids = new Set();
  for (const bot of value.bots) {
    if (typeof bot.id !== 'string' || !/^[a-f0-9-]{36}$/i.test(bot.id) || ids.has(bot.id) || typeof bot.name !== 'string' || !bot.name.trim() || bot.name.length > 200 || typeof bot.purpose !== 'string' || bot.purpose.length > 2000 || !COLORS.has(bot.color)) throw new Error('Invalid Bot');
    ids.add(bot.id);
  }
  const entries = new Set();
  for (const entry of value.entries) {
    if (typeof entry.id !== 'string' || entries.has(entry.id) || !ids.has(entry.botID) || !KINDS.has(entry.kind) || typeof entry.text !== 'string' || entry.text.length > (entry.kind === 'bot' ? 32 * 1024 * 1024 : 100000)) throw new Error('Invalid entry');
    if(entry.state!==undefined&&!['streaming','complete','stopped','failed'].includes(entry.state))throw new Error('Invalid message state');
    entries.add(entry.id);
  }
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
  const main=value.bots.find(x=>x.name==='Grok Bot'&&x.purpose===fixtures.bots[0].purpose);
  const legacyPrefix=main?value.entries.filter(x=>x.botID===main.id).slice(0,7):[];
  const discarded=new Set();
  for(const bot of value.bots){
    if(bot===main)continue;
    if(fixtures.bots.slice(1).some(x=>x.name===bot.name&&x.purpose===bot.purpose)&&value.entries.filter(x=>x.botID===bot.id).every(x=>fixtureTexts.has(x.text)))discarded.add(bot.id);
  }
  value.bots=value.bots.filter(x=>!discarded.has(x.id));
  value.entries=value.entries.filter(x=>!discarded.has(x.botID)&&!fixtureTexts.has(x.text)&&!(legacyPrefix.indexOf(x)===1&&x.kind==='user'&&x.text==='Sure')&&!(legacyPrefix.indexOf(x)===5&&x.kind==='user'&&x.text==='Yea'));
  if(main){main.isMain=true;main.purpose=previewWorkspace().bots[0].purpose;}else value.bots.unshift(previewWorkspace().bots[0]);
  value.version=2;value.sessions={};return value;
}
module.exports = { validateWorkspace, previewWorkspace, migrateWorkspace };
