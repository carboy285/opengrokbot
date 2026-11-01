const { randomUUID } = require('node:crypto');

const COLORS = new Set(['white', 'purple', 'pink', 'ochre']);
const KINDS = new Set(['bot', 'user', 'activity']);
function validateWorkspace(value) {
  if (!value || value.version !== 1 || !Array.isArray(value.bots) || !Array.isArray(value.entries) || value.bots.length > 100 || value.entries.length > 10000) throw new Error('Invalid workspace');
  const ids = new Set();
  for (const bot of value.bots) {
    if (typeof bot.id !== 'string' || !bot.id || ids.has(bot.id) || typeof bot.name !== 'string' || !bot.name.trim() || bot.name.length > 200 || typeof bot.purpose !== 'string' || bot.purpose.length > 2000 || !COLORS.has(bot.color)) throw new Error('Invalid Bot');
    ids.add(bot.id);
  }
  const entries = new Set();
  for (const entry of value.entries) {
    if (typeof entry.id !== 'string' || entries.has(entry.id) || !ids.has(entry.botID) || !KINDS.has(entry.kind) || typeof entry.text !== 'string' || entry.text.length > 100000) throw new Error('Invalid entry');
    entries.add(entry.id);
  }
  return value;
}

function previewWorkspace() {
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
module.exports = { validateWorkspace, previewWorkspace };
