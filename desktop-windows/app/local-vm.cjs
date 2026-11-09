const {spawn,execFile}=require('node:child_process');
const tools=require('./vm-tools.cjs');
const downloads=require('./vm-download.cjs');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const {access,mkdir,writeFile,unlink}=require('node:fs/promises');
const path=require('node:path');
const {randomBytes}=require('node:crypto');
const {safeStorage,nativeImage}=require('electron');
class LocalVMs{
 constructor({getBot,load,save,root}){Object.assign(this,{getBot,load,save,root});this.records=null;this.busy=new Set();this.loading=null;}
 async init(){if(!this.records){this.loading||=this.load().then(value=>{this.records=value||{};for(const [id,record] of Object.entries(this.records))if(['installing','verifying'].includes(record.state))setTimeout(()=>this.watch(id),0);}).catch(error=>{this.loading=null;throw error;});await this.loading;}}
 async executable(){const candidates=[path.join(process.env.ProgramFiles||'C:\\Program Files','Oracle','VirtualBox','VBoxManage.exe'),path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Oracle','VirtualBox','VBoxManage.exe')];for(const candidate of candidates)try{await access(candidate);return candidate;}catch{}throw new Error('Install VirtualBox 7.2 or newer, then reopen VM setup.');}
 async run(args,timeout=120000){const executable=await this.executable();return new Promise((resolve,reject)=>{let output='',error='';const child=spawn(executable,args,{shell:false,windowsHide:true,stdio:['ignore','pipe','pipe']});const timer=setTimeout(()=>{child.kill();reject(new Error('VirtualBox took too long. Check its console for setup progress before retrying.'));},timeout);child.stdout.on('data',data=>{if(output.length<8192)output+=data.toString();});child.stderr.on('data',data=>{if(error.length<4096)error+=data.toString();});child.on('error',()=>{clearTimeout(timer);reject(new Error('VirtualBox could not start.'));});child.on('close',code=>{clearTimeout(timer);code===0?resolve(output):reject(new Error('VirtualBox could not complete setup. '+error.slice(0,500)));});});}
 async status(id){await this.init();let installed=true;try{await this.executable();}catch{installed=false;}const record=this.records[id];return {installed,busy:this.busy.has(id),assigned:!!record,name:record?.name,state:record?.state,hasCredentials:!!record?.password,commandsEnabled:!!record?.commandsEnabled,shared:!!record?.shared,progress:record?.progress||'',autoStart:!!record?.autoStart,autoLogin:record?.autoLogin!==false,hypervisorNote:await this.hypervisorPresent()?tools.HYPERVISOR_NOTE:''};}
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
    this.records[bot.id]={name,state:'configuring',username:'bot',password:safeStorage.encryptString(password).toString('base64')};await this.save(this.records);
    // With Windows' own hypervisor active VirtualBox falls back to a slower path, and the default paravirtualisation then freezes the Ubuntu installer.
    await this.run(['modifyvm',name,'--memory','4096','--cpus','2','--nic1','nat','--clipboard-mode','disabled','--drag-and-drop','disabled','--graphicscontroller','vmsvga','--vram','128','--ioapic','on',...(await this.hypervisorPresent()?['--paravirt-provider','none']:[])]);
    await this.run(['storagectl',name,'--name','SATA','--add','sata','--controller','IntelAhci']);
    const disk=path.join(folder,'linux.vdi');await this.run(['createmedium','disk','--filename',disk,'--size','32768','--format','VDI']);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','0','--device','0','--type','hdd','--medium',disk]);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','1','--device','0','--type','dvddrive','--medium','emptydrive']);
    passwordFile=path.join(folder,'installer-password.txt');await writeFile(passwordFile,password,{mode:0o600,flag:'wx'});
    await this.run(['unattended','install',name,'--iso='+image,'--user=bot','--user-password-file='+passwordFile,'--full-user-name=Bot','--hostname=bot-'+bot.id.slice(0,8)+'.local','--install-additions','--post-install-command='+tools.postInstallCommand(this.records[bot.id].autoLogin!==false),'--start-vm=gui'],600000);
    this.records[bot.id].state='installing';this.records[bot.id].progress='Installing Ubuntu (this takes a while)…';await this.save(this.records);this.watch(bot.id);
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
  if(state==='running'){try{const exe=(await this.executable()).replace(/VBoxManage\.exe$/i,'VirtualBoxVM.exe');spawn(exe,['--startvm',record.name],{detached:true,stdio:'ignore',windowsHide:false}).unref();}catch{}return this.status(id);}
  if(state==='paused')await this.run(['controlvm',record.name,'resume'],30000);
  else await this.run(['startvm',record.name,'--type','gui'],60000);
  return this.status(id);
 }
 /** Watches a new VM until Ubuntu and Guest Additions are up, then proves a command works and marks it ready. */
 watch(id){
  this.watching||=new Set();if(this.watching.has(id))return;this.watching.add(id);
  (async()=>{
   const end=Date.now()+3*3600000;let off=0,failures=0;
   try{while(Date.now()<end){
    await sleep(15000);const record=this.records[id];if(!record||['ready','failed'].includes(record.state))break;
    const info=await this.info(record.name),state=tools.vmState(info),level=tools.guestRunLevel(info);
    if(state==='running'&&level>=2){
     off=0;await this.setProgress(id,'verifying','Checking that commands work in the VM…');
     record.commandsEnabled=true;record.shared=true;await this.save(this.records);
     try{await this.execute(id,['/bin/true']);await this.setProgress(id,'ready','Ready. Test command passed.');break;}
     catch(error){if(++failures>=8){await this.setProgress(id,'failed','Guest Additions are running but a test command failed: '+String(error.message).slice(0,200)+' Use Retry.');break;}}
    }else if(state==='running'){off=0;await this.setProgress(id,'installing',level>0?'Installing Guest Additions…':'Installing Ubuntu (this takes a while)…');}
    else if(['poweroff','aborted','saved'].includes(state)&&++off>=4){off=0;await this.ensureRunning(id);}
   }}catch{}finally{this.watching.delete(id);}
  })();
 }
 async retry(id){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the shared Linux VM first.');record.state='installing';record.progress='Checking the VM again…';await this.save(this.records);this.watch(id);return this.status(id);}
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
 async execute(id,argv){await this.init();await this.ensureRunning(id,{wait:true});const record=this.records[id];if(!record?.commandsEnabled||!record.password)throw new Error('Enable Bot commands in VM settings. A running Linux guest with VirtualBox Guest Additions and saved login is required.');if(!Array.isArray(argv)||!argv.length||argv.length>16||argv.some(x=>typeof x!=='string'||x.includes('\0'))||!argv[0].startsWith('/')||argv.join('').length>16000)throw new Error('Use 1–16 guest arguments, starting with an absolute Linux executable path.');const login=await this.credentials(id),passwordFile=path.join(this.root,id,'guest-command-'+randomBytes(8).toString('hex')+'.txt');try{await writeFile(passwordFile,login.password,{mode:0o600,flag:'wx'});return await this.run(['guestcontrol',record.name,'run','--exe='+argv[0],'--username='+login.username,'--passwordfile='+passwordFile,'--timeout=60000','--wait-stdout','--wait-stderr','--',...argv],65000);}finally{await unlink(passwordFile).catch(()=>{});}}
 async preview(id){await this.init();id=this.getBot(id)?.id;if(id)await this.ensureRunning(id);const record=id&&this.records[id];if(!record)return {title:'VM not set up',url:'Set up this Bot’s Linux VM on the host desktop.',imageData:null};const file=path.join(this.root,id,'preview-'+randomBytes(8).toString('hex')+'.png');try{await this.run(['controlvm',record.name,'screenshotpng',file,'0'],10000);const image=nativeImage.createFromPath(file);if(image.isEmpty())throw new Error('The VM display is unavailable.');const bytes=image.resize({width:900}).toJPEG(60);if(bytes.length>2000000)throw new Error('The VM display preview is too large.');return {title:record.name,url:'VirtualBox · local Linux VM',imageData:bytes.toString('base64')};}finally{await unlink(file).catch(()=>{});}}
 async credentials(id){await this.init();const record=this.records[id];if(!record?.password)throw new Error('This VM uses the credentials supplied by its template.');if(!safeStorage.isEncryptionAvailable())throw new Error('Unlock Windows encryption first.');return {username:record.username,password:safeStorage.decryptString(Buffer.from(record.password,'base64'))};}
}
module.exports={LocalVMs};
