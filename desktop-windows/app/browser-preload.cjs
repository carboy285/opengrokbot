const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('botBrowser',{
 ready:()=>ipcRenderer.invoke('bot-browser:ready'),navigate:url=>ipcRenderer.invoke('bot-browser:navigate',url),back:()=>ipcRenderer.invoke('bot-browser:back'),forward:()=>ipcRenderer.invoke('bot-browser:forward'),reload:()=>ipcRenderer.invoke('bot-browser:reload'),clear:()=>ipcRenderer.invoke('bot-browser:clear'),
 onState:callback=>ipcRenderer.on('bot-browser:state',(_event,value)=>callback(value))
});
