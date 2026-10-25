'use strict';
// Real Release-mode registry, preflight, bridge and dispatcher; explicitly modeled Native/PDF SDK.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const h = host({debugBuild:false});
const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
const meta = h.load('./generated/RegistryData').registryMetadata;
const routes = registry.listPlannedRoutes();
const counters = {executed:0, officePrepared:0, pdfVerified:0, tasksReleased:0, artifactsReleased:0};
const capabilities = {schemaVersion:1,offlineOnly:true,abi:'arm64-v8a',configVersion:meta.configVersion,
  engines:['image','office'].map(engineId=>({engineId,version:'host-model',buildHash:'a'.repeat(64)})),
  routes:routes.map(route=>({routeId:route.id,availability:'experimental'}))};
let parseFails = false;
const native = {getCapabilities:async()=>capabilities,
  probeInputs:async request=>request.inputs.map(input=>({fileId:input.fileId,actualFormatId:input.sourceFormatId,
    protection:'none',needsDeepCheck:false})),
  subscribeProgress:async()=> 'progress-model',unsubscribeProgress:async()=>true,
  execute:async request=>{counters.executed++;return {schemaVersion:1,taskId:request.taskId,attemptId:request.attemptId,
    status:'success',outputs:[{artifactId:'model',role:'primary',formatId:'pdf',internalRef:'artifact:'+'a'.repeat(32),
      sha256:'b'.repeat(64),byteSize:100}],validation:{state:'passed',validatorVersion:'host-model',evidenceRefs:['model']},
    engines:capabilities.engines,warnings:[],elapsedMs:1,nativePeakBytes:0,tempPeakBytes:100};},
  releaseTask:async()=>{counters.tasksReleased++;},releaseArtifact:async()=>{counters.artifactsReleased++;}};
const runtime = {prepareOffice:async()=>{counters.officePrepared++;},verifyPdf:async()=>{
  counters.pdfVerified++;if(parseFails)throw new Error('modeled parser failure');}};
const Bridge = h.load('./services/NativeBridge').NativeBridgeService;
const bridge = new Bridge({load:async()=>native},runtime);
const runner = new (h.load('./services/NativeTaskRunner').NativeTaskRunnerService)(registry,bridge);
const preflight = new (h.load('./services/RealTaskPreflight').RealTaskPreflight)(registry,bridge);
function request(route,approved=false) {
  const office=['docx-pdf','pptx-pdf'].includes(route.id);
  const allowed=office&&approved?['font_substitution']:[];
  return {schemaVersion:1,taskId:'release-'+route.id,attemptId:'attempt',sessionId:'session',workspaceRef:'workspace',
    operation:route.operation,inputs:[{fileId:'file',sourceFormatId:route.from[0],relativePath:'input.'+route.from[0],
    byteSize:100,sha256:'c'.repeat(64)}],targetFormatId:'pdf',qualityMode:'balanced',intent:route.intent,
    options:office?{office:{allowedDegradations:allowed,includeReferencePages:false,
      missingFontPolicy:approved?'approved_fallback':'reject'}}:{},
    resourceBudget:meta.defaultBudget,plan:{routeId:route.id,steps:route.steps,fallbackRouteIds:[],
      configVersion:meta.configVersion,configSha256:meta.matrixSha256,policyVersion:meta.securityPolicy.version,
      intent:route.intent,minimumTier:route.fidelityTier,allowedDegradations:allowed}};
}
(async()=>{
  assert.equal(registry.availableRoutes(capabilities).length,4);
  for(const route of routes) {
    await preflight.inspect(route.id,route.from[0],route.to);
    const result = await runner.run(runner.prepare(request(route),true),()=>{},()=>true);
    assert.equal(result.status,'success');
  }
  assert.deepEqual(counters,{executed:4,officePrepared:2,pdfVerified:3,tasksReleased:4,artifactsReleased:0});
  const fallback=request(routes.find(route=>route.id==='docx-pdf'),true);
  assert.throws(()=>runner.prepare(fallback,false),error=>error.reason==='NATIVE_APPROVAL_REQUIRED');
  const confirmed=runner.prepare(fallback,true);
  assert.equal(confirmed.options.office.missingFontPolicy,'approved_fallback');
  assert.deepEqual(Array.from(confirmed.plan.allowedDegradations),['font_substitution']);
  parseFails = true;
  await assert.rejects(runner.run(request(routes.find(route=>route.id==='png-pdf')),()=>{},()=>true),
    error=>error.code==='OUTPUT_VALIDATION_FAILED');
  assert.equal(counters.artifactsReleased,1);assert.equal(counters.tasksReleased,5);
  capabilities.engines = [];
  await assert.rejects(preflight.inspect('docx-pdf','docx','pdf'),error=>error.code==='ENGINE_MISSING');
  assert.equal(counters.executed,5);
  assert.equal(registry.listPlannedRoutes().some(route=>route.id==='pdf-docx'),false);
  const Coordinator = h.load('./viewmodel/ConverterCoordinator').ConverterCoordinator;
  let picked=0,enqueued=0;
  const coordinator = new Coordinator({registryReady:true},{authorizedFiles:[],pickSourceFiles:()=>{picked++;}},
    {working:false,confirming:false,inputBusy:false,setOnChange:()=>{}},{enqueue:()=>{enqueued++;}},{});
  coordinator.start();assert.equal(picked,1);assert.equal(enqueued,0);
  h.store.shutdown();
  const report={scope:'actual Release ArkTS with modeled Native, not real engine/device execution',
    result:'passed',fourRoutesDispatch:true,missingEngineBlocked:true,failedPdfReleased:true,
    deferredRoutesDisabled:true,releaseCannotCreateImplicitDemo:true,counters,deviceExecution:'not executed'};
  fs.writeFileSync(path.join(__dirname,'generated/release-routes-host-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
})().catch(error=>{console.error(error);process.exitCode=1;});
