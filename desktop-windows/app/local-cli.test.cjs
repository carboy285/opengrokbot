const {test}=require('node:test');const assert=require('node:assert/strict');const {EventParser,command}=require('./local-cli.cjs');
test('parses Unicode streaming replies without duplicating completed messages',()=>{
 const parser=new EventParser();let events=parser.parse(JSON.stringify({type:'thread.started',thread_id:'session-test'}));assert.equal(events[0].id,'session-test');
 parser.parse(JSON.stringify({type:'item.updated',item:{id:'one',type:'agent_message',text:'Hello 🌎'}}));parser.parse(JSON.stringify({type:'item.completed',item:{id:'one',type:'agent_message',text:'Hello 🌎'}}));assert.equal(parser.text,'Hello 🌎');
 const claude=new EventParser();claude.parse(JSON.stringify({type:'stream_event',event:{delta:{type:'text_delta',text:'reply'}}}));claude.parse(JSON.stringify({type:'result',result:'reply'}));assert.equal(claude.text,'reply');
 const open=new EventParser();open.parse(JSON.stringify({type:'text',sessionID:'session-open',part:{id:'p',text:'OpenCode'}}));assert.equal(open.text,'OpenCode');
 const gemini=new EventParser();gemini.parse(JSON.stringify({type:'message',role:'assistant',content:'Gemini',delta:true}));assert.equal(gemini.text,'Gemini');
});
test('commands preserve per-provider sessions without approval bypass flags',()=>{for(const id of ['codex','claude','grok','opencode','gemini']){const args=command(id,'saved-session','private-prompt.txt');assert.ok(args.includes('saved-session'));assert.ok(!args.some(x=>/dangerously|yolo|auto-approve/.test(x)));}});
