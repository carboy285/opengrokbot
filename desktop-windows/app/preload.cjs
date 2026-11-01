const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('desktop', {
  load: () => ipcRenderer.invoke('workspace:load'),
  save: value => ipcRenderer.invoke('workspace:save', value),
  export: text => ipcRenderer.invoke('workspace:export', text),
  openDocs: url => ipcRenderer.invoke('docs:open', url),
  windowAction: action => ipcRenderer.invoke('window:action', action),
  vaultList: () => ipcRenderer.invoke('vault:list'),
  vaultSave: (title, value) => ipcRenderer.invoke('vault:save', title, value),
  vaultRead: id => ipcRenderer.invoke('vault:read', id),
  vaultDelete: id => ipcRenderer.invoke('vault:delete', id)
});
