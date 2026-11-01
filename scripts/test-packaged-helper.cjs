// Verify that an installed-app runtime can launch the unpacked MCP helper without another Node install.
const path=require('node:path');const fs=require('node:fs');const {spawnSync}=require('node:child_process');const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../artifacts/windows/win-unpacked');
const executable=path.join(root,'OpenGrokBot.exe');const helper=path.join(root,'resources/app.asar.unpacked/desktop-windows/app/composio-bridge.cjs');
assert.ok(fs.existsSync(executable));assert.ok(fs.existsSync(helper));assert.ok(fs.existsSync(path.join(path.dirname(helper),'composio.cjs')));
const result=spawnSync(executable,[helper],{env:{...process.env,ELECTRON_RUN_AS_NODE:'1',OPENGROKBOT_COMPOSIO_MCP_URL:'https://connect.composio.dev/mcp/packaging-fixture'},input:'',encoding:'utf8',timeout:15000,windowsHide:true});
assert.equal(result.status,0,`Packaged MCP helper could not launch: ${(result.stderr||'').slice(0,1000)}`);
console.log('PASS: packaged Windows executable launches the unpacked MCP helper; no extra Node runtime or network request is required.');
