const {test}=require('node:test');const assert=require('node:assert/strict');
const {validateWorkspace,previewWorkspace,migrateWorkspace}=require('./workspace.cjs');
test('new workspace contains only the main Grok Bot and no example conversation',()=>{const value=previewWorkspace();assert.equal(validateWorkspace(value),value);assert.equal(value.bots.length,1);assert.equal(value.bots[0].name,'Grok Bot');assert.equal(value.bots[0].isMain,true);assert.deepEqual(value.entries,[]);});
test('rejects path traversal, duplicate IDs, orphan messages, unknown kinds and oversized notes',()=>{
  for(const mutate of [x=>x.bots.push(x.bots[0]),x=>x.bots[0].id='../../outside',x=>x.entries[0].botID='missing',x=>x.entries[0].kind='executed',x=>x.entries[0].text='x'.repeat(100001),x=>x.bots[0].name='',x=>x.bots[0].color='invalid']){
    const value=previewWorkspace();value.entries.push({id:'test',botID:value.bots[0].id,kind:'user',text:'Hello'});mutate(value);assert.throws(()=>validateWorkspace(value));
  }
});
test('legacy migration preserves user-authored messages and custom Bots',()=>{const value=previewWorkspace();value.version=1;value.bots[0].purpose='A place to bring it all together';value.entries.push({id:'authored',botID:value.bots[0].id,kind:'user',text:'Keep this message'});const migrated=migrateWorkspace(value);assert.equal(migrated.version,2);assert.equal(migrated.entries[0].text,'Keep this message');assert.equal(migrated.bots.length,1);});

test('long CLI replies remain reloadable while user message limits are preserved',()=>{const value=previewWorkspace();value.entries.push({id:'long-answer',botID:value.bots[0].id,kind:'bot',text:'x'.repeat(150000),state:'complete'});assert.equal(validateWorkspace(JSON.parse(JSON.stringify(value))).entries[0].text.length,150000);value.entries[0].kind='user';assert.throws(()=>validateWorkspace(value));});

test('migration never removes authored text that happens to match a fixture',()=>{const value=previewWorkspace();value.version=1;value.bots[0].purpose='A place to bring it all together';value.entries.push({id:'authored-fixture-phrase',botID:value.bots[0].id,kind:'user',text:'What’s on your plate right now?'},{id:'authored-sure',botID:value.bots[0].id,kind:'user',text:'Sure'});const migrated=migrateWorkspace(value);assert.deepEqual(migrated.entries.map(x=>x.text),['What’s on your plate right now?','Sure']);});
