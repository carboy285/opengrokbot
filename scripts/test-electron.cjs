const { _electron: electron } = require('@playwright/test');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
(async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(),'opengrokbot-smoke-'));
  let desktop;
  const launch = () => electron.launch({ args: [path.resolve(__dirname,'..')], env: { ...process.env, OPENGROKBOT_TEST_DATA_DIR: directory } });
  try {
    desktop = await launch();
    const page = await desktop.firstWindow();
    await page.locator('#chat-heading').getByText('Grok Bot',{exact:true}).waitFor();
    assert.equal(await page.evaluate(()=>typeof window.require),'undefined');
    const invalid = await page.evaluate(()=>window.desktop.save({version:0}));
    assert.equal(invalid.ok,false,'IPC must reject invalid state');
    await page.locator('#draft').fill('Native IPC persistence smoke test');
    await page.locator('#draft').press('Control+Enter');
    await page.locator('.bubble').getByText('Native IPC persistence smoke test',{exact:true}).waitFor();
    const secret = 'encrypted-smoke-' + Date.now();
    const saved = await page.evaluate(value=>window.desktop.vaultSave('Test secret',value),secret);
    assert.equal(saved.ok,true,'Windows device encryption must be available');
    const listed = await page.evaluate(()=>window.desktop.vaultList());
    assert.equal(listed.ok,true);
    const item = listed.value.find(x=>x.title==='Test secret'); assert.ok(item);
    const read = await page.evaluate(id=>window.desktop.vaultRead(id),item.id); assert.equal(read.value,secret);
    assert.equal((await fs.readFile(path.join(directory,'vault.json'),'utf8')).includes(secret),false,'Vault must never store plaintext');
    await page.evaluate(id=>window.desktop.vaultDelete(id),item.id);
    await desktop.close(); desktop = await launch();
    const relaunched = await desktop.firstWindow();
    await relaunched.locator('.bubble').getByText('Native IPC persistence smoke test',{exact:true}).waitFor();
    console.log('PASS: native Electron launch, isolated renderer, validated IPC, persisted notes after relaunch, and encrypted Windows vault.');
  } finally {
    if (desktop) await desktop.close();
    await fs.rm(directory,{recursive:true,force:true});
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
