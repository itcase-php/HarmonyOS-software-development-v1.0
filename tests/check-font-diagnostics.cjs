'use strict';
// Real bridge/models/scheduler, with explicitly modeled Native and filesystem.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {host} = require('./check-interactions.cjs');
const h = host({debugBuild:false});
const meta = h.load('./generated/RegistryData').registryMetadata;
const route = h.planner.routes('docx','pdf')[0];
const request = {schemaVersion:1,sessionId:'session',taskId:'task',attemptId:'attempt',workspaceRef:'workspace',
  operation:route.operation,inputs:[{fileId:'file',sourceFormatId:'docx',relativePath:'inputs/file',byteSize:100,sha256:'c'.repeat(64)}],
  targetFormatId:'pdf',qualityMode:'balanced',intent:route.intent,
  options:{office:{missingFontPolicy:'reject',allowedDegradations:[],includeReferencePages:false}},resourceBudget:meta.defaultBudget,
  plan:{routeId:route.id,steps:route.steps,fallbackRouteIds:[],configVersion:meta.configVersion,configSha256:meta.matrixSha256,
    policyVersion:meta.securityPolicy.version,intent:route.intent,minimumTier:route.fidelityTier,allowedDegradations:[]}};
function failure(req, reason='OFFICE_REQUIRED_FONT_MISSING') {
  return {schemaVersion:1,taskId:req.taskId,attemptId:req.attemptId,status:'failed',
    error:{code:'FONT_MISSING',reason,module:'office',stage:'executing',retryable:false,traceId:'',messageKey:'errors.FONT_MISSING'},
    fontDiagnostics:[{family:'Missing Font',part:'word/header1.xml'}],outputs:[],warnings:[],engines:[],
    validation:{state:'not_evaluated',validatorVersion:'not-evaluated',evidenceRefs:[]},elapsedMs:1,nativePeakBytes:0,tempPeakBytes:0};
}
const flush = async () => {for(let i=0;i<15;i++) await Promise.resolve();};
(async()=>{
  let response=failure(request);
  const native={getCapabilities:async()=>({}),execute:async()=>response};
  const Bridge=h.load('./services/NativeBridge').NativeBridgeService;
  const bridge=new Bridge({load:async()=>native},{prepareOffice:async()=>{}});
  const result=await bridge.execute(request);
  assert.equal(result.fontDiagnostics[0].family,'Missing Font');
  const Snapshot=h.load('./models/ConversionSnapshot').ConversionSnapshot;
  const copied=Snapshot.copyConvertResult(result);
  copied.fontDiagnostics[0].family='changed';assert.equal(result.fontDiagnostics[0].family,'Missing Font');
  delete response.fontDiagnostics;
  assert.equal((await bridge.execute(request)).fontDiagnostics,undefined);
  for(const invalid of [[{family:'x'.repeat(257),part:'word/document.xml'}], [{family:'bad\nfont',part:'word/document.xml'}],
    [{family:'Font',part:'../../secret.xml'}], [{family:'Font',part:'/data/private.xml'}], Array(4097).fill({family:'Font',part:'word/document.xml'})]) {
    response={...failure(request),fontDiagnostics:invalid};
    await assert.rejects(bridge.execute(request),error=>error.reason==='FONT_DIAGNOSTICS_RESPONSE');
  }
  const status=new (h.load('./viewmodel/ConversionStatusVM').ConversionStatusVM)(h.store);
  assert.equal(status.inputFailureKey('OFFICE_REQUIRED_FONT_MISSING'),'input_office_font_missing');
  assert.equal(status.inputFailureKey('OFFICE_FONT_INVENTORY_EMPTY'),'input_office_font_inventory_failed');
  assert.equal(status.inputFailureKey('OFFICE_FONT_USAGE_UNRESOLVED'),'input_office_font_usage_unsupported');
  assert.ok(status.fontDiagnosticText(failure(request).fontDiagnostics).includes('Missing Font'));
  assert.ok(status.fontDiagnosticText(failure(request).fontDiagnostics).includes('页眉'));
  const deps=h.store.services;let destroyed=0,executed=0,released=0;
  const session={sessionId:'owned',workspaceRef:'/cache/workspace/owned',createdAt:h.now(),inputFiles:[]};
  deps.files={getSession:()=>session,getWorkspaceRoot:()=>'/cache/workspace',destroySession:async()=>{destroyed++;}};
  deps.authorized={prepare:async()=>request};
  deps.native={initializeSession:async()=> 'new-session',registerWorkspace:async()=> 'new-workspace',releaseTask:async()=>{released++;}};
  deps.runner.run=async req=>{executed++;return failure(req,executed===1?'OFFICE_REQUIRED_FONT_MISSING':'OFFICE_GLYPH_MISSING');};
  deps.runner.releaseOutputs=async()=>{};
  const task=await h.store.submitTask('sample.docx','docx','pdf',route.id,false,undefined,[{originalName:'sample.docx'}],session);
  h.store.advance(h.now());await flush();
  assert.equal(executed,1);assert.equal(destroyed,0);assert.equal(h.store.canRetryFontFallback(task.id),true);
  const shown=h.store.snapshot()[0];assert.equal(shown.fontDiagnostics[0].family,'Missing Font');
  shown.fontDiagnostics[0].family='changed';assert.equal(h.store.snapshot()[0].fontDiagnostics[0].family,'Missing Font');
  await assert.rejects(h.store.retryFontFallback(task.id),error=>error.reason==='NATIVE_APPROVAL_REQUIRED');
  const retried=await h.store.retryFontFallback(task.id,true);
  assert.notEqual(retried.id,task.id);assert.equal(h.store.canRetryFontFallback(task.id),false);
  const prepared=h.store.nativeRequests.get(retried.id);
  assert.equal(prepared.options.office.missingFontPolicy,'approved_fallback');assert.deepEqual(Array.from(prepared.plan.allowedDegradations),['font_substitution']);
  assert.equal(prepared.inputs[0].sha256,request.inputs[0].sha256);
  h.store.advance(h.now());await flush();assert.equal(executed,2);assert.equal(destroyed,1);
  assert.equal(h.store.canRetryFontFallback(retried.id),false);
  h.store.shutdown();
  // A retained failed source must also be released on history clear / shutdown.
  const h2=host({debugBuild:false});const store2=h2.store;let cleanups=0;
  const deps2=store2.services;
  deps2.files={getSession:()=>session,getWorkspaceRoot:()=>'/cache/workspace',destroySession:async()=>{cleanups++;}};
  deps2.authorized={prepare:async()=>({...request,taskId:'clear-task'})};
  deps2.runner.run=async req=>failure(req);deps2.runner.releaseOutputs=async()=>{};
  deps2.native={releaseTask:async()=>{}};
  await store2.submitTask('clear.docx','docx','pdf',route.id,false,undefined,[{originalName:'clear.docx'}],session);
  store2.advance(h2.now());await flush();assert.equal(cleanups,0);
  store2.clearFinished();await flush();assert.equal(cleanups,1);
  deps2.authorized.prepare=async()=>({...request,taskId:'shutdown-task'});
  await store2.submitTask('close.docx','docx','pdf',route.id,false,undefined,[{originalName:'close.docx'}],session);
  store2.advance(h2.now());await flush();assert.equal(cleanups,1);
  store2.shutdown();await store2.releaseAuthorizedSessions(async()=>{});assert.equal(cleanups,2);
  const report={scope:'actual ArkTS with modeled Native/filesystem; no phone or conversion',passed:17,
    optionalBackwardCompatibility:true,detachedSnapshots:true,boundedDiagnostics:true,distinctFontErrors:true,
    explicitRetryApproval:true,retainedInputRetry:true,glyphFailureCannotRetry:true,historyAndShutdownReleaseRetainedInputs:true,device:'not executed'};
  fs.writeFileSync(path.join(__dirname,'generated/font-diagnostics.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
})().catch(error=>{h.store.shutdown();console.error(error);process.exitCode=1;});
