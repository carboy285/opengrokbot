const test = require('node:test');
const assert = require('node:assert/strict');
const {make, advance, firstMatchingEvent} = require('./schedules.cjs');

test('rejects invalid schedules and creates an explicit incoming-message trigger', () => {
  assert.equal(make({name:'x',text:'y',at:'not a date'}), null);
  assert.equal(make({name:'x',text:'y',at:new Date(Date.now()+60000).toISOString(),timezone:'not/a-zone'}), null);
  const task = make({name:'Urgent',text:'Review',trigger:'message_received',contains:'urgent',timezone:'America/Chicago'});
  assert.equal(task.contains, 'urgent');
  assert.equal(task.nextRun, undefined);
  assert.equal(task.enabled, true);
});

test('daily schedules retain local time across daylight saving and coalesce missed runs', () => {
  const task = {occurrence:'old',nextRun:'2026-03-07T15:00:00Z',recurrence:'daily',timezone:'America/Chicago',enabled:true};
  advance(task, Date.parse('2026-03-09T13:00:00Z'));
  assert.equal(task.nextRun, '2026-03-09T14:00:00.000Z');
  assert.notEqual(task.occurrence, 'old');
});

test('one-time schedules disable after running', () => {
  const task = {occurrence:'old',nextRun:'2026-01-01T10:00:00Z',recurrence:'none',timezone:'Etc/UTC',enabled:true};
  advance(task, Date.parse('2026-01-02T10:00:00Z'));
  assert.equal(task.enabled, false);
  assert.notEqual(task.occurrence, 'old');
});


test('message triggers handle matching messages in order rather than skipping to the latest', () => {
  const events = [{id:'a',text:'old'}, {id:'b',text:'Urgent one'}, {id:'c',text:'ordinary'}, {id:'d',text:'URGENT two'}];
  assert.equal(firstMatchingEvent(events, {lastEvent:'a',contains:'urgent'}).id, 'b');
  assert.equal(firstMatchingEvent(events, {lastEvent:'b',contains:'urgent'}).id, 'd');
  assert.equal(firstMatchingEvent(events, {lastEvent:'d',contains:'urgent'}), undefined);
});
