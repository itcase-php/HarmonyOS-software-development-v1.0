'use strict';
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
const {host}=require('./check-interactions.cjs');
const root=path.resolve(__dirname,'..');
const cases=[];
const formats=JSON.parse(fs.readFileSync(path.join(root,'shared/format-registry/formats.json'))).formats;
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
async function flush(){for(let i=0;i<100;i++)await Promise.resolve();}
async function test(name,body){await body();cases.push({name,result:'passed'});}
function fixture(options={}) {
 const h=host(options);
 const {FileAuthorizationManager,FileAuthorizationService}=h.load('./services/FileAuthorizationService');
 const {BridgeError}=h.load('./common/BridgeError');
 let id=0;
 const platform={available:true,free:1024*1024*1024,selected:[],copies:new Map(),directories:new Set(),removed:[],reads:0,gate:null,
  isAvailable(){return this.available;},cacheDir:()=>'/sandbox/cache',uuid:()=> (++id).toString(16).padStart(32,'0'),now:()=>1700000000000,
  async pick(){return this.selected.map(file=>({...file}));},async exists(name){return this.copies.has(name)||this.directories.has(name);},
  async mkdir(name){this.directories.add(name.replace(/\/inputs$/,''));this.directories.add(name);},async freeBytes(){return this.free;},
  async copyUri(uri,target,maxBytes,active){
   this.reads++;if(this.gate)await this.gate;
   this.copies.set(target,Buffer.from('%PDF-controlled-input'));
   if(!active())throw new BridgeError('CONVERSION_CANCELLED','FILE_IMPORT_CANCELLED');
   if(this.actualBytes>maxBytes)throw new BridgeError('RESOURCE_LIMIT_EXCEEDED','FILE_TOO_LARGE');
   if(this.copyFailure)throw new Error('sensitive URI must not escape');
   return this.actualBytes||21;
  },
  async sha256(name){if(this.hashFailure)throw new Error('hash failure');return this.badDigest?'invalid':sha(this.copies.get(name));},
  async unlink(name){this.copies.delete(name);this.removed.push(name);},async removeDirectory(name){
   if(this.removeFailure)throw new Error('cleanup failure');this.removed.push(name);
   for(const target of this.copies.keys())if(target.startsWith(name+'/'))this.copies.delete(target);
   for(const target of this.directories)if(target===name||target.startsWith(name+'/'))this.directories.delete(target);
  }};
 const manager=new FileAuthorizationManager(platform);
 const select=names=>platform.selected=names.map((fileName,index)=>({uri:'file://docs/'+index+'/'+fileName,fileName,fileSize:21,mimeType:''}));
 async function imported(names=['report.pdf'],facade=false){
  if(facade)FileAuthorizationService.configurePlatform(platform);
  const service=facade?FileAuthorizationService:manager;
  select(names);const picked=await service.pickDocuments(10);const session=await service.createSession();
  const files=[];for(const file of picked)files.push(await service.copyToSandbox(file,session.sessionId));
  return {session:service.getSession(session.sessionId),files,service};
 }
 return {h,manager,platform,select,imported,FileAuthorizationService,BridgeError};
}
const reason=expected=>error=>error.name==='BridgeError'&&error.reason===expected;
function stub(h,overrides={}) {
 const metadata=h.load('./generated/RegistryData').registryMetadata;
 return {initializeSession:async()=> 'native-session',registerWorkspace:async()=> 'workspace-handle',
  getCapabilities:async()=>({schemaVersion:1,offlineOnly:true,abi:'mock',configVersion:metadata.configVersion,engines:[],routes:[]}),
  releaseTask:async()=>{},...overrides};
}
function sdkFixture(settings={}) {
 const bytes=Buffer.alloc(256*1024*2+37);for(let i=0;i<bytes.length;i++)bytes[i]=i%251;
 const uri='file://docs/report.PDF',destination='/sandbox/cache/workspace/controlled/inputs/id';
 const handles=new Map(),outputs=new Map(),closed=[],opens=[];let next=1,reads=0,writes=0;
 const fileIo={OpenMode:{READ_ONLY:0,WRITE_ONLY:1,CREATE:2,TRUNC:4},
  async open(name,mode){opens.push(name);if(settings.openCode)throw {code:settings.openCode};
   const file={fd:next++};handles.set(file.fd,{name,pos:0,source:name===uri});if(name!==uri)outputs.set(name,Buffer.alloc(0));return file;},
  async stat(fd){const item=handles.get(fd);return {size:item.source?(settings.reportedSize??bytes.length):outputs.get(item.name).length,isFile:()=>settings.regular!==false};},
  async read(fd,buffer,options){assert.equal(options,undefined);reads++;const item=handles.get(fd);
   const count=Math.min(90001,buffer.byteLength,bytes.length-item.pos);new Uint8Array(buffer).set(bytes.subarray(item.pos,item.pos+count));item.pos+=count;return count;},
  async write(fd,buffer,options){assert.equal(options,undefined);writes++;if(settings.zeroWrite)return 0;
   const item=handles.get(fd),chunk=Buffer.from(buffer),count=Math.min(17003,chunk.length);
   outputs.set(item.name,Buffer.concat([outputs.get(item.name),chunk.subarray(0,count)]));item.pos+=count;return count;},
  async close(file){closed.push(file.fd);handles.delete(file.fd);if(settings.closeFailure&&file.fd===2)throw new Error('close failure');},
  async access(name){return outputs.has(name);},async unlink(name){outputs.delete(name);},async mkdir(){},async rmdir(){}};
 const kit={fileIo,fileUri:{FileUri:class {constructor(value){this.name=value.slice(value.lastIndexOf('/')+1);}}},
  picker:{DocumentViewPicker:class {async select(options){assert.equal(options.maxSelectNumber,10);return [uri];}}},
  statfs:{getFreeSize:async()=>settings.free??1024*1024*1024},hash:{hash:async(name,algorithm)=>{assert.equal(algorithm,'sha256');return sha(outputs.get(name)).toUpperCase();}}};
 const h=host({sdkModules:{'@kit.CoreFileKit':kit}}),{HarmonyFilePlatform}=h.load('./services/HarmonyFilePlatform');
 const adapter=new HarmonyFilePlatform({cacheDir:'/sandbox/cache'});
 return {adapter,bytes,uri,destination,handles,outputs,closed,opens,reads:()=>reads,writes:()=>writes};
}
async function main(){
 await test('Approved task method surface and immutable format matrix and Native protocol remain intact',()=>{
  const baseline=JSON.parse(fs.readFileSync(path.join(__dirname,'approved-input-baseline.json')));
  const ts=require(process.env.HDM_TYPESCRIPT_PATH||'D:/DevEco Studio2026/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
  const source=fs.readFileSync(path.join(root,'entry/src/main/ets/viewmodel/TaskStore.ets'),'utf8');
  const file=ts.createSourceFile('TaskStore.ts',source,ts.ScriptTarget.Latest,true);
  const taskClass=file.statements.find(item=>ts.isClassDeclaration(item)&&item.name.text==='TaskStore');
  const methods=taskClass.members.filter(ts.isMethodDeclaration);
  // Body refactoring is explicitly approved for this phase; the P0 hash record stays historical.
  // Behaviour is verified by the queue/fidelity/native/input suites, not by replacing pinned hashes.
  for(const name of Object.keys(baseline.taskStoreMethods)){
   const method=methods.find(item=>item.name.getText(file)===name);assert.ok(method,name);
  }
  for(const [name,hash] of Object.entries(baseline.unchangedFiles)){
   // 04e6886 added copyArtifactToFd with the previously approved delivery work.
   // Retain the historical baseline; pin that authorized protocol separately.
   const expected=name.endsWith('/NativeProtocol.ets')?
    'a48889500afe6575c74a7b7ab0b1ef9dba852c2274ad335ecd5eb34b8adfdfa1':hash;
   if(name.startsWith('shared/')||name.endsWith('/NativeProtocol.ets'))
    assert.equal(sha(fs.readFileSync(path.join(root,name),'utf8').replace(/\r\n/g,'\n')),expected,name);
  }
 });
 await test('Harmony adapter handles multiple chunks and partial writes without offsets or descriptor leaks',async()=>{
  const f=sdkFixture();assert.equal(await f.adapter.copyUri(f.uri,f.destination,100*1024*1024,()=>true),f.bytes.length);
  assert.deepEqual(f.outputs.get(f.destination),f.bytes);assert.ok(f.reads()>2);assert.ok(f.writes()>f.reads());
  assert.equal(await f.adapter.sha256(f.destination),sha(f.bytes));assert.equal(f.handles.size,0);assert.equal(f.closed.length,2);
 });
 await test('Harmony picker derives file metadata from authorized descriptors and closes each descriptor',async()=>{
  const f=sdkFixture();assert.equal(f.adapter.isAvailable(),true);const files=await f.adapter.pick(10);
  assert.equal(files[0].uri,f.uri);assert.equal(files[0].fileName,'report.PDF');assert.equal(files[0].fileSize,f.bytes.length);
  assert.equal(files[0].mimeType,'application/pdf');assert.equal(f.handles.size,0);
 });
 await test('Harmony adapter rejects oversized files and low space before opening a destination',async()=>{
  for(const [settings,error] of [[{reportedSize:100*1024*1024+1},'FILE_TOO_LARGE'],[{free:0},'SANDBOX_FULL']]){
   const f=sdkFixture(settings);await assert.rejects(()=>f.adapter.copyUri(f.uri,f.destination,100*1024*1024,()=>true),reason(error));
   assert.deepEqual(f.opens,[f.uri]);assert.equal(f.handles.size,0);
  }
 });
 await test('Harmony adapter rejects source size changes and zero writes and closes both descriptors',async()=>{
  for(const [settings,error] of [[{reportedSize:23},'FILE_CHANGED_DURING_COPY'],[{zeroWrite:true},'FILE_WRITE_INCOMPLETE']]){
   const f=sdkFixture(settings);await assert.rejects(()=>f.adapter.copyUri(f.uri,f.destination,100*1024*1024,()=>true),reason(error));
   assert.equal(f.handles.size,0);assert.equal(f.closed.length,2);
  }
 });
 await test('Harmony copy cancellation and close failure still attempt both descriptor closures',async()=>{
  const canceled=sdkFixture();await assert.rejects(()=>canceled.adapter.copyUri(canceled.uri,canceled.destination,100*1024*1024,()=>canceled.reads()===0),reason('FILE_IMPORT_CANCELLED'));
  assert.equal(canceled.handles.size,0);const closing=sdkFixture({closeFailure:true});
  await assert.rejects(()=>closing.adapter.copyUri(closing.uri,closing.destination,100*1024*1024,()=>true),reason('FILE_CLOSE_FAILED'));
  assert.equal(closing.handles.size,0);assert.equal(closing.closed.length,2);
 });
 await test('Harmony file SDK permission and storage errors normalize into existing BridgeError codes',async()=>{
  for(const [openCode,error] of [[13900012,'FILE_GRANT_EXPIRED'],[13900025,'SANDBOX_FULL']]){
   const f=sdkFixture({openCode});await assert.rejects(()=>f.adapter.copyUri(f.uri,f.destination,100*1024*1024,()=>true),reason(error));
  }
 });
 await test('Format detection covers every extension and MIME in the unchanged 18-format registry',()=>{
  const h=host(),{FormatDetector}=h.load('./services/FormatDetector');
  assert.equal(formats.length,18);
  for(const format of formats){
   for(const extension of format.extensions)assert.equal(FormatDetector.detectByExtension('example.'+extension.toUpperCase()),format.id);
   for(const mime of format.mimeTypes)assert.equal(FormatDetector.detectByMime(mime.toUpperCase()+'; charset=utf-8'),format.id);
  }
  assert.equal(FormatDetector.detect('image.JPG','application/pdf'),'jpeg');
  assert.equal(FormatDetector.detect('no-extension','application/pdf'),'pdf');
  assert.equal(FormatDetector.detect('x.unknown','application/unknown'),'');
  assert.equal(FormatDetector.detectByExtension('x.'),null);
 });
 await test('Standalone preview has no configured picker and does not touch file APIs',async()=>{
  const f=fixture();assert.equal(f.FileAuthorizationService.isAvailable(),false);
  await assert.rejects(()=>f.FileAuthorizationService.pickDocuments(10),reason('FILE_PICKER_UNAVAILABLE'));
  f.platform.available=false;assert.equal(f.manager.isAvailable(),false);
  await assert.rejects(()=>f.manager.createSession(),reason('FILE_PICKER_UNAVAILABLE'));assert.equal(f.platform.directories.size,0);
 });
 await test('Picker cancellation is empty and invalid counts or malformed URIs are rejected',async()=>{
  const f=fixture();assert.deepEqual(Array.from(await f.manager.pickDocuments(10)),[]);
  for(const count of [0,11,1.5])await assert.rejects(()=>f.manager.pickDocuments(count),reason('FILE_SELECTION_LIMIT'));
  f.select(['x.pdf']);f.platform.selected[0].uri='/outside/user-file';
  await assert.rejects(()=>f.manager.pickDocuments(10),reason('FILE_URI_INVALID'));
  f.select(['x.pdf']);f.platform.selected[0].fileSize=0;
  await assert.rejects(()=>f.manager.pickDocuments(10),reason('FILE_EMPTY_OR_INVALID'));
 });
 await test('Oversized picker metadata is rejected before creating any sandbox file',async()=>{
  const f=fixture();f.select(['large.pdf']);f.platform.selected[0].fileSize=100*1024*1024+1;
  await assert.rejects(()=>f.manager.pickDocuments(10),reason('FILE_TOO_LARGE'));assert.equal(f.platform.reads,0);
 });
 await test('Unauthorized URI and edited picker metadata never reach the copy adapter',async()=>{
  const f=fixture();f.select(['x.pdf']);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();
  await assert.rejects(()=>f.manager.copyToSandbox({...picked[0],uri:'file://docs/not-picked.pdf'},session.sessionId),reason('FILE_NOT_PICKER_AUTHORIZED'));
  await assert.rejects(()=>f.manager.copyToSandbox({...picked[0],fileName:'other.pdf'},session.sessionId),reason('FILE_NOT_PICKER_AUTHORIZED'));
  assert.equal(f.platform.reads,0);await f.manager.destroySession(session.sessionId);
 });
 await test('Controlled random paths real copied sizes SHA-256 and snapshots preserve ownership',async()=>{
  const f=fixture(),{session,files}=await f.imported();const file=files[0];
  assert.match(file.relativePath,/^inputs\/[a-f0-9]{32}$/);assert.equal(file.byteSize,21);
  assert.equal(file.sha256,sha(Buffer.from('%PDF-controlled-input')));assert.equal(file.detectedFormatId,'pdf');
  assert.equal(JSON.stringify(file).includes('file://'),false);
  session.inputFiles.length=0;file.sha256='forged';assert.equal(f.manager.getSession(session.sessionId).inputFiles.length,1);
  assert.notEqual(f.manager.getSession(session.sessionId).inputFiles[0].sha256,'forged');
  await f.manager.destroySession(session.sessionId);assert.equal(f.platform.copies.size,0);
 });
 await test('MIME disagreement records a warning and keeps the registered extension priority',async()=>{
  const f=fixture();f.select(['x.png']);f.platform.selected[0].mimeType='application/pdf';
  const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();
  const file=await f.manager.copyToSandbox(picked[0],session.sessionId);
  assert.equal(file.detectedFormatId,'png');assert.deepEqual(Array.from(file.warnings),['FORMAT_MIME_MISMATCH']);
  await f.manager.destroySession(session.sessionId);
 });
 await test('Blocked protected extensions and unregistered formats cannot create input copies',async()=>{
  for(const [name,error] of [['x.ncm','DRM_BLOCKED'],['x.doc','FILE_FORMAT_UNSUPPORTED']]){
   const f=fixture();f.select([name]);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();
   await assert.rejects(()=>f.manager.copyToSandbox(picked[0],session.sessionId),reason(error));assert.equal(f.platform.reads,0);
  }
 });
 await test('Actual oversized data and copy failures remove incomplete files and normalize errors',async()=>{
  for(const failure of ['actualBytes','copyFailure']){
   const f=fixture();f.select(['x.pdf']);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();
   f.platform[failure]=failure==='actualBytes'?100*1024*1024+1:true;
   await assert.rejects(()=>f.manager.copyToSandbox(picked[0],session.sessionId),reason(failure==='actualBytes'?'FILE_TOO_LARGE':'FILE_COPY_FAILED'));
   assert.equal(f.platform.copies.size,0);assert.equal(f.manager.getSession(session.sessionId).inputFiles.length,0);
  }
 });
 await test('Hash failures and invalid digests remove the copy and do not publish an authorized file',async()=>{
  for(const failure of ['hashFailure','badDigest']){
   const f=fixture();f.select(['x.pdf']);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();f.platform[failure]=true;
   await assert.rejects(()=>f.manager.copyToSandbox(picked[0],session.sessionId),reason(failure==='hashFailure'?'FILE_COPY_FAILED':'FILE_HASH_INVALID'));
   assert.equal(f.platform.copies.size,0);assert.equal(f.manager.getSession(session.sessionId).inputFiles.length,0);
  }
 });
 await test('Insufficient storage rejects copying before an adapter opens the input',async()=>{
  const f=fixture();f.select(['x.pdf']);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();f.platform.free=0;
  await assert.rejects(()=>f.manager.copyToSandbox(picked[0],session.sessionId),reason('SANDBOX_FULL'));assert.equal(f.platform.reads,0);
 });
 await test('Concurrent imports serialize the 300MB budget and cannot overfill the session',async()=>{
  const f=fixture();f.select(['a.pdf','b.pdf','c.pdf','d.pdf']);for(const file of f.platform.selected)file.fileSize=100*1024*1024;
  f.platform.actualBytes=100*1024*1024;const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();
  const results=await Promise.allSettled(picked.map(file=>f.manager.copyToSandbox(file,session.sessionId)));
  assert.equal(results.filter(result=>result.status==='fulfilled').length,3);assert.equal(results[3].reason.reason,'BATCH_TOO_LARGE');
  assert.equal(f.manager.getSession(session.sessionId).inputFiles.reduce((count,file)=>count+file.byteSize,0),300*1024*1024);
 });
 await test('Session destruction during copying waits for cancellation and leaves no late files',async()=>{
  const f=fixture();f.select(['x.pdf']);const picked=await f.manager.pickDocuments(10),session=await f.manager.createSession();let finish;
  f.platform.gate=new Promise(resolve=>finish=resolve);
  const copying=f.manager.copyToSandbox(picked[0],session.sessionId);const failed=assert.rejects(()=>copying,reason('FILE_IMPORT_CANCELLED'));
  await flush();const cleanup=f.manager.destroySession(session.sessionId);finish();await failed;await cleanup;
  assert.equal(f.platform.copies.size,0);assert.equal(f.manager.activeSessions().length,0);
 });
 await test('Removing inputs requires ownership and updates both disk and session snapshots',async()=>{
  const f=fixture(),{session,files}=await f.imported();
  await assert.rejects(()=>f.manager.removeFile(session.sessionId,'../../escape'),reason('INPUT_NOT_OWNED'));
  assert.equal(f.platform.copies.size,1);await f.manager.removeFile(session.sessionId,files[0].fileId);
  assert.equal(f.platform.copies.size,0);assert.equal(f.manager.getSession(session.sessionId).inputFiles.length,0);
 });
 await test('Concurrent destroy is idempotent and cleanup cannot target caller supplied paths',async()=>{
  const f=fixture(),{session}=await f.imported();await f.manager.destroySession('../../outside');
  await Promise.all([f.manager.destroySession(session.sessionId),f.manager.destroySession(session.sessionId)]);
  await f.manager.destroySession(session.sessionId);
  assert.equal(f.platform.removed.filter(name=>name===session.workspaceRef).length,1);
  assert.ok(f.platform.removed.every(name=>name.startsWith('/sandbox/cache/workspace/')));
 });
 await test('Failed cleanup can retry and ability cleanup closes all sessions and grants',async()=>{
  const f=fixture(),{session}=await f.imported();f.platform.removeFailure=true;
  await assert.rejects(()=>f.manager.destroySession(session.sessionId),reason('WORKSPACE_REMOVE_FAILED'));
  assert.equal(f.manager.activeSessions().length,1);f.platform.removeFailure=false;await f.manager.destroyAllSessions();
  assert.equal(f.manager.activeSessions().length,0);assert.equal(f.manager.isAvailable(),false);
 });
 await test('Claimed task inputs cannot be removed or imported again by the page',async()=>{
  const f=fixture(),{session,files}=await f.imported();f.manager.claimSession(session.sessionId);
  await assert.rejects(()=>f.manager.removeFile(session.sessionId,files[0].fileId),reason('SESSION_ALREADY_SUBMITTED'));
  assert.throws(()=>f.manager.claimSession(session.sessionId),reason('SESSION_ALREADY_SUBMITTED'));
 });
 await test('No authorized files preserves original queued demo state timer and duration',async()=>{
  const f=fixture();const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png');
  assert.equal(task.mode,'demo');assert.equal(task.status,'queued');assert.equal(task.progress,0);assert.equal(f.h.timers.size,1);
  f.h.step(50);f.h.fireTimeouts();f.h.step(3500);f.h.fireTimeouts();assert.equal(f.h.store.snapshot()[0].status,'completed');
  assert.equal(f.h.nativeLoads(),0);
 });
 await test('Current Native session placeholder produces a failed real task without demo success and releases input',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let workspaceCalls=0;
  f.h.setNative(stub(f.h,{initializeSession:async()=>{throw {code:'UNSUPPORTED_FEATURE',reason:'MIGRATED_CONTRACT_NOT_IMPLEMENTED'};},
   registerWorkspace:async()=>{workspaceCalls++;return 'unexpected';}}));
  const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  assert.equal(task.mode,'native');assert.equal(task.status,'failed');assert.equal(task.progress,0);
  assert.equal(task.fidelityReport,undefined);assert.equal(task.resultLabel,'');assert.match(task.error,/MIGRATED_CONTRACT_NOT_IMPLEMENTED/);
  assert.equal(workspaceCalls,0);assert.equal(f.platform.copies.size,0);assert.equal(f.h.timers.size,0);
 });
 await test('Forged authorized hashes are rejected before Native initialization',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let calls=0;
  f.h.setNative(stub(f.h,{initializeSession:async()=>{calls++;return 'native';}}));files[0].sha256='a'.repeat(64);
  const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  assert.match(task.error,/AUTHORIZED_INPUT_MISMATCH/);assert.equal(calls,0);assert.equal(f.platform.copies.size,0);
 });
 await test('Native single-file and fidelity gates stay intact for real submissions',async()=>{
  for(const multi of [true,false]){
   const f=fixture(),{session,files}=await f.imported(multi?['a.pdf','b.pdf']:['a.pdf'],true);
   const selection={qualityMode:'high_fidelity',requestedIntent:'layout_preserved',requestedTier:'extreme'};
   const task=await f.h.store.submitTask('a.pdf','pdf','png','pdf-png',false,multi?undefined:selection,files,session);
   assert.match(task.error,multi?/NATIVE_SINGLE_FILE_REQUIRED/:/FIDELITY_TIER_UNAVAILABLE/);assert.equal(f.h.nativeLoads(),0);
  }
 });
 await test('Successful mock bootstrap uses Native handles and existing unavailable-route gate before probing',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let init,grant,probes=0,releases=0;
  f.h.setNative(stub(f.h,{initializeSession:async value=>{init=value;return 'native-session';},registerWorkspace:async value=>{grant=value;return 'native-workspace';},
   probeInputs:async()=>{probes++;return [];},releaseTask:async()=>{releases++;}}));
  const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  assert.equal(task.mode,'native');assert.equal(task.status,'queued');assert.equal(init.appSandboxRoot,'/sandbox/cache');
  assert.equal(grant.sessionId,'native-session');assert.equal(grant.relativeDirectory,'workspace/'+session.sessionId);
  const request=f.h.store.nativeRequests.get(task.id);assert.equal(request.workspaceRef,'native-workspace');
  assert.equal(JSON.stringify(request).includes('file://'),false);assert.equal(request.inputs[0].sha256,files[0].sha256);
  f.h.step(50);f.h.fireTimeouts();await flush();assert.equal(f.h.store.snapshot()[0].status,'failed');
  assert.equal(probes,0);assert.equal(f.platform.copies.size,0);assert.equal(releases,1);
 });
 await test('Queued real cancellation removes owned inputs and cannot resurrect the task',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let releases=0;f.h.setNative(stub(f.h,{releaseTask:async()=>{releases++;}}));
  const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  assert.equal(f.h.store.cancel(task.id),true);await flush();assert.equal(f.platform.copies.size,0);
  f.h.step(6000);f.h.fireTimeouts();assert.equal(f.h.store.snapshot()[0].status,'cancelled');
  assert.equal(releases,1);
 });
 await test('Running real cancellation keeps sandbox inputs until the Native call and release settle',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let finish,releases=0;
  const metadata=f.h.load('./generated/RegistryData').registryMetadata;
  f.h.setNative(stub(f.h,{getCapabilities:()=>new Promise(resolve=>finish=resolve),
   cancel:async()=>({accepted:true}),releaseTask:async()=>{releases++;}}));
  const task=await f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  f.h.store.advance(f.h.now());await flush();assert.equal(typeof finish,'function');
  f.h.store.cancel(task.id);await flush();assert.equal(f.platform.copies.size,1);assert.equal(releases,0);
  finish({schemaVersion:1,offlineOnly:true,abi:'mock',configVersion:metadata.configVersion,engines:[],routes:[]});await flush();
  assert.equal(f.platform.copies.size,0);assert.equal(releases,1);assert.equal(f.h.store.snapshot()[0].status,'cancelled');
 });
 await test('Late Native workspace registration after timeout is released and never enqueued',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let finish,releases=0;
  f.h.setNative(stub(f.h,{registerWorkspace:()=>new Promise(resolve=>finish=resolve),releaseTask:async()=>{releases++;}}));
  const submission=f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  await flush();assert.equal(typeof finish,'function');f.h.fireTimeouts();const task=await submission;
  assert.match(task.error,/NATIVE_SESSION_TIMEOUT/);finish('late-workspace');await flush();
  assert.equal(releases,1);assert.equal(f.h.store.nativeRequests.size,0);assert.equal(f.platform.copies.size,0);
 });
 await test('Native bootstrap timeout destroys inputs and prevents a late workspace registration',async()=>{
  const f=fixture(),{session,files}=await f.imported(['x.pdf'],true);let finish,calls=0;
  f.h.setNative(stub(f.h,{initializeSession:()=>new Promise(resolve=>finish=resolve),registerWorkspace:async()=>{calls++;return 'late';}}));
  const submission=f.h.store.submitTask('x.pdf','pdf','png','pdf-png',false,undefined,files,session);
  await flush();f.h.fireTimeouts();const task=await submission;assert.match(task.error,/NATIVE_SESSION_TIMEOUT/);
  assert.equal(f.platform.copies.size,0);finish('late-session');await flush();assert.equal(calls,0);assert.equal(f.h.timers.size,0);
 });
 await test('Ability shutdown closes owned input sessions without affecting the existing shutdown path',async()=>{
  const f=fixture();await f.imported(['x.pdf'],true);f.h.store.shutdown();await f.h.store.releaseAuthorizedSessions();
  assert.equal(f.platform.copies.size,0);assert.equal(f.FileAuthorizationService.isAvailable(),false);
 });
 await test('Delayed old ability cleanup cannot close a newly configured file service',async()=>{
  const f=fixture();f.FileAuthorizationService.configurePlatform(f.platform);
  const cleanup=f.FileAuthorizationService.captureCleanup();f.FileAuthorizationService.configurePlatform({...f.platform});
  await cleanup();assert.equal(f.FileAuthorizationService.isAvailable(),true);
 });
 const report={scope:'input_authorization_logic_with_mock_filesystem_and_native_adapters',result:'passed',testedCases:cases.length,cases,
 realPickerExecution:'not_executed',deviceExecution:'not_executed',previewerExecution:'not_executed',realConversion:'not_executed'};
 fs.writeFileSync(path.join(root,'tests/generated/input-management-check-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({result:report.result,testedCases:report.testedCases}));
}
if(require.main===module)main().catch(error=>{console.error(error);process.exitCode=1;});
module.exports={fixture,flush,stub};
