const { app, BrowserWindow, ipcMain, dialog, shell, safeStorage } = require('electron');
const { readFile, writeFile, mkdir, rename } = require('node:fs/promises');
const path = require('node:path');
const { fileURLToPath } = require('node:url');
const { randomUUID } = require('node:crypto');
const { validateWorkspace, previewWorkspace } = require('./workspace.cjs');

let window;
const rendererFile = path.resolve(__dirname, '../renderer/index.html');
const documentation = new Set(['https://docs.x.ai/grok-bot/get-started', 'https://docs.x.ai/grok-bot/mobile', 'https://github.com/carboy285/opengrokbot']);
let writeQueue = Promise.resolve();
function file(name) { return path.join(app.getPath('userData'), name); }
function authorized(event) {
  try { return event.sender === window?.webContents && event.senderFrame === window.webContents.mainFrame && fileURLToPath(event.senderFrame.url) === rendererFile; }
  catch { return false; }
}
function handle(name, callback) {
  ipcMain.handle(name, async (event, ...args) => {
    if (!authorized(event)) return { ok: false, error: 'Untrusted request' };
    try { return { ok: true, value: await callback(...args) }; }
    catch { return { ok: false, error: 'The action could not be completed. Your existing data was kept; unlock your device or check available storage and try again.' }; }
  });
}
async function atomicJSON(name, value) {
  const operation = writeQueue.then(async () => {
    const temporary = file(`${name}.${randomUUID()}.tmp`);
    await mkdir(app.getPath('userData'), { recursive: true });
    await writeFile(temporary, JSON.stringify(value), { mode: 0o600 });
    await rename(temporary, file(name));
  });
  writeQueue = operation.catch(() => {});
  return operation;
}
async function loadJSON(name, fallback) {
  try { return JSON.parse(await readFile(file(name), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return fallback; throw error; }
}
function requireVault() {
  if (process.platform !== 'win32' || !safeStorage.isEncryptionAvailable()) throw new Error('Windows encryption unavailable');
}

function configureIPC() {
  handle('workspace:load', async () => validateWorkspace(await loadJSON('preview-workspace.json', previewWorkspace())));
  handle('workspace:save', async value => { validateWorkspace(value); await atomicJSON('preview-workspace.json', value); });
  handle('workspace:export', async text => {
    if (typeof text !== 'string' || text.length > 2000000) throw new Error('Invalid export');
    const result = await dialog.showSaveDialog(window, { defaultPath: 'OpenGrokBot-preview.txt', filters: [{ name: 'Text file', extensions: ['txt'] }] });
    if (result.canceled) return false;
    await writeFile(result.filePath, text, { encoding: 'utf8', mode: 0o600 });
    return true;
  });
  handle('docs:open', async url => { if (!documentation.has(url)) throw new Error('Unapproved URL'); await shell.openExternal(url); });
  handle('window:action', async action => {
    if (action === 'minimize') window.minimize();
    else if (action === 'maximize') { if (window.isMaximized()) window.unmaximize(); else window.maximize(); }
    else if (action === 'close') window.close();
  });
  handle('vault:list', async () => {
    requireVault();
    const values = await loadJSON('vault.json', []);
    return values.map(({ id, title }) => ({ id, title }));
  });
  handle('vault:save', async (title, value) => {
    requireVault();
    if (typeof title !== 'string' || !title.trim() || title.length > 200 || typeof value !== 'string' || !value || value.length > 100000) throw new Error('Invalid secret');
    const items = await loadJSON('vault.json', []);
    items.push({ id: randomUUID(), title, encrypted: safeStorage.encryptString(value).toString('base64') });
    await atomicJSON('vault.json', items);
  });
  handle('vault:read', async id => {
    requireVault();
    const item = (await loadJSON('vault.json', [])).find(x => x.id === id);
    if (!item) throw new Error('Missing item');
    return safeStorage.decryptString(Buffer.from(item.encrypted, 'base64'));
  });
  handle('vault:delete', async id => {
    requireVault();
    const values = await loadJSON('vault.json', []);
    await atomicJSON('vault.json', values.filter(x => x.id !== id));
  });
}

app.whenReady().then(() => {
  configureIPC();
  window = new BrowserWindow({ width: 1370, height: 940, minWidth: 860, minHeight: 620, frame: false, backgroundColor: '#111111', title: 'OpenGrokBot', webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false } });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.webContents.session.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  window.loadFile(rendererFile);
});
app.on('window-all-closed', () => app.quit());
