const {spawn}=require('node:child_process');
const {access,mkdir,writeFile,unlink}=require('node:fs/promises');
const path=require('node:path');
const {randomBytes}=require('node:crypto');
const {safeStorage}=require('electron');
class LocalVMs{
 constructor({getBot,load,save,root}){Object.assign(this,{getBot,load,save,root});this.records=null;this.busy=new Set();this.loading=null;}
 async init(){if(!this.records){this.loading||=this.load().then(value=>{this.records=value||{};}).catch(error=>{this.loading=null;throw error;});await this.loading;}}
 async executable(){const candidates=[path.join(process.env.ProgramFiles||'C:\\Program Files','Oracle','VirtualBox','VBoxManage.exe'),path.join(process.env['ProgramFiles(x86)']||'C:\\Program Files (x86)','Oracle','VirtualBox','VBoxManage.exe')];for(const candidate of candidates)try{await access(candidate);return candidate;}catch{}throw new Error('Install VirtualBox 7.2 or newer, then reopen VM setup.');}
 async run(args,timeout=120000){const executable=await this.executable();return new Promise((resolve,reject)=>{let output='',error='';const child=spawn(executable,args,{shell:false,windowsHide:true,stdio:['ignore','pipe','pipe']});const timer=setTimeout(()=>{child.kill();reject(new Error('VirtualBox took too long. Check its console for setup progress before retrying.'));},timeout);child.stdout.on('data',data=>{if(output.length<8192)output+=data.toString();});child.stderr.on('data',data=>{if(error.length<4096)error+=data.toString();});child.on('error',()=>{clearTimeout(timer);reject(new Error('VirtualBox could not start.'));});child.on('close',code=>{clearTimeout(timer);code===0?resolve(output):reject(new Error('VirtualBox could not complete setup. '+error.slice(0,500)));});});}
 async status(id){await this.init();let installed=true;try{await this.executable();}catch{installed=false;}const record=this.records[id];return {installed,busy:this.busy.has(id),assigned:!!record,name:record?.name,state:record?.state,hasCredentials:!!record?.password,commandsEnabled:!!record?.commandsEnabled};}
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
    await this.run(['modifyvm',name,'--memory','4096','--cpus','2','--nic1','nat','--clipboard-mode','disabled','--drag-and-drop','disabled','--graphicscontroller','vmsvga','--vram','128','--ioapic','on']);
    await this.run(['storagectl',name,'--name','SATA','--add','sata','--controller','IntelAhci']);
    const disk=path.join(folder,'linux.vdi');await this.run(['createmedium','disk','--filename',disk,'--size','32768','--format','VDI']);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','0','--device','0','--type','hdd','--medium',disk]);
    await this.run(['storageattach',name,'--storagectl','SATA','--port','1','--device','0','--type','dvddrive','--medium','emptydrive']);
    passwordFile=path.join(folder,'installer-password.txt');await writeFile(passwordFile,password,{mode:0o600,flag:'wx'});
    await this.run(['unattended','install',name,'--iso='+image,'--user=bot','--user-password-file='+passwordFile,'--full-user-name=Bot','--hostname=bot-'+bot.id.slice(0,8)+'.local','--install-additions','--start-vm=gui'],600000);
    this.records[bot.id].state='installing';await this.save(this.records);
   }
   return this.status(bot.id);
  }catch(error){if(this.records[bot.id]){this.records[bot.id].state='setup-incomplete';await this.save(this.records);}throw error;}
  finally{if(passwordFile)await unlink(passwordFile).catch(()=>{});this.busy.delete(bot.id);}
 }
 async open(id){await this.init();const record=this.records[id];if(!record)throw new Error('Set up this Bot’s Linux VM from its host desktop first.');await this.run(['startvm',record.name,'--type','gui'],60000);return this.status(id);}
 async setCommands(id,enabled){await this.init();const record=this.records[id];if(!record)throw new Error('Set up the VM first.');record.commandsEnabled=enabled===true;await this.save(this.records);return this.status(id);}
 async execute(id,argv){await this.init();const record=this.records[id];if(!record?.commandsEnabled||!record.password)throw new Error('Enable Bot commands in VM settings. A running Linux guest with VirtualBox Guest Additions and saved login is required.');if(!Array.isArray(argv)||!argv.length||argv.length>16||argv.some(x=>typeof x!=='string'||x.includes('\0'))||!argv[0].startsWith('/')||argv.join('').length>16000)throw new Error('Use 1–16 guest arguments, starting with an absolute Linux executable path.');const login=await this.credentials(id),passwordFile=path.join(this.root,id,'guest-command-'+randomBytes(8).toString('hex')+'.txt');try{await writeFile(passwordFile,login.password,{mode:0o600,flag:'wx'});return await this.run(['guestcontrol',record.name,'run','--exe='+argv[0],'--username='+login.username,'--passwordfile='+passwordFile,'--timeout=60000','--wait-stdout','--wait-stderr','--',...argv],65000);}finally{await unlink(passwordFile).catch(()=>{});}}
 async credentials(id){await this.init();const record=this.records[id];if(!record?.password)throw new Error('This VM uses the credentials supplied by its template.');if(!safeStorage.isEncryptionAvailable())throw new Error('Unlock Windows encryption first.');return {username:record.username,password:safeStorage.decryptString(Buffer.from(record.password,'base64'))};}
}
module.exports={LocalVMs};
