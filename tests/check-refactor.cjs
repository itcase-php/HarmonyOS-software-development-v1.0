'use strict';
// Runs actual model/dispatcher sources with mocked Native exports. No real engine runs.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
const cases = [];
const copy = value => JSON.parse(JSON.stringify(value));
async function flush() { for (let i=0; i<60; i++) await Promise.resolve(); }
async function test(name,fn) { await fn(); cases.push({name,result:'passed'}); }
function fixture({available=true, protection='none', deep=false, engines=true}={}) {
  const h = host();
  const {registryMetadata} = h.load('./generated/RegistryData');
  const {FormatRegistry} = h.load('./services/FormatRegistry');
  const route = FormatRegistry.shared().routes.find(item=>item.id==='png-pdf');
  if (available) route.status='available'; // Isolated VM fixture; never edits shared JSON.
  const request = {schemaVersion:1,taskId:'native-fixture',attemptId:'attempt-fixture',sessionId:'authorized-fixture',
    workspaceRef:'workspace-fixture',operation:route.operation,inputs:[{fileId:'input-fixture',sourceFormatId:'png',
      relativePath:'input.png',byteSize:12,sha256:'a'.repeat(64)}],targetFormatId:'pdf',qualityMode:'balanced',
    intent:route.intent,options:{image:{quality:95,backgroundArgb:0xffffffff,metadataPolicy:'remove',
      colorPolicy:'preserve_profile',normalizeOrientation:true}},resourceBudget:copy(registryMetadata.defaultBudget),
    plan:{routeId:route.id,steps:copy(route.steps),fallbackRouteIds:[],configVersion:registryMetadata.configVersion,
      configSha256:registryMetadata.matrixSha256,intent:route.intent,minimumTier:'extreme',allowedDegradations:[],
      policyVersion:registryMetadata.securityPolicy.version}};
  const report = {schemaVersion:1,intent:route.intent,requestedTier:'extreme',achievedTier:'extreme',
    sourcePageCount:1,outputPageCount:1,metrics:[{name:'layout_similarity',state:'measured',value:0.991,
      unit:'ratio',algorithmVersion:'host-fixture-only',evidenceRefs:['fixture-evidence']}],fontSubstitutions:['fixture-font'],
    unsupportedFeatures:[],degradations:[],requiresManualReview:false,detectorVersion:'host-fixture-only',evidenceRefs:['fixture-evidence']};
  const result = {schemaVersion:1,taskId:request.taskId,attemptId:request.attemptId,status:'success',warnings:[],
    outputs:[{artifactId:'artifact-fixture',role:'primary',formatId:'pdf',internalRef:'fixture-internal-ref',
      byteSize:12,sha256:'b'.repeat(64)}],validation:{state:'passed',validatorVersion:'host-fixture-only',evidenceRefs:['fixture-evidence']},
    fidelity:report,engines:[],elapsedMs:120,nativePeakBytes:12,tempPeakBytes:12};
  let resolveExecution;
  const execution = new Promise(resolve=>{resolveExecution=resolve;});
  const trace = {capabilities:0,probes:0,execute:0,releaseTasks:0,unsubscribe:0,cancel:0,releasedOutputs:[],progress:null,request:null};
  const native = {
    getCapabilities:async()=>{trace.capabilities++;return {schemaVersion:1,offlineOnly:true,abi:'host-fixture',
      configVersion:registryMetadata.configVersion,
      engines:engines ? [...new Set(route.steps.map(step=>step.executorEngineId))].map(engineId=>({engineId,version:'fixture',buildHash:'c'.repeat(64)})) : [],
      routes:available ? [{routeId:route.id,availability:'available',reason:'fixture-only',releaseEvidenceId:'fixture-evidence'}] : []};},
    probeInputs:async()=>{trace.probes++;return [{fileId:'input-fixture',actualFormatId:'png',protection,needsDeepCheck:deep}];},
    subscribeProgress:(id,callback)=>{trace.progress=callback;return 'fixture-subscription';},
    unsubscribeProgress:()=>{trace.unsubscribe++;return true;},
    execute:async value=>{trace.execute++;trace.request=value;return execution;},
    cancel:async()=>{trace.cancel++;return {taskId:request.taskId,attemptId:request.attemptId,state:'accepted'};},
    releaseTask:async()=>{trace.releaseTasks++;},
    releaseArtifact:async ref=>{trace.releasedOutputs.push(ref);}
  };
  h.setNative(native);
  return {h,request,result,trace,native,finish(value=result){resolveExecution(value);}};
}
async function main() {
  await test('Model clone copies every present data field and isolates nested report arrays',()=>{
    const h=host(); const started=h.store.enqueue('clone.pdf','pdf','png','pdf-png');h.store.advance(h.now());
    h.step(3500);h.store.advance(h.now()); const original=h.store.snapshot()[0];
    for (const key of Object.keys(original)) {
      if (typeof original[key]==='string') original[key]='clone-marker-'+key;
      else if (typeof original[key]==='number') original[key]=123;
      else if (typeof original[key]==='boolean') original[key]=!original[key];
    }
    const cloned=original.clone();
    assert.deepEqual(Object.keys(cloned).sort(),Object.keys(original).sort());
    assert.deepEqual(cloned,original);assert.notEqual(cloned,original);
    assert.notEqual(cloned.fidelityReport,original.fidelityReport);
    cloned.fidelityReport.metrics[0].evidenceRefs.push('mutated');
    assert.equal(original.fidelityReport.metrics[0].evidenceRefs.length,0);
    assert.equal(h.store.snapshot()[0].id,started.id);
  });
  await test('Native task cannot enter the simulated report factory',()=>{
    const h=host();const {DemoTask}=h.load('./models/InteractionModels');
    const task=new DemoTask();task.mode='native';
    const {DemoFidelityReport}=h.load('./viewmodel/DemoFidelityReport');
    assert.throws(()=>DemoFidelityReport.create(task,'extreme',[]),error=>error.reason==='DEMO_REPORT_NATIVE_TASK');
  });
  await test('A recreated application session gets a usable store after shutdown',()=>{
    const h=host();const {TaskStore}=h.load('./viewmodel/TaskStore');
    const previous=TaskStore.shared();previous.shutdown();const current=TaskStore.shared();
    assert.notEqual(previous,current);
    const task=current.enqueue('reopen.pdf','pdf','png','pdf-png');assert.equal(task.status,'queued');
    current.shutdown();assert.equal(h.timers.size,0);
  });
  await test('Planned capability blocks Native before probe/execute with no demo report',async()=>{
    const f=fixture({available:false}); f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());
    await flush(); const task=f.h.store.snapshot()[0];
    assert.equal(task.mode,'native');assert.equal(task.status,'failed');
    assert.match(task.error,/NATIVE_ROUTE_UNAVAILABLE/);
    assert.equal(task.fidelityReport,undefined);assert.equal(task.achievedTier,undefined);
    assert.equal(f.trace.probes,0);assert.equal(f.trace.execute,0);assert.equal(f.h.timers.size,0);
    f.h.store.shutdown();
  });
  await test('Missing executors and protected/unverified probes cannot execute',async()=>{
    for (const options of [{engines:false},{protection:'drm'},{protection:'signed'},{protection:'encrypted'},{protection:'unknown'},{deep:true}]) {
      const f=fixture(options);f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());await flush();
      assert.equal(f.h.store.snapshot()[0].status,'failed');assert.equal(f.trace.execute,0);
      assert.equal(f.trace.releaseTasks,1);f.h.store.shutdown();
    }
  });
  await test('Native request snapshot, single dispatch and monotonic progress are preserved',async()=>{
    const f=fixture();f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());f.request.options.image.quality=1;
    f.request.qualityMode='fast';f.request.plan.steps[0].executorEngineId='caller-mutation';
    await flush();assert.equal(f.trace.execute,1);assert.equal(f.trace.request.qualityMode,'balanced');
    assert.equal(f.trace.request.options.image.quality,95);
    const progress=(sequence,fraction,attemptId='attempt-fixture')=>({taskId:'native-fixture',attemptId,
      stage:'executing',sequence,unit:'steps',completedUnits:1,totalUnits:2,fraction});
    f.trace.progress(progress(1,.5));assert.equal(f.h.store.snapshot()[0].progress,50);
    f.trace.progress(progress(0,.9));f.trace.progress(progress(2,.3));f.trace.progress(progress(3,.9,'stale-attempt'));
    assert.equal(f.h.store.snapshot()[0].progress,50);
    for(let i=0;i<5;i++)f.h.store.advance(f.h.now());assert.equal(f.trace.execute,1);
    assert.equal(f.h.store.pause('native-fixture'),false);
    f.finish();await flush();const done=f.h.store.snapshot()[0];
    assert.equal(done.status,'completed');assert.equal(done.elapsedMs,120);
    assert.equal(done.fidelityReport.metrics[0].state,'measured');assert.equal(done.fidelityReport.metrics[0].value,.991);
    assert.equal(done.fidelityReport.requiresManualReview,false);assert.equal(done.fidelityReport.sourcePageCount,1);
    assert.equal(f.trace.unsubscribe,1);assert.equal(f.trace.releaseTasks,1);
    f.result.fidelity.metrics[0].value=0;assert.equal(f.h.store.snapshot()[0].fidelityReport.metrics[0].value,.991);
    assert.equal(f.h.store.clearFinished(),1);await flush();assert.deepEqual(f.trace.releasedOutputs,['fixture-internal-ref']);
    f.h.store.shutdown();
  });
  await test('Missing Native report stays missing and does not fabricate an achieved tier',async()=>{
    const f=fixture();delete f.result.fidelity;f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());await flush();
    f.finish();await flush();const done=f.h.store.snapshot()[0];
    assert.equal(done.status,'completed');assert.equal(done.fidelityReport,undefined);assert.equal(done.achievedTier,undefined);
    f.h.store.shutdown();await flush();assert.equal(f.trace.releasedOutputs.length,1);
  });
  await test('Invalid Native fidelity options or below-minimum grade fail and release outputs',async()=>{
    for (const change of [report=>{report.intent='content_only';},report=>{report.achievedTier='compatible';},
      report=>{report.metrics[0].value=42;},report=>{report.metrics[0].evidenceRefs=[];}]) {
      const f=fixture();change(f.result.fidelity);f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());await flush();
      f.finish();await flush();const failed=f.h.store.snapshot()[0];assert.equal(failed.status,'failed');
      assert.equal(failed.fidelityReport,undefined);assert.equal(failed.achievedTier,undefined);
      assert.equal(f.trace.releasedOutputs.length,1);f.h.store.shutdown();
    }
  });
  await test('Native cancellation holds scheduler slot until cleanup and ignores late success',async()=>{
    const f=fixture();f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());await flush();
    const queued=f.h.store.enqueue('next.pdf','pdf','png','pdf-png');
    f.h.store.cancel('native-fixture');await flush();assert.equal(f.trace.cancel,1);
    assert.equal(f.h.store.snapshot().find(task=>task.id===queued.id).status,'queued');
    f.finish();await flush();const cancelled=f.h.store.snapshot().find(task=>task.id==='native-fixture');
    assert.equal(cancelled.status,'cancelled');assert.equal(cancelled.fidelityReport,undefined);
    assert.equal(f.trace.releasedOutputs.length,1);
    assert.equal(f.h.store.snapshot().find(task=>task.id===queued.id).status,'running');f.h.store.shutdown();
  });
  await test('Shutdown during Native work cannot start queued tasks or resurrect late results',async()=>{
    const f=fixture();f.h.store.enqueueNative('input.png',f.request);f.h.store.advance(f.h.now());await flush();
    f.h.store.enqueue('queued.pdf','pdf','png','pdf-png');f.h.store.shutdown();
    f.finish();await flush();assert.ok(f.h.store.snapshot().every(task=>task.status==='cancelled'));
    assert.equal(f.h.timers.size,0);assert.equal(f.trace.releaseTasks,1);assert.equal(f.trace.releasedOutputs.length,1);
  });
  await test('Tampered approved plan is rejected before enqueue or Native load',()=>{
    const f=fixture();f.request.plan.steps[0].executorEngineId='tampered';
    assert.throws(()=>f.h.store.enqueueNative('input.png',f.request),error=>error.reason==='NATIVE_APPROVED_PLAN_MISMATCH');
    assert.equal(f.h.store.snapshot().length,0);assert.equal(f.h.nativeLoads(),0);
  });
  await test('UI resource keys are present in base and English catalogs with matching placeholders',()=>{
    const source=path.join(root,'entry/src/main/ets');
    const files=['common/FidelityText.ets','components/FidelitySettingsCard.ets','components/QualitySelector.ets',
      'components/FidelityReportCard.ets','components/FidelityConfigPanel.ets','components/AuthorizedFilePanel.ets','components/SourceFormatSelector.ets','components/TargetFormatSelector.ets','components/ConversionErrorBanner.ets','components/ConversionProgressPanel.ets','viewmodel/FormatSelectionVM.ets','viewmodel/ConversionStatusVM.ets','pages/ConverterPage.ets','pages/TaskHistory.ets'];
    const base=JSON.parse(fs.readFileSync(path.join(root,'entry/src/main/resources/base/element/string.json'),'utf8')).string;
    const english=JSON.parse(fs.readFileSync(path.join(root,'entry/src/main/resources/en_US/element/string.json'),'utf8')).string;
    assert.equal(new Set(base.map(item=>item.name)).size,base.length);
    for(const file of files) {
      for(const [,key] of fs.readFileSync(path.join(source,file),'utf8').matchAll(/\$r\('app\.string\.([^']+)'\)/g)) {
        const a=base.find(item=>item.name===key),b=english.find(item=>item.name===key);
        assert.ok(a&&b,'Missing localized resource '+key);
        assert.equal((a.value.match(/%s/g)||[]).length,(b.value.match(/%s/g)||[]).length);
      }
    }
    assert.match(fs.readFileSync(path.join(source,'components/FidelityConfigPanel.ets'),'utf8'),/FidelitySettingsCard\(/);
    assert.doesNotMatch(fs.readFileSync(path.join(source,'pages/ConverterPage.ets'),'utf8'),/fidelitySettings\(\)/);
    assert.match(fs.readFileSync(path.join(source,'components/FidelitySettingsCard.ets'),'utf8'),/accessibilityDescription/);
  });
  const report={scope:'refactor_logic_with_mock_native_not_real_engine',result:'passed',testedCases:cases.length,cases,
    nativeCalls:'mocked_exports_only',realConversion:'not_executed',deviceExecution:'not_executed',previewerExecution:'not_executed'};
  fs.writeFileSync(path.join(root,'tests/generated/refactor-check-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
