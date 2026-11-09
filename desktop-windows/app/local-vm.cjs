const {spawn,execFile}=require('node:child_process');
const tools=require('./vm-tools.cjs');
const downloads=require('./vm-download.cjs');
const sleep=ms=>LocalVMs.wait(ms);
const {access,mkdir,writeFile,unlink}=require('node:fs/promises');
const path=require('node:path');
const {randomBytes}=require('node:crypto');
const {safeStorage,nativeImage}=require('electron');
class LocalVMs{
 constructor({getBot,load,save,root}){Object.assign(this,{getBot,load,save,root});this.records=null;this.busy=new Set();this.loading=null;}
 async init(){if(!this.records){this.loading||=this.load().then(value=>{this.records=value||{};for(const [id,record] of Object.entries(this.records))if(['installing','verifying'].includes(record.state))setTimeout(()=>this.watch(id),0);}).catch(error=>{this.loading=null;throw error;});await this.loading;}}
 async executable(){const candidates=[path.join(process.env.ProgramFiles||'C:\\Program Files','Oracle','VirtualBox','VBoxManage.exe'),path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Oracle','VirtualBox','VBoxManage.exe')];for(const candidate of candidates)try{await access(candidate);return candidate;}catch{}throw new Error('Install VirtualBox 7.2 or newer, then reopen VM setup.');}
 async run(args,timeout=120000){const executable=await this.executable();return new Promise((resolve,reject)=>{let output='',error='';const child=spawn(executable,args,{shell:false,windowsHide:true,stdio:['ignore','pipe','pipe']});const timer=setTimeout(()=>{child.kill();reject(new Error('VirtualBox took too long. Check its console for setup progress before retrying.'));},timeout);child.stdout.on('data',data=>{if(output.length<8192)output+=data.toString();});child.stderr.on('data',data=>{if(error.length<4096)error+=data.toString();});child.on('error',()=>{clearTimeout(timer);reject(new Error('VirtualBox could not start.'));});child.on('close',code=>{clearTimeout(timer);if(code===0)resolve(output);else{const failure=new Error((tools.friendlyGuestError(error)||'VirtualBox reported a problem.')+' '+error.slice(0,500));failure.detail=error;reject(failure);}});});}
 async status(id){await this.init();let installed=true;try{await this.executable();}catch{installed=false;}const record=this.records[id];const missing=!!record&&installed&&!(await this.exists(record.name));const stale=record&&['installing','verifying'].includes(record.state)&&Date.now()-(record.installStartedAt||0)>20*60000;return {installed,missing,canRetry:!!record&&!missing&&(record.state==='failed'||stale),clipboard:record?.clipboard||'disabled',noLock:(record||this.options||{}).noLock!==false,sudo:(record||this.options||{}).sudo!==false,busy:this.busy.has(id),assigned:!!record,name:record?.name,state:missing?'missing':record?.state,hasCredentials:!!record?.password,commandsEnabled:!!record?.commandsEnabled,shared:!!record?.shared,progress:record?.progress||'',autoStart:!!record?.autoStart,autoLogin:(record||this.options||{}).autoLogin!==false,hypervisorNote:await this.hypervisorPresent()?tools.HYPERVISOR_NOTE:''};}
 async setup(id,image){
  await this.init();const bot=this.getBot(id);if(!bot)throw new Error('Choose a Bot.');if(this.busy.has(bot.id))throw new Error('VM setup is already running.');if(this.records[bot.id])return this.open(bot.id);
  if(typeof image!=='string'||!path.isAbsolute(image)||!['.iso','.ova'].includes(path.extname(image).toLowerCase()))throw new Error('Choose an Ubuntu Linux ISO or Linux OVA template.');await access(image);await this.executable();
  this.busy.add(bot.id);const name='OpenGrokBot-'+bot.id,folder=path.join(this.root,bot.id);
  let passwordFile;
  try{
   await mkdir(folder,{recursive:true});
   if(path.extname(image).toLowerCase()==='.ova'){
    await this.run(['import',image,'--vsys','0','--vmname',name,'--basefolder',folder,'--memory','4096','--cpus','2'],600000);
    this.records[bot.id]={name,state:'created'};await this.save(this.records);
    await this.run(['modifyvm',name,'--nic1','nat','--clipboard-mode','disabled','--drag-and-drop','disabled']);
    this.records[bot.id].state='ready';await this.save(this.records);await this.open(bot.id);
   }else{
    if(!safeStorage.isEncryptionAvailable())throw new Error('Unlock Windows encryption before creating guest credentials.');
    const password=randomBytes(24).toString('base64url');
    await this.run(['createvm','--name',name,'--ostype','Ubuntu_64','--basefolder',folder,'--register']);
    const chosen=this.options||{};this.records[bot.id]={name,state:'configuring',username:'bot',password:safeStorage.encryptString(password).toString('base64'),autoLogin:chosen.autoLogin!==false,noLock:chosen.noLock!==false,sudo:chosen.sudo!==false,clipboard:'hosttoguest',installStartedAt:Date.now()};await this.save(this.records);
    // Paravirtualisation is always off: with Windows' own hypervisor active VirtualBox falls back to a slower path and the
    // default (KVM) then freezes the Ubuntu installer at "Loading essential drivers". Without it the cost is negligible.
    await this.modify(name,['--memory','4096','--cpus','2','--nic1','nat','--clipboard-mode','hosttoguest','--drag-and-drop','disabled','--graphicscontroller','vmsvga','--vram','128','--ioapic','on','--paravirt-provider','none']);
    const configured=await this.info(name);if(configured.paravirtprovider&&configured.paravirtprovider!=='none')await this.modify(name,['--paravirt-provider','none']);
    await this.run(['storagectl',name,'--name','SATA','--add','sata','--controller','IntelAhci']);
    const disk=path.join(folder,'linux.vdi');await this.run(['createmedium','disk','--filename',disk,'--size','32768','--format','VDI']);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','0','--device','0','--type','hdd','--medium',disk]);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','1','--device','0','--type','dvddrive','--medium','emptydrive']);
    passwordFile=path.join(folder,'installer-password.txt');await writeFile(passwordFile,password,{mode:0o600,flag:'wx'});
    await this.run(['unattended','install',name,'--iso='+image,'--user=bot','--user-password-file='+passwordFile,'--full-user-name=Bot','--hostname=bot-'+bot.id.slice(0,8)+'.local','--install-additions','--post-install-command='+tools.postInstallCommand(this.records[bot.id]),'--start-vm=gui'],600000);
    this.records[bot.id].state='installing';this.records[bot.id].installStartedAt=Date.now();this.records[bot.id].progress='Installing Ubuntu (this takes a while)…';await this.save(this.records);this.watch(bot.id);
   }
   return this.status(bot.id);
  }catch(error){if(this.records[bot.id]){this.records[bot.id].state='setup-incomplete';await this.save(this.records);}throw error;}
  finally{if(passwordFile)await unlink(passwordFile).catch(()=>{});this.busy.delete(bot.id);}
 }

 /** Whether Windows' own hypervisor (Hyper-V, Memory Integrity) is active. Unknown counts as yes: the safe setting costs little. */
 async hypervisorPresent(){if(this.hypervisor!==undefined)return this.hypervisor;return this.hypervisor=await new Promise(resolve=>execFile('powershell.exe',['-NoProfile','-NonInteractive','-Command','(Get-CimInstance Win32_ComputerSystem).HypervisorPresent'],{windowsHide:true,timeout:15000},(error,stdout)=>resolve(error?true:/true/i.test(String(stdout)))));}
 async info(name){try{return tools.parseVMInfo(await this.run(['showvminfo',name,'--machinereadable'],15000));}catch{return {};}}
 async setProgress(id,state,progress){const record=this.records[id];if(!record)return;if(state)record.state=state;record.progress=progress;await this.save(this.records);this.onProgress?.(id,{state:record.state,progress});}
 /** Starts the VM (without a window) if it is stopped, saved or paused, so a Bot command or another computer never finds it asleep. */
 async ensureRunning(id,{wait=false}={}){
  await this.init();const record=this.records[id];if(!record)return;
  let info=await this.info(record.name),state=tools.vmState(info);
  if(state==='paused')await this.run(['controlvm',record.name,'resume'],30000).catch(()=>{});
  else if(['poweroff','saved','aborted'].includes(state))await this.run(['startvm',record.name,'--type','headless'],60000).catch(()=>{});
  if(!wait)return;
  for(let i=0;i<40;i++){info=await this.info(record.name);if(tools.vmState(info)==='running'&&tools.guestRunLevel(info)>=2)return;await sleep(3000);}
 }
 /** Opens the VM's window. A VM that is already running is not started again (that was the "already locked by a session" message). */
 async open(id){
  await this.init();const record=this.records[id];if(!record)throw new Error('Set up the shared Linux VM first.');
  const state=tools.vmState(await this.info(record.name));
  if(state==='running'){try{const exe=(await this.executable()).replace(/VBoxManage\.exe$/i,'VirtualBoxVM.exe');const child=spawn(exe,['--startvm',record.name],{detached:true,stdio:'ignore',windowsHide:false});child.on('error',()=>{});child.unref();}catch{}return this.status(id);}
  try{if(state==='paused')await this.run(['controlvm',record.name,'resume'],30000);else await this.run(['startvm',record.name,'--type','gui'],60000);}
  catch(error){if(!(tools.lockedError(error.detail||error.message)&&tools.vmState(await this.info(record.name))==='running'))throw error;}
  return this.status(id);
 }
 /** Whether VirtualBox still has this VM registered (it may have been deleted by hand). */
 async exists(name){try{await this.run(['showvminfo',name,'--machinereadable'],15000);return true;}catch(error){return !/VBOX_E_OBJECT_NOT_FOUND|Could not find a registered machine/i.test(error.detail||error.message);}}
 /** modifyvm, retried for about 30 s while VirtualBox still holds the session lock after a power-off. */
 async modify(name,args){for(let i=0;;i++){try{return await this.run(['modifyvm',name,...args]);}catch(error){if(i>=10||!tools.lockedError(error.detail||error.message))throw error;await sleep(3000);}}}
 async waitFor(name,wanted,ms){const end=Date.now()+ms;while(Date.now()<end){if(wanted.includes(tools.vmState(await this.info(name))))return true;await sleep(2000);}return false;}
 /** Shuts the guest down cleanly (forcing it after 90 s), so saved settings can change. */
 async powerOff(name){if(tools.vmState(await this.info(name))==='poweroff')return;await this.run(['controlvm',name,'acpipowerbutton'],30000).catch(()=>{});if(!await this.waitFor(name,['poweroff','aborted'],90000)){await this.run(['controlvm',name,'poweroff'],30000).catch(()=>{});await this.waitFor(name,['poweroff','aborted'],30000);}}
 async startHeadless(name){for(let i=0;i<10;i++){try{await this.run(['startvm',name,'--type','headless'],60000);return;}catch(error){if(tools.vmState(await this.info(name))==='running')return;if(!tools.lockedError(error.detail||error.message))throw error;await sleep(3000);}}}
 async restart(id){const record=this.records[id];if(!record)return;await this.powerOff(record.name);await this.startHeadless(record.name);}
 /** Watches a new VM until Ubuntu and the guest tools are up, proves a command works, then marks it ready. See tools.watchDecision. */
 watch(id){
  if(LocalVMs.noWatch)return;
  this.watching||=new Set();if(this.watching.has(id))return;this.watching.add(id);
  (async()=>{
   const s={vmState:'unknown',level:-1,levelSince:Date.now(),readySince:0,offPolls:0,testingSince:0,rebooted:false,lastError:''};
   try{for(;;){
    await sleep(10000);const record=this.records[id];if(!record||['ready','failed'].includes(record.state))break;
    const info=await this.info(record.name),level=tools.guestRunLevel(info);
    s.now=Date.now();s.vmState=tools.vmState(info);s.offPolls=s.vmState==='running'?0:s.offPolls+1;
    if(level!==s.level){s.level=level;s.levelSince=s.now;}
    if(level>=2){s.readySince||=s.now;}else{s.readySince=0;s.testingSince=0;}
    const step=tools.watchDecision(s);
    if(step.action==='start'){await this.startHeadless(record.name).catch(()=>{});s.offPolls=0;}
    else if(step.action==='reboot'){s.rebooted=true;await this.setProgress(id,step.state,step.progress);await this.restart(id).catch(()=>{});s.level=-1;s.readySince=0;s.testingSince=0;continue;}
    else if(step.action==='fail'){await this.setProgress(id,'failed',step.progress);break;}
    else if(step.action==='test'){
     s.testingSince||=s.now;await this.setProgress(id,step.state,step.progress);
     try{await this.guestRun(id,['/bin/true']);record.commandsEnabled=true;record.shared=true;await this.save(this.records);await this.setProgress(id,'ready','Ready. Test command passed.');break;}
     catch(error){s.lastError=error.detail||error.message;if(/not able to logon|AUTHENTICATION/i.test(s.lastError)){await this.setProgress(id,'failed',tools.friendlyGuestError(s.lastError));break;}}
     continue;
    }
    if(record.progress!==step.progress||record.state!==step.state)await this.setProgress(id,step.state,step.progress);
   }}catch{}finally{this.watching.delete(id);}
  })();
 }
 async retry(id){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the shared Linux VM first.');record.state='installing';record.installStartedAt=Date.now();record.progress='Checking the VM again…';if(tools.vmState(await this.info(record.name))!=='running')await this.startHeadless(record.name).catch(()=>{});await this.save(this.records);this.watch(id);return this.status(id);}
 /** Starts the VM without a window every time this Windows user signs in. */
 async setAutoStart(id,enabled){
  await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');
  const exe=await this.executable(),task='OpenGrokBot VM '+id.slice(0,8);
  await new Promise((resolve,reject)=>execFile('schtasks.exe',enabled?['/Create','/F','/SC','ONLOGON','/TN',task,'/TR',`"${exe}" startvm "${record.name}" --type headless`]:['/Delete','/F','/TN',task],{windowsHide:true,timeout:20000},error=>error&&enabled?reject(new Error('Windows would not create the sign-in task.')):resolve()));
  record.autoStart=enabled===true;await this.save(this.records);return this.status(id);
 }
 /** Turns on automatic sign-in (affects new installs only) and records the choice. */
 async setAutoLogin(id,enabled){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');record.autoLogin=enabled===true;await this.save(this.records);return this.status(id);}
 /** Everything in one go: VirtualBox, the Ubuntu image, the VM, the install, and the checks. Progress goes to onProgress({ step, text }). */
 async setupAll(id,{onProgress=()=>{},fetcher=fetch}={}){
  await this.init();const bot=this.getBot(id);if(!bot)throw new Error('Choose the main Bot.');
  if(this.records[bot.id]&&!(await this.exists(this.records[bot.id].name))){delete this.records[bot.id];await this.save(this.records);}
  if(this.records[bot.id])return this.open(bot.id);
  const percent=p=>p.total?` ${Math.round(p.received/p.total*100)}%`:'';
  try{await this.executable();}catch{
   onProgress({step:'virtualbox',text:'Downloading VirtualBox…'});
   const installer=await downloads.ensureVirtualBoxInstaller({dir:path.join(this.root,'downloads'),fetcher,onProgress:p=>onProgress({step:'virtualbox',text:'Downloading VirtualBox…'+percent(p)})});
   onProgress({step:'virtualbox',text:'Installing VirtualBox (Windows will ask for permission)…'});
   await new Promise((resolve,reject)=>{const child=spawn(installer,['--silent','--ignore-reboot'],{stdio:'ignore',windowsHide:true});child.on('error',error=>reject(new Error('VirtualBox could not be installed: '+error.message)));child.on('exit',code=>code===0||code===3010?resolve():reject(new Error('The VirtualBox installer stopped (code '+code+'). Install VirtualBox yourself, then try again.')));});
   await this.executable();
  }
  const space=await require('node:fs/promises').statfs?.(this.root).catch(()=>null);
  if(space&&space.bavail*space.bsize<25e9)throw new Error('At least 25 GB of free disk space is needed for the Ubuntu image and the VM.');
  onProgress({step:'ubuntu',text:'Downloading Ubuntu 24.04 (about 6 GB)…'});
  const image=await downloads.ensureUbuntuISO({root:this.root,fetcher,onProgress:p=>onProgress({step:'ubuntu',text:'Downloading Ubuntu 24.04 (about 6 GB)…'+percent(p)})});
  onProgress({step:'create',text:'Creating the VM and starting the Ubuntu install…'});
  await this.setup(bot.id,image);
  return this.status(bot.id);
 }
 /** Whether other computers on this account may run commands in this Bot's VM. Off until the human turns it on. */
 async setShared(id,enabled){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');record.shared=enabled===true;await this.save(this.records);return this.status(id);}
 /** VMs this computer shares: set up, guest commands on, and sharing turned on. */
 async sharedList(){await this.init();return Object.entries(this.records).filter(([,record])=>record?.shared&&record.commandsEnabled&&record.password).map(([botID,record])=>({botID,name:record.name,state:record.state||'ready'}));}
 async setCommands(id,enabled){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');record.commandsEnabled=enabled===true;await this.save(this.records);return this.status(id);}
 async execute(id,argv){await this.init();await this.ensureRunning(id,{wait:true});const record=this.records[id];if(!record?.commandsEnabled||!record.password)throw new Error('Enable Bot commands in VM settings. A running Linux guest with VirtualBox Guest Additions and saved login is required.');return this.guestRun(id,argv);}
 /** Runs one command in the guest. VERR_DUPLICATE and other transient session errors are retried after 10 s. The password goes through a file that is deleted afterwards. */
 async guestRun(id,argv,password){
  await this.init();const record=this.records[id];if(!record?.password)throw new Error('This VM has no saved guest login.');
  if(!Array.isArray(argv)||!argv.length||argv.length>16||argv.some(x=>typeof x!=='string'||x.includes('\0'))||!argv[0].startsWith('/')||argv.join('').length>16000)throw new Error('Use 1–16 guest arguments, starting with an absolute Linux executable path.');
  const login=password?{username:record.username,password}:await this.credentials(id);
  for(let attempt=0;;attempt++){
   const passwordFile=path.join(this.root,id,'guest-command-'+randomBytes(8).toString('hex')+'.txt');
   try{await mkdir(path.dirname(passwordFile),{recursive:true});await writeFile(passwordFile,login.password,{mode:0o600,flag:'wx'});return await this.run(['guestcontrol',record.name,'run','--exe='+argv[0],'--username='+login.username,'--passwordfile='+passwordFile,'--timeout=60000','--wait-stdout','--wait-stderr','--',...argv],65000);}
   catch(error){const detail=error.detail||error.message;if(/not able to logon|AUTHENTICATION/i.test(detail)){const wrong=new Error(tools.friendlyGuestError(detail));wrong.detail=detail;throw wrong;}if(attempt>=3||!tools.retryableGuest(detail))throw error;await sleep(10000);}
   finally{await unlink(passwordFile).catch(()=>{});}
  }
 }
 /** Saves a new guest password after proving it works. */
 async updatePassword(id,password){
  await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');
  if(typeof password!=='string'||!password||password.length>200||password.includes('\0'))throw new Error('Enter the guest password.');
  if(!safeStorage.isEncryptionAvailable())throw new Error('Unlock Windows encryption first.');
  await this.ensureRunning(id,{wait:true});
  try{await this.guestRun(id,['/bin/true'],password);}catch(error){throw new Error(/not able to logon|AUTHENTICATION/i.test(error.detail||error.message)?'That password did not work for the bot account in the VM.':error.message);}
  record.password=safeStorage.encryptString(password).toString('base64');if(record.state==='failed'){record.state='ready';record.progress='Ready. Test command passed.';}await this.save(this.records);return this.status(id);
 }
 /** Changes the saved clipboard mode: the VM is shut down, the setting saved, the VM started again, and the saved file checked. */
 async setClipboard(id,mode){
  await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');
  if(!tools.CLIPBOARD_MODES[mode])throw new Error('Choose a clipboard setting.');
  const info=await this.info(record.name),wasRunning=tools.vmState(info)==='running';
  await this.powerOff(record.name);await this.modify(record.name,['--clipboard-mode',mode]);
  const file=(await this.info(record.name)).CfgFile;
  if(file){const saved=tools.savedClipboardMode(await require('node:fs/promises').readFile(file,'utf8').catch(()=>''));if(saved.toLowerCase()!==tools.CLIPBOARD_MODES[mode].toLowerCase()&&!(mode==='disabled'&&saved==='Disabled'))throw new Error('VirtualBox did not save the clipboard setting (it reads '+saved+').');}
  record.clipboard=mode;await this.save(this.records);
  if(wasRunning||record.state==='ready')await this.startHeadless(record.name);
  return this.status(id);
 }
 /** Deletes the VM, its disk, the sign-in task and the record. */
 async remove(id){
  await this.init();const record=this.records[id];if(!record)return this.status(id);
  if(await this.exists(record.name)){await this.powerOff(record.name).catch(()=>{});for(let i=0;i<10;i++){try{await this.run(['unregistervm',record.name,'--delete'],120000);break;}catch(error){if(!tools.lockedError(error.detail||error.message)||i===9)throw error;await sleep(3000);}}}
  if(record.autoStart)await this.setAutoStart(id,false).catch(()=>{});
  delete this.records[id];await this.save(this.records);return this.status(id);
 }
 /** Settings for the next VM (before one exists). */
 setOptions(options){this.options={...(this.options||{}),...options};}
 async preview(id){await this.init();id=this.getBot(id)?.id;if(id)await this.ensureRunning(id);const record=id&&this.records[id];if(!record)return {title:'VM not set up',url:'Set up this Bot’s Linux VM on the host desktop.',imageData:null};const file=path.join(this.root,id,'preview-'+randomBytes(8).toString('hex')+'.png');try{await this.run(['controlvm',record.name,'screenshotpng',file,'0'],10000);const image=nativeImage.createFromPath(file);if(image.isEmpty())throw new Error('The VM display is unavailable.');const bytes=image.resize({width:900}).toJPEG(60);if(bytes.length>2000000)throw new Error('The VM display preview is too large.');return {title:record.name,url:'VirtualBox · local Linux VM',imageData:bytes.toString('base64')};}finally{await unlink(file).catch(()=>{});}}
 async credentials(id){await this.init();const record=this.records[id];if(!record?.password)throw new Error('This VM uses the credentials supplied by its template.');if(!safeStorage.isEncryptionAvailable())throw new Error('Unlock Windows encryption first.');return {username:record.username,password:safeStorage.decryptString(Buffer.from(record.password,'base64'))};}
}
/** Replaced in tests so retries do not take real seconds. */
LocalVMs.wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
module.exports={LocalVMs};
