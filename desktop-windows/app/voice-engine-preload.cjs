// The hidden local-voice window may only report download progress. It has no other access to the app.
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('ogbVoiceProgress', value => ipcRenderer.send('localvoice:progress', { kind: String(value?.kind || ''), loaded: Number(value?.loaded) || 0, total: Number(value?.total) || 0 }));
