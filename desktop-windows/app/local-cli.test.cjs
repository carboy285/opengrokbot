const {test}=require('node:test');const assert=require('node:assert/strict');const {EventParser,command}=require('./local-cli.cjs');
test('parses Unicode streaming replies without duplicating completed messages',()=>{
 const parser=new EventParser();let events=parser.parse(JSON.stringify({type:'thread.started',thread_id:'session-test'}));assert.equal(events[0].id,'session-test');
 parser.parse(JSON.stringify({type:'item.updated',item:{id:'one',type:'agent_message',text:'Hello 🌎'}}));parser.parse(JSON.stringify({type:'item.completed',item:{id:'one',type:'agent_message',text:'Hello 🌎'}}));assert.equal(parser.text,'Hello 🌎');
 const claude=new EventParser();claude.parse(JSON.stringify({type:'stream_event',event:{delta:{type:'text_delta',text:'reply'}}}));claude.parse(JSON.stringify({type:'result',result:'reply'}));assert.equal(claude.text,'reply');
 const open=new EventParser();open.parse(JSON.stringify({type:'text',sessionID:'session-open',part:{id:'p',text:'OpenCode'}}));assert.equal(open.text,'OpenCode');
 const gemini=new EventParser();gemini.parse(JSON.stringify({type:'message',role:'assistant',content:'Gemini',delta:true}));assert.equal(gemini.text,'Gemini');
});
test('commands preserve per-provider sessions without approval bypass flags',()=>{for(const id of ['codex','claude','grok','opencode','gemini']){const args=command(id,'saved-session','private-prompt.txt');assert.ok(args.includes('saved-session'));assert.ok(!args.some(x=>/dangerously|yolo|auto-approve/.test(x)));}});

test('Claude Code reports connected-apps problems and only pre-approves the connected-apps server when asked', () => {
  const { EventParser, command, CONNECTED_APPS_SERVER } = require('./local-cli.cjs');
  assert.equal(CONNECTED_APPS_SERVER, 'opengrokbot-composio');
  const failed = new EventParser().parse(JSON.stringify({ type: 'system', subtype: 'init', session_id: 'abc', mcp_servers: [{ name: 'opengrokbot-composio', status: 'failed' }] }));
  assert.ok(failed.some(e => e.type === 'notice' && /failed/.test(e.text) && /Refresh connections/.test(e.text)));
  const fine = new EventParser().parse(JSON.stringify({ type: 'system', subtype: 'init', session_id: 'abc', mcp_servers: [{ name: 'opengrokbot-composio', status: 'connected' }, { name: 'other', status: 'failed' }] }));
  assert.ok(!fine.some(e => e.type === 'notice'));
  const blocked = new EventParser().parse(JSON.stringify({ type: 'result', result: 'could not', permission_denials: [{ tool_name: 'mcp__opengrokbot-composio__COMPOSIO_SEARCH_TOOLS' }] }));
  assert.ok(blocked.some(e => e.type === 'notice' && /Let Claude Code use connected apps/.test(e.text)));
  assert.ok(!new EventParser().parse(JSON.stringify({ type: 'result', result: 'ok', permission_denials: [{ tool_name: 'Bash' }] })).some(e => e.type === 'notice'));
  assert.ok(!command('claude', null, 'p.txt').includes('--allowedTools'));
  const on = command('claude', null, 'p.txt', '', { allowConnectedApps: true });
  assert.equal(on[on.indexOf('--allowedTools') + 1], 'mcp__opengrokbot-composio');
  assert.ok(!command('codex', null, 'p.txt', '', { allowConnectedApps: true }).includes('--allowedTools'));
});

test('Codex answers sent in pieces stream into the chat, then the final text wins', () => {
  const { EventParser } = require('./local-cli.cjs');
  const parser = new EventParser();
  const texts = [];
  for (const line of [
    '{"type":"item.agent_message.delta","item_id":"m1","delta":"Hello"}',
    '{"type":"item.agent_message.delta","item_id":"m1","delta":" there."}',
    '{"type":"item.completed","item":{"id":"m1","type":"agent_message","text":"Hello there!"}}'
  ]) for (const event of parser.parse(line)) if (event.type === 'text') texts.push(event.text);
  assert.deepEqual(texts, ['Hello', 'Hello there.', 'Hello there!']);
  assert.equal(parser.text, 'Hello there!');
});
