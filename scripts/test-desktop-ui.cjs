// Uses an already installed Chromium; no browser downloads are required.
const { chromium } = require('@playwright/test');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const assert = require('node:assert/strict');

(async () => {
  const server = spawn('python3', ['-m','http.server','4174','--bind','127.0.0.1','--directory','desktop-windows/renderer'], { stdio: 'ignore' });
  let browser;
  try {
    await new Promise((resolve, reject) => { server.once('error', reject); setTimeout(resolve, 300); });
    browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium', headless: true, args: ['--no-sandbox'] });
    const page = await browser.newPage({ viewport: { width: 1370, height: 940 }, deviceScaleFactor: 1 });
    const errors=[];page.on('pageerror', error=>errors.push(error.message));
    await page.goto('http://127.0.0.1:4174');
    await page.locator('#status-button').waitFor();
    await fs.mkdir('artifacts/visuals-web',{recursive:true});
    await page.screenshot({path:'artifacts/visuals-web/workspace.png'});
    const prior=await page.locator('.bubble').count();
    await page.locator('#draft').fill('A local note that must survive relaunch.');
    await page.locator('#draft').press('Control+Enter');
    await page.getByText('A local note that must survive relaunch.',{exact:true}).waitFor();
    assert.equal(await page.locator('.bubble').count(),prior+1,'Saving must not invent a Bot reply');
    await page.reload();
    await page.getByText('A local note that must survive relaunch.',{exact:true}).waitFor();
    await page.getByRole('button',{name:'New preview Bot',exact:true}).click();
    await page.getByRole('textbox',{name:'Bot name',exact:true}).fill('UI Test Bot');
    await page.getByRole('textbox',{name:'Bot description',exact:true}).fill('Local persistence test');
    await page.getByRole('button',{name:'Create preview Bot',exact:true}).click();
    await page.locator('#chat-heading').getByText('UI Test Bot',{exact:true}).waitFor();
    await page.locator('#draft').fill('<img src=x onerror=alert(1)>');
    await page.locator('#draft').press('Control+Enter');
    await page.locator('.bubble').getByText('<img src=x onerror=alert(1)>',{exact:true}).waitFor();
    assert.equal(await page.locator('#messages img').count(),0,'Messages must render as text');
    await page.evaluate(()=>{const original=Storage.prototype.setItem;Storage.prototype.setItem=function(key,value){if(key==='workspace')throw new DOMException('Quota exceeded','QuotaExceededError');return original.call(this,key,value);};});
    await page.locator('#draft').fill('Keep this unsaved draft');
    await page.locator('#draft').press('Control+Enter');
    await page.getByRole('status').getByText('Local storage is full. Your draft was kept.',{exact:true}).waitFor();
    assert.equal(await page.locator('#draft').inputValue(),'Keep this unsaved draft');
    await page.reload();
    await page.getByRole('button',{name:'Connect apps',exact:false}).click();
    await page.getByRole('textbox',{name:'Search apps'}).fill('Supabase');
    assert.equal(await page.locator('.catalog-app').count(),1);
    await page.getByRole('button',{name:'Connect',exact:true}).click();
    await page.getByRole('heading',{name:'Not connected',exact:true}).waitFor();
    await page.getByRole('button',{name:'Back to workspace'}).click();
    await page.getByRole('button',{name:'Connect apps',exact:false}).click();
    await page.screenshot({path:'artifacts/visuals-web/connect-apps.png'});
    await page.getByRole('button',{name:'Close panel'}).click();
    await page.getByRole('button',{name:'Settings',exact:true}).click();
    await page.screenshot({path:'artifacts/visuals-web/settings.png'});
    await page.getByRole('combobox',{name:'Theme'}).selectOption('light');
    assert.equal(await page.locator('html').getAttribute('data-theme'),'light');
    await page.keyboard.press('Escape');
    await page.emulateMedia({reducedMotion:'reduce'});
    await page.getByRole('button',{name:'Settings',exact:true}).click();
    assert.equal(await page.locator('#panel').evaluate(el=>getComputedStyle(el).animationName),'none');
    const vaultPage = await browser.newPage();
    const { previewWorkspace } = require('../desktop-windows/app/workspace.cjs');
    await vaultPage.addInitScript(value => {
      window.desktop = {
        load: async () => ({ok:true,value}),
        vaultList: async () => ({ok:true,value:[{id:'test-secret',title:'Test secure note'}]}),
        vaultRead: () => new Promise(resolve => { window.finishSecretRead = () => resolve({ok:true,value:'private-test-value'}); })
      };
    }, previewWorkspace());
    await vaultPage.goto('http://127.0.0.1:4174');
    await vaultPage.bringToFront();
    await vaultPage.getByRole('button',{name:'Settings',exact:true}).click();
    await vaultPage.getByRole('button',{name:'Vault',exact:false}).click();
    await vaultPage.getByRole('button',{name:'Reveal',exact:true}).click();
    await vaultPage.evaluate(()=>{ window.dispatchEvent(new Event('blur')); window.finishSecretRead(); });
    await vaultPage.waitForTimeout(50);
    assert.equal(await vaultPage.locator('.revealed-secret').isVisible(),false,'A delayed secret read must not reveal after loss of focus');
    assert.equal(await vaultPage.locator('.revealed-secret').textContent(),'');
    await vaultPage.close();
    assert.deepEqual(errors,[],'No uncaught JavaScript errors');
    console.log('PASS: desktop local persistence, Bot creation, text escaping, failed-save recovery, catalog filtering, honest connection status, themes, reduced motion, delayed vault reveal protection, and screenshots.');
  } finally {
    if (browser) await browser.close();
    server.kill();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
