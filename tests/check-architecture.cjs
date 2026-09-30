'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {host}=require('./check-interactions.cjs');
const {fixture}=require('./check-input-management.cjs');
const root=path.resolve(__dirname,'..'),cases=[];
async function test(name,body){await body();cases.push({name,result:'passed'});}
async function flush(){for(let i=0;i<80;i++)await Promise.resolve();}
async function main(){
 await test('BridgeError UUIDs uniquely identify errors created within the same clock millisecond',()=>{
  const h=host(),{BridgeError}=h.load('./common/BridgeError');
  const ids=new Set(Array.from({length:1000},()=>new BridgeError('INVALID_REQUEST','TEST').traceId));
  assert.equal(ids.size,1000);assert.ok([...ids].every(id=>/^[a-f0-9-]{32,36}$/i.test(id)));
 });
 await test('Unavailable UUID support has a monotonic preview fallback and cannot break error construction',()=>{
  const h=host({sdkModules:{'@kit.ArkTS':{util:{generateRandomUUID(){throw new Error('unsupported');}}}}});
  const {BridgeError}=h.load('./common/BridgeError');
  assert.notEqual(new BridgeError('IO_ERROR','TEST').traceId,new BridgeError('IO_ERROR','TEST').traceId);
 });
 await test('ErrorHandler retains typed errors and reports sanitized fallbacks without raw SDK messages',()=>{
  const h=host(),{BridgeError}=h.load('./common/BridgeError'),{ErrorHandler,isBridgeError}=h.load('./common/ErrorHandler');
  const reports=[];ErrorHandler.setReporter({report:(error,context)=>reports.push({error,context})});
  const original=new BridgeError('IO_ERROR','FILE_COPY_FAILED');assert.equal(isBridgeError(original),true);
  assert.equal(ErrorHandler.catchBridge(original,'Test'),original);
  const raw=new Error('file://private/sensitive.pdf');const normalized=ErrorHandler.catchBridge(raw,'Test');
  assert.equal(normalized.reason,'UNEXPECTED_FAILURE');assert.equal(isBridgeError(raw),false);
  assert.equal(reports.length,2);assert.equal(JSON.stringify(reports).includes('file://'),false);
  ErrorHandler.setReporter(null);
 });
 await test('Every FidelityPolicy enum switch rejects invalid boundary values while preserving valid durations',()=>{
  const {FidelityPolicy}=host().load('./viewmodel/FidelityPolicy');
  for(const method of ['tierRank','tierLabel','intentLabel','qualityLabel','durationMs'])
   assert.throws(()=>FidelityPolicy[method]('invalid'),error=>error.code==='INVALID_REQUEST');
  assert.deepEqual(['fast','balanced','high_fidelity'].map(mode=>FidelityPolicy.durationMs(mode)),[2000,3500,6000]);
 });
 await test('FormatRegistry instances own readiness and verification independently',async()=>{
  const h=host({registryReady:false}),{FormatRegistryService}=h.load('./services/FormatRegistry');
  const first=new FormatRegistryService(),second=new FormatRegistryService();
  await first.initialize(h.resources);assert.equal(first.isInitialized(),true);assert.equal(second.isInitialized(),false);
  const formats=first.listFormats();formats[0].extensions.length=0;assert.ok(second.listFormats()[0].extensions.length>0);
  assert.equal(second.listFormats().length,18);assert.equal(second.listPlannedRoutes().length,43);
 });
 await test('Extension and MIME indexes build once per catalogue revision and rebuild only after a change',()=>{
  const h=host(),{FormatDetectorIndex}=h.load('./services/FormatDetector');let reads=0,version=0;
  const registry={catalogueVersion:()=>version,listFormats:()=>{reads++;return [{id:'pdf',extensions:['pdf'],mimeTypes:['application/pdf']}];}};
  const index=new FormatDetectorIndex(registry);
  for(let i=0;i<1000;i++){assert.equal(index.detect('x.PDF','image/png'),'pdf');assert.equal(index.detectByMime('APPLICATION/PDF; x=1'),'pdf');}
  assert.equal(reads,1);version++;assert.equal(index.detectByExtension('x.pdf'),'pdf');assert.equal(reads,2);
 });
 await test('Injected Native loaders do not share module state and failed loads remain retryable',async()=>{
  const h=host(),{NativeBridgeService}=h.load('./services/NativeBridge');let calls=0;
  const metadata=h.load('./generated/RegistryData').registryMetadata;
  const request={schemaVersion:1,sessionId:'inspection',configVersion:metadata.configVersion};
  const module={getCapabilities:async()=>({schemaVersion:1,offlineOnly:true,abi:'mock',configVersion:metadata.configVersion,engines:[],routes:[]})};
  const first=new NativeBridgeService({load:async()=>{calls++;if(calls===1)throw new Error('load failed');return module;}});
  const second=new NativeBridgeService({load:async()=>module});
  await assert.rejects(()=>first.getCapabilities(request));assert.equal(first.isNativeAvailable(),false);
  await first.getCapabilities(request);assert.equal(first.isNativeAvailable(),true);assert.equal(second.isNativeAvailable(),false);
  assert.equal(calls,2);assert.equal(h.nativeLoads(),0);
 });
 await test('Promise race deadlines clear their timers and discard late caller results',async()=>{
  const h=host(),{withDeadline}=h.load('./common/Deadline'),{BridgeError}=h.load('./common/BridgeError');
  let finish;const pending=withDeadline(new Promise(resolve=>finish=resolve),5000,()=>new BridgeError('CONVERSION_TIMEOUT','TEST'));
  const rejected=assert.rejects(()=>pending,error=>error.reason==='TEST');h.fireTimeouts();await rejected;
  finish('late');await flush();assert.equal(h.timers.size,0);
  assert.equal(await withDeadline(Promise.resolve('ready'),5000,()=>new BridgeError('CONVERSION_TIMEOUT','TEST')),'ready');
  assert.equal(h.timers.size,0);
 });
 await test('Category factories instantiate only requested records and still expose the entire offline catalogue',()=>{
  const h=host({registryReady:false}),{FormatRegistryService}=h.load('./services/FormatRegistry');
  const registry=new FormatRegistryService();assert.equal(registry.formatCategories.size,0);
  assert.equal(registry.listFormats('office').length,3);assert.deepEqual([...registry.formatCategories.keys()],['office']);
  assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
 });
 await test('Idle draft session TTL removes owned copies but claimed task inputs never expire',async()=>{
  for(const claimed of [false,true]){
   const f=fixture();f.platform.now=()=>f.h.now();const {session}=await f.imported();
   if(claimed)f.manager.claimSession(session.sessionId);f.h.step(30*60*1000+1);await f.manager.expireIdleSessions();
   assert.equal(f.platform.copies.size,claimed?1:0);assert.equal(f.manager.activeSessions().length,claimed?1:0);
   await f.manager.destroyAllSessions();assert.equal(f.h.timers.size,0);
  }
 });
 await test('Copying draft sessions survive TTL and successful activity refreshes their idle deadline',async()=>{
  const f=fixture();f.platform.now=()=>f.h.now();const {session}=await f.imported();f.select(['second.pdf']);
  const picked=await f.manager.pickDocuments(10);let finish;f.platform.gate=new Promise(resolve=>finish=resolve);
  const copy=f.manager.copyToSandbox(picked[0],session.sessionId);await flush();
  f.h.step(30*60*1000+1);await f.manager.expireIdleSessions();assert.equal(f.manager.activeSessions().length,1);
  finish();await copy;await f.manager.expireIdleSessions();assert.equal(f.manager.getSession(session.sessionId).inputFiles.length,2);
  await f.manager.destroyAllSessions();
 });
 await test('Cleanup deadlines report pending ownership without deleting live or uncompleted resources',async()=>{
  const f=fixture();await f.imported();let finish;const original=f.platform.removeDirectory.bind(f.platform);
  f.platform.removeDirectory=async name=>{await new Promise(resolve=>finish=resolve);await original(name);};
  const pending=f.manager.destroyAllSessions(),rejected=assert.rejects(()=>pending,error=>error.reason==='WORKSPACE_CLEANUP_TIMEOUT');
  await flush();f.h.fireTimeouts();await rejected;assert.equal(f.manager.activeSessions().length,1);assert.equal(f.platform.copies.size,1);
  finish();await flush();assert.equal(f.manager.activeSessions().length,0);assert.equal(f.platform.copies.size,0);
 });
 await test('ServiceContainer preview construction calls no Native loader and owned scope shutdown leaves other scopes available',async()=>{
  const f=fixture(),{ServiceContainer}=f.h.load('./services/ServiceContainer');
  const preview=new ServiceContainer();assert.equal(preview.files.isAvailable(),false);assert.equal(f.h.nativeLoads(),0);
  const native={shutdown:async()=>{}};
  const first=new ServiceContainer(f.h.load('./services/FormatRegistry').FormatRegistry.shared(),native,f.platform);
  const second=new ServiceContainer(f.h.load('./services/FormatRegistry').FormatRegistry.shared(),native,{...f.platform});
  await first.shutdown();assert.equal(first.files.isAvailable(),false);assert.equal(second.files.isAvailable(),true);
 });

 function converter(f,store=f.h.store){
  const h=f.h,ui={read:key=>String(key.id),tier:t=>t,intent:i=>i,quality:q=>q,toast:()=>{},
    showAlertDialog(){throw new Error('preview');},navigationParams:()=>({}),ensureRegistry:async()=>{}};
  const status=new (h.load('./viewmodel/ConversionStatusVM').ConversionStatusVM)(store,ui);
  const fidelity=new (h.load('./viewmodel/FidelityConfigVM').FidelityConfigVM)();
  const planner=new (h.load('./viewmodel/ConversionPlanner').ConversionPlannerService)(h.load('./services/FormatRegistry').FormatRegistry.shared());
  const formats=new (h.load('./viewmodel/FormatSelectionVM').FormatSelectionVM)(h.load('./services/FormatRegistry').FormatRegistry.shared(),planner,fidelity,status,ui);
  const files=new (h.load('./viewmodel/FileAuthorizationVM').FileAuthorizationVM)(f.manager,status,formats,ui);
  const coordinator=new (h.load('./viewmodel/ConverterCoordinator').ConverterCoordinator)(formats,files,status,store,planner,ui);
  coordinator.appear();return {status,fidelity,formats,files,coordinator};
 }
 await test('Independent converter VMs retain all formats, original route filters and quality ordering without cloning',async()=>{
  const f=fixture(),c=converter(f);await flush();assert.equal(c.formats.sourceChoices.length,18);
  c.formats.selectFormat('pdf');c.formats.selectTarget(c.formats.targetFormats.findIndex(t=>t.id==='png'));
  const identity=c.fidelity;c.formats.selectQuality('high_fidelity');assert.equal(c.fidelity,identity);
  assert.deepEqual(c.formats.activeRoutes.map(r=>r.id),f.h.planner.routes('pdf','png','high_fidelity',c.fidelity.requestedIntent,c.fidelity.requestedTier).map(r=>r.id));
  c.coordinator.hide(true);assert.equal(f.h.store.listeners.length,0);
 });
 await test('Inline confirmation never starts automatically and uses the frozen approved submission',async()=>{
  const f=fixture(),c=converter(f);await flush();c.formats.selectFormat('pdf');
  c.formats.selectTarget(c.formats.targetFormats.findIndex(t=>t.id==='png'));c.formats.fileName='confirmation.pdf';
  c.coordinator.start();assert.equal(f.h.store.snapshot().length,0);assert.equal(c.status.confirming,true);assert.equal(c.formats.interactive,false);
  assert.ok(c.status.inlineConfirmationText.includes('confirmation.pdf'));
  c.formats.fileName='mutated.pdf';c.coordinator.beginConfirmed();
  assert.equal(f.h.store.snapshot()[0].fileName,'confirmation.pdf');assert.equal(c.status.confirming,false);
  c.coordinator.hide(true);f.h.store.shutdown();
 });
 await test('Submission throws clear UI authorization in finally and release the owned draft for retry',async()=>{
  const f=fixture(),store={...f.h.store, snapshot:()=>[],subscribe:()=>1,unsubscribe:()=>{},submitTask:async()=>{throw new Error('failure');}};
  const c=converter(f,store);await flush();f.select(['report.pdf']);await c.files.pickSourceFiles();
  c.formats.selectTarget(c.formats.targetFormats.findIndex(t=>t.id==='png'));c.coordinator.start();
  assert.ok(c.status.realConfirmationText);await c.coordinator.beginAuthorized();
  assert.equal(c.files.authorizedFiles.length,0);assert.equal(c.files.sessionContext,null);assert.equal(c.files.fileSubmitting,false);
  assert.equal(f.manager.activeSessions().length,0);assert.ok(c.status.errorText);c.coordinator.hide(true);
 });
 await test('Temporary system Picker hide preserves its result while copy-time hide discards late data',async()=>{
  for(const stage of ['picker','copy']){
   const f=fixture(),c=converter(f);await flush();f.select(['report.pdf']);let finish;
   if(stage==='picker'){const original=f.platform.pick.bind(f.platform);f.platform.pick=async()=>{await new Promise(resolve=>finish=resolve);return original();};}
   else f.platform.gate=new Promise(resolve=>finish=resolve);
   const importing=c.files.pickSourceFiles();await flush();c.coordinator.hide();finish();await importing;await flush();
   assert.equal(c.files.authorizedFiles.length,stage==='picker'?1:0);
   c.coordinator.hide(true);await flush();assert.equal(f.manager.activeSessions().length,0);
  }
 });
 await test('TTL invalidates visible unsubmitted inputs and unsubscribes the page observer on hide',async()=>{
  const f=fixture();f.platform.now=()=>f.h.now();const c=converter(f);await flush();f.select(['report.pdf']);await c.files.pickSourceFiles();
  f.h.step(30*60*1000+1);await f.manager.expireIdleSessions();assert.equal(c.files.authorizedFiles.length,0);assert.equal(c.files.sessionContext,null);
  assert.ok(c.status.errorText.includes('input_grant_expired'));c.coordinator.hide(true);assert.equal(f.manager.expiryListeners.size,0);
 });
 await test('Task history stays at 100, protects active work, reuses original ordering and bounds timing caches',()=>{
  const h=host();for(let i=0;i<100;i++)h.store.enqueue('job'+i+'.pdf','pdf','png','pdf-png');
  assert.throws(()=>h.store.enqueue('overflow.pdf','pdf','png','pdf-png'),e=>e.reason==='DEMO_HISTORY_LIMIT');
  h.store.advance(h.now());const first=h.store.snapshot().at(-1);assert.equal(h.store.pause(first.id),true);assert.equal(h.store.resume(first.id),true);
  h.step(3500);h.store.advance(h.now());assert.equal(h.store.runningTask.id,first.id);
  for(let i=0;i<100;i++){h.step(3500);h.store.advance(h.now());}
  assert.equal(h.store.timings.size,0);assert.equal(h.timers.size,0);
  h.store.enqueue('new.pdf','pdf','png','pdf-png');assert.equal(h.store.snapshot().length,100);assert.ok(h.store.timings.size<=100);h.store.shutdown();
 });
 await test('Native result cache preserves recency and releases only the oldest result at its bound',async()=>{
  const h=host(),store=h.store,released=[];store.services.runner={releaseOutputs:async result=>released.push(result.taskId)};
  const result=id=>({schemaVersion:1,taskId:id,attemptId:'a',status:'success',warnings:[],outputs:[],validation:{state:'not_evaluated',validatorVersion:'fixture',evidenceRefs:[]},engines:[],elapsedMs:0,nativePeakBytes:0,tempPeakBytes:0});
  for(let i=0;i<100;i++)store.saveNativeResult('r'+i,result('r'+i));
  assert.equal(store.nativeResultSnapshot('r0').taskId,'r0');store.saveNativeResult('r100',result('r100'));await flush();
  assert.equal(store.nativeResultSnapshot('r1'),undefined);assert.equal(store.nativeResults.size,100);assert.deepEqual(released,['r1']);
 });
 await test('Six preview components have bounded local state and the page supplies four observed VMs',()=>{
  const source=path.join(root,'entry/src/main/ets');for(const name of ['SourceFormatSelector','TargetFormatSelector','FidelityConfigPanel','AuthorizedFilePanel','ConversionProgressPanel','ConversionErrorBanner']){
   const text=fs.readFileSync(path.join(source,'components',name+'.ets'),'utf8');assert.match(text,/@Preview/);assert.ok((text.match(/@State/g)||[]).length<=5);
  }
  const page=fs.readFileSync(path.join(source,'pages/ConverterPage.ets'),'utf8');assert.equal((page.match(/@State/g)||[]).length,4);
  assert.doesNotMatch(page,/clone\(/);assert.ok(page.split('\n').length<150);
 });

 const report={scope:'architecture_logic_with_host_sdk_adapters',result:'passed',testedCases:cases.length,cases,
  deviceExecution:'not_executed',previewerExecution:'not_executed'};
 fs.writeFileSync(path.join(root,'tests/generated/architecture-check-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({result:'passed',testedCases:cases.length}));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
