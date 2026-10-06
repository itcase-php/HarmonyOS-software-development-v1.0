'use strict';
// Audit regressions: actual ArkTS services, with host adapters for SDK/Native calls.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {host}=require('./check-interactions.cjs');
const root=path.resolve(__dirname,'..');
const cases=[];
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const bytes=name=>new Uint8Array(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/format-registry',name)));
async function flush() {for(let i=0;i<60;i++) await Promise.resolve();}
async function test(name,fn) {await fn();cases.push({name,result:'passed'});}
function cold(options={}) {
 const h=host({...options,registryReady:false});
 return {h,registry:h.load('./services/FormatRegistry').FormatRegistry.shared()};
}
const capabilities=version=>({schemaVersion:1,offlineOnly:true,abi:'host-adapter',configVersion:version,engines:[],routes:[]});
async function main() {
 await test('Generated metadata pins rawfile hashes counts and the approved JPEG Debug matrix',()=>{
  const source=read('entry/src/main/ets/generated/RegistryData.ets');
  const metadata=JSON.parse(source.match(/export const registryMetadata: RegistryMetadata = ([\s\S]*?);\n/)[1]);
  assert.ok(source.split('\n').length<200);
  const {h}=cold();const generated=h.load('./generated/RegistryData');
  const formats=generated.catalogueCategories.flatMap(category=>generated.loadBundledFormats(category)).sort((a,b)=>generated.formatOrder.indexOf(a.id)-generated.formatOrder.indexOf(b.id));
  const routes=generated.catalogueCategories.flatMap(category=>generated.loadBundledRoutes(category)).sort((a,b)=>generated.routeOrder.indexOf(a.id)-generated.routeOrder.indexOf(b.id));
  assert.deepEqual(JSON.parse(JSON.stringify(formats)),JSON.parse(Buffer.from(bytes('formats.json')).toString()).formats);
  assert.deepEqual(JSON.parse(JSON.stringify(routes)),JSON.parse(Buffer.from(bytes('conversion-matrix.json')).toString()).routes);
  for(const [name,key] of [['formats.json','formatsSha256'],['conversion-matrix.json','matrixSha256']])
   assert.equal(crypto.createHash('sha256').update(bytes(name)).digest('hex'),metadata[key]);
  assert.equal(metadata.formatsCount,18);assert.equal(metadata.routesCount,43);
  assert.ok(JSON.parse(Buffer.from(bytes('conversion-matrix.json')).toString()).routes.every(
   route=>route.status===(route.id==='jpeg-pdf'?'experimental':'planned')));
 });
 await test('Cold registry immediately exposes all 18 approved formats and 43 catalogue routes',()=>{
  const {h,registry}=cold();
  assert.deepEqual(JSON.parse(JSON.stringify(registry.listFormats())),JSON.parse(Buffer.from(bytes('formats.json')).toString()).formats);
  assert.deepEqual(JSON.parse(JSON.stringify(registry.listPlannedRoutes())),JSON.parse(Buffer.from(bytes('conversion-matrix.json')).toString()).routes);
  assert.equal(registry.isInitialized(),false);assert.equal(registry.availableRoutes(capabilities('1.0.0-design')).length,0);
  assert.equal(h.timers.size,0);
 });
 await test('Failed initialization installs no partial snapshot and the next request can retry',async()=>{
  const {h,registry}=cold();const resources={getRawFileContent:async name=>name.endsWith('/formats.json')?bytes('formats.json'):new Uint8Array()};
  await assert.rejects(()=>registry.initialize(resources),error=>error.reason==='BUNDLED_RESOURCE_EMPTY');
  assert.equal(registry.isInitialized(),false);assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
  await registry.initialize(h.resources);assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
  assert.equal(h.timers.size,0);
 });
 await test('Concurrent initializers share one read and atomically cache both documents',async()=>{
  const {h,registry}=cold();let reads=0;
  const resources={getRawFileContent:async name=>{reads++;return h.resources.getRawFileContent(name);}};
  await Promise.all([registry.initialize(resources),registry.initialize(resources),registry.initialize(resources)]);
  assert.equal(reads,2);await registry.initialize(resources);assert.equal(reads,2);assert.equal(h.timers.size,0);
 });
 await test('Pinned metadata mismatch rejects initialization even if rawfile hashes match',async()=>{
  const {h,registry}=cold();const {registryMetadata}=h.load('./generated/RegistryData');registryMetadata.formatsCount++;
  await assert.rejects(()=>registry.initialize(h.resources),error=>error.reason==='BUNDLED_RESOURCE_METADATA_MISMATCH');
  assert.equal(registry.isInitialized(),false);assert.equal(h.timers.size,0);
 });
 await test('Unavailable SDK hashing safely blocks cache publication',async()=>{
  const {h,registry}=cold({cryptoAvailable:false});
  await assert.rejects(()=>registry.initialize(h.resources),error=>error.reason==='BUNDLED_RESOURCE_HASH_UNAVAILABLE');
  assert.equal(registry.isInitialized(),false);assert.equal(h.timers.size,0);
 });
 await test('Initialization timeout permits retry and ignores later data from the timed-out reader',async()=>{
  const {h,registry}=cold();let finishFormats,finishMatrix;
  const resources={getRawFileContent:name=>new Promise(resolve=>{
   if(name.endsWith('/formats.json'))finishFormats=resolve;else finishMatrix=resolve;
  })};
  const pending=registry.initialize(resources);
  const rejected=assert.rejects(()=>pending,error=>error.reason==='BUNDLED_RESOURCE_TIMEOUT');
  h.fireTimeouts();await rejected;assert.equal(registry.isInitialized(),false);
  await registry.initialize(h.resources);const installed=registry.formats;
  finishFormats(bytes('formats.json'));finishMatrix(bytes('conversion-matrix.json'));await flush();
  assert.equal(registry.formats,installed);assert.equal(h.timers.size,0);
 });
 await test('Standalone preview and failed resource reads retain the complete catalogue and allow retry',async()=>{
  const {h,registry}=cold();const {RegistryUi}=h.load('./common/RegistryUi');
  await RegistryUi.ensure({getHostContext:()=>undefined});
  await RegistryUi.ensure({getHostContext:()=>{throw new Error('unsupported preview context');}});
  await RegistryUi.ensure({getHostContext:()=>({resourceManager:{getRawFileContent:async()=>{throw new Error('missing rawfile');}}})});
  assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
  assert.equal(registry.isInitialized(),false);assert.equal(h.timers.size,0);
  await RegistryUi.ensure({getHostContext:()=>({resourceManager:h.resources})});
  assert.equal(registry.isInitialized(),true);assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
 });
 await test('Unavailable preview hashing and modified resources preserve demo planning without approving Native routes',async()=>{
  for(const options of [{cryptoAvailable:false},{}]) {
   const {h,registry}=cold(options);const {RegistryUi}=h.load('./common/RegistryUi');
   const changed=bytes('conversion-matrix.json');changed[changed.length-1]^=1;
   const resources=options.cryptoAvailable===false?h.resources:{getRawFileContent:async name=>name.endsWith('/formats.json')?bytes('formats.json'):changed};
   await RegistryUi.ensure({getHostContext:()=>({resourceManager:resources})});
   assert.equal(registry.isInitialized(),false);assert.equal(registry.listFormats().length,18);assert.equal(registry.listPlannedRoutes().length,43);
   assert.equal(registry.availableRoutes(capabilities('1.0.0-design')).length,0);
   assert.equal(h.planner.bestRoute('png','pdf','layout_preserved','high_fidelity','extreme').id,'png-pdf');
   await assert.rejects(()=>registry.initialize(resources),error=>error.reason===
    (options.cryptoAvailable===false?'BUNDLED_RESOURCE_HASH_UNAVAILABLE':'BUNDLED_RESOURCE_HASH_MISMATCH'));
  }
 });
 await test('Unverified offline catalogue snapshots cannot be mutated by callers',()=>{
  const {registry}=cold();const formats=registry.listFormats(),routes=registry.listPlannedRoutes();
  formats[0].extensions.push('fixture-mutation');routes[0].steps[0].executorEngineId='fixture-mutation';
  assert.equal(registry.listFormats()[0].extensions.includes('fixture-mutation'),false);
  assert.notEqual(registry.listPlannedRoutes()[0].steps[0].executorEngineId,'fixture-mutation');
 });
 await test('Offline single-file targets intents minimum tiers and quality sorting match the verified catalogue',()=>{
  const offline=cold().h,verified=host();
  const ids=JSON.parse(Buffer.from(bytes('formats.json')).toString()).formats.map(format=>format.id);
  for(const source of ids) {
   assert.deepEqual(Array.from(offline.planner.targets(source),format=>format.id),Array.from(verified.planner.targets(source),format=>format.id));
   for(const target of ids)for(const mode of ['fast','balanced','high_fidelity'])
    for(const intent of [undefined,'layout_preserved','structured_rebuild','content_only'])
     for(const tier of [undefined,'compatible','standard','extreme']) {
      const actual=offline.planner.routes(source,target,mode,intent,tier);
      assert.deepEqual(Array.from(actual,route=>route.id),Array.from(verified.planner.routes(source,target,mode,intent,tier),route=>route.id));
      assert.ok(actual.every(route=>route.inputConstraints.minInputs<=1&&route.inputConstraints.maxInputs>=1));
      if(intent)assert.ok(actual.every(route=>route.intent===intent));
      if(tier) {
       const ranks={compatible:1,standard:2,extreme:3};assert.ok(actual.every(route=>ranks[route.fidelityTier]>=ranks[tier]));
      }
     }
  }
  assert.equal(offline.planner.routes('pdf','pdf').some(route=>route.id==='pdf-merge'),false);
  assert.equal(offline.planner.bestRoute('pdf','pptx','layout_preserved','high_fidelity','standard').id,'pdf-pptx-visual');
  assert.equal(offline.planner.bestRoute('pdf','pptx','structured_rebuild','high_fidelity','compatible').id,'pdf-pptx');
  assert.deepEqual(Array.from(offline.planner.routes('png','pdf','high_fidelity','layout_preserved'),route=>route.id),
   ['png-pdf','mixed-images-pdf','png-pdf-alternate','png-pdf-compatible']);
 });
 await test('Many Native callers share one failed import then one successful retry',async()=>{
  const h=host();const {NativeBridge}=h.load('./services/NativeBridge');
  const {registryMetadata}=h.load('./generated/RegistryData');
  const request={schemaVersion:1,sessionId:'bootstrap',configVersion:registryMetadata.configVersion};
  const failures=await Promise.allSettled([NativeBridge.getCapabilities(request),NativeBridge.getCapabilities(request),NativeBridge.getCapabilities(request)]);
  assert.ok(failures.every(result=>result.status==='rejected'&&result.reason.reason==='NATIVE_MODULE_NOT_AVAILABLE'));
  assert.equal(h.nativeLoads(),1);assert.equal(NativeBridge.isNativeAvailable(),false);
  h.setNative({getCapabilities:async()=>capabilities(registryMetadata.configVersion)});
  await Promise.all([NativeBridge.getCapabilities(request),NativeBridge.getCapabilities(request)]);
  assert.equal(h.nativeLoads(),2);assert.equal(NativeBridge.isNativeAvailable(),true);
  await NativeBridge.getCapabilities(request);assert.equal(h.nativeLoads(),2);
 });
 await test('A retry started by an early failed waiter survives another waiter rejecting',async()=>{
  const h=host();const {NativeBridge}=h.load('./services/NativeBridge');const {registryMetadata}=h.load('./generated/RegistryData');
  const request={schemaVersion:1,sessionId:'bootstrap',configVersion:registryMetadata.configVersion};
  const first=NativeBridge.getCapabilities(request).catch(()=>{
   h.setNative({getCapabilities:async()=>capabilities(registryMetadata.configVersion)});return NativeBridge.getCapabilities(request);
  });
  const second=NativeBridge.getCapabilities(request);const outcomes=await Promise.allSettled([first,second]);
  assert.equal(outcomes[0].status,'fulfilled');assert.equal(outcomes[1].status,'rejected');assert.equal(h.nativeLoads(),2);
  await NativeBridge.getCapabilities(request);assert.equal(h.nativeLoads(),2);
 });
 await test('Delayed initial queue publication starts at zero and default runtime has one recursive timer',()=>{
  const h=host();const tasks=['first','second','third'].map(name=>h.store.enqueue(name+'.pdf','pdf','png','pdf-png'));
  assert.ok(tasks.every(task=>task.status==='queued'&&task.progress===0));assert.equal(h.timers.size,1);
  h.step(50);h.fireTimeouts();assert.equal(h.store.snapshot().filter(task=>task.status==='running').length,1);
  assert.equal(h.timers.size,1);
  for(let i=0;i<54;i++){h.step(200);h.fireTimeouts();assert.ok(h.timers.size<=1);}
  assert.ok(h.store.snapshot().every(task=>task.status==='completed'));assert.equal(h.timers.size,0);
 });
 await test('Observer-triggered advances and observer failures cannot reenter or strand queue progression',()=>{
  const h=host();let notifications=0;
  h.store.enqueue('reentrant.pdf','pdf','png','pdf-png');
  h.store.subscribe(()=>{notifications++;h.store.advance(h.now());throw new Error('fixture observer');});
  h.store.advance(h.now());assert.equal(notifications,1);h.step(3500);h.store.advance(h.now());
  assert.equal(notifications,2);assert.equal(h.store.snapshot()[0].status,'completed');assert.equal(h.timers.size,0);
 });
 await test('Settings component consumes one VM and format browser resources have matching translations',()=>{
  const component=read('entry/src/main/ets/components/FidelitySettingsCard.ets');
  assert.equal((component.match(/@ObjectLink\b/g)||[]).length,1);assert.match(component,/@State expanded/);
  const page=read('entry/src/main/ets/pages/ConverterPage.ets');assert.match(page,/FidelityConfigPanel\(/);
  assert.match(read('entry/src/main/ets/components/FidelityConfigPanel.ets'),/FidelitySettingsCard\(\{ vm: this\.model/);
  assert.doesNotMatch(page,/@State (?:qualityMode|selectedIntent|requestedTier|intentChoices|tierChoices):/);
  const base=JSON.parse(read('entry/src/main/resources/base/element/string.json')).string;
  const english=JSON.parse(read('entry/src/main/resources/en_US/element/string.json')).string;
  for(const catalog of [base,english])assert.equal(new Set(catalog.map(item=>item.name)).size,catalog.length);
  const files=['pages/FormatBrowser.ets','components/PageHeader.ets','pages/ConverterPage.ets','common/RegistryUi.ets'];
  for(const file of files)for(const [,key] of read('entry/src/main/ets/'+file).matchAll(/\$r\('app\.string\.([^']+)'/g)) {
   const a=base.find(item=>item.name===key),b=english.find(item=>item.name===key);assert.ok(a&&b,key);
   assert.deepEqual(a.value.match(/%[sd]/g)||[],b.value.match(/%[sd]/g)||[],'Placeholder mismatch '+key);
  }
  const browser=read('entry/src/main/ets/pages/FormatBrowser.ets');assert.doesNotMatch(browser,/[\u4e00-\u9fff]/);
 });
 const generated=read('entry/src/main/ets/generated/RegistryData.ets');
 const report={scope:'audit_regressions_with_host_sdk_and_native_adapters',result:'passed',testedCases:cases.length,cases,
 registryDataLines:generated.trimEnd().split('\n').length,nativeCalls:'mocked_exports_only',
 realConversion:'not_executed',deviceExecution:'not_executed',previewerExecution:'not_executed'};
 fs.writeFileSync(path.join(root,'tests/generated/audit-check-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({result:report.result,testedCases:report.testedCases,registryDataLines:report.registryDataLines}));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
