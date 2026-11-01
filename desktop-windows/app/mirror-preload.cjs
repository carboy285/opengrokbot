const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('mirror',{
 browser:(id,kind)=>ipcRenderer.invoke('mirror:browser',id,kind),
 retry:()=>ipcRenderer.invoke('mirror:retry'),
 discover:()=>ipcRenderer.invoke('mirror:discover'),select:id=>ipcRenderer.invoke('mirror:select',id),
 command:value=>ipcRenderer.invoke('mirror:command',value),pin:(id,value)=>ipcRenderer.invoke('mirror:pin',id,value),
 close:()=>ipcRenderer.invoke('mirror:close'),
 onChange:callback=>{const listener=(_event,value)=>callback(value);ipcRenderer.on('mirror:changed',listener);return()=>ipcRenderer.removeListener('mirror:changed',listener);}
});
