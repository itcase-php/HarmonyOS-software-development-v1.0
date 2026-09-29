'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const root = path.resolve(__dirname,'..');
const cases = [];
function test(name,fn) { fn(); cases.push({name,result:'passed'}); }
function task(h,mode='balanced',tier='standard') {
  return h.store.enqueue('report.pdf','pdf','png','pdf-png',false,
    {qualityMode:mode,requestedIntent:'layout_preserved',requestedTier:tier});
}
test('Each quality mode retains options and completes at its specified active duration',()=>{
  for (const [mode,duration] of [['fast',2000],['balanced',3500],['high_fidelity',6000]]) {
    const h=host(); const created=task(h,mode);
    assert.equal(created.qualityMode,mode); assert.equal(created.requestedTier,'standard');
    assert.equal(created.intent,created.requestedIntent);
    h.step(duration-1); h.store.advance(h.now()); assert.equal(h.store.snapshot()[0].status,'running');
    h.step(1); h.store.advance(h.now()); const completed=h.store.snapshot()[0];
    assert.equal(completed.status,'completed'); assert.equal(completed.elapsedMs,duration);
    assert.equal(completed.achievedTier,'standard'); assert.equal(completed.fidelityReport.requestedTier,'standard');
    assert.equal(completed.fidelityReport.achievedTier,'standard'); assert.equal(h.nativeLoads(),0);
  }
});
test('Report begins at commit; achieved task tier is exposed only on completion',()=>{
  const h=host(); task(h); h.step(2974); h.store.advance(h.now());
  assert.equal(h.store.snapshot()[0].fidelityReport,undefined);
  h.step(1); h.store.advance(h.now()); let current=h.store.snapshot()[0];
  assert.equal(current.progress,85); assert.equal(current.status,'running');
  assert.equal(current.achievedTier,undefined); assert.equal(current.fidelityReport.detectorVersion,'demo-fidelity-v1');
  h.step(525); h.store.advance(h.now()); current=h.store.snapshot()[0];
  assert.equal(current.achievedTier,'standard'); assert.equal(current.mode,'demo');
  assert.equal(current.outputs,undefined);
});
test('Minimum fidelity cannot be exceeded by selecting a faster or higher quality mode',()=>{
  for (const mode of ['fast','balanced','high_fidelity']) {
    const h=host(); assert.throws(()=>task(h,mode,'extreme'),error=>error.reason==='FIDELITY_TIER_UNAVAILABLE');
    assert.equal(h.store.snapshot().length,0); assert.equal(h.timers.size,0);
    assert.equal(h.planner.bestRoute('pdf','png','layout_preserved',mode,'extreme'),undefined);
  }
});
test('Intent mismatch is blocked before queue insertion and bestRoute never changes intent',()=>{
  const h=host();
  assert.throws(()=>h.store.enqueue('x.pdf','pdf','docx','pdf-docx',false,
    {qualityMode:'balanced',requestedIntent:'layout_preserved',requestedTier:'compatible'}),
    error=>error.reason==='FIDELITY_INTENT_MISMATCH');
  const layout=h.planner.bestRoute('pdf','pptx','layout_preserved','high_fidelity','standard');
  assert.equal(layout.id,'pdf-pptx-visual');
  const structured=h.planner.bestRoute('pdf','pptx','structured_rebuild','high_fidelity','compatible');
  assert.equal(structured.id,'pdf-pptx');
  assert.equal(h.planner.bestRoute('pdf','pptx','structured_rebuild','high_fidelity','extreme'),undefined);
  assert.equal(h.store.snapshot().length,0);
});
test('Invalid fidelity enum values are rejected rather than defaulted silently',()=>{
  for (const invalid of [
    {qualityMode:'turbo',requestedIntent:'layout_preserved',requestedTier:'standard'},
    {qualityMode:'balanced',requestedIntent:'magic',requestedTier:'standard'},
    {qualityMode:'balanced',requestedIntent:'layout_preserved',requestedTier:'perfect'}
  ]) {
    const h=host(); assert.throws(()=>h.store.enqueue('x.pdf','pdf','png','pdf-png',false,invalid),
      error=>error.reason==='FIDELITY_OPTIONS_INVALID');
    assert.equal(h.store.snapshot().length,0);
  }
});
test('Selection is frozen at enqueue even if the caller mutates its options later',()=>{
  const h=host(); const selection={qualityMode:'fast',requestedIntent:'layout_preserved',requestedTier:'standard'};
  h.store.enqueue('x.pdf','pdf','png','pdf-png',false,selection);
  selection.qualityMode='high_fidelity'; selection.requestedIntent='content_only'; selection.requestedTier='extreme';
  h.step(2000); h.store.advance(h.now()); const done=h.store.snapshot()[0];
  assert.equal(done.status,'completed'); assert.equal(done.qualityMode,'fast');
  assert.equal(done.fidelityReport.intent,'layout_preserved'); assert.equal(done.fidelityReport.requestedTier,'standard');
});
test('In-flight reports use the route snapshot instead of later registry mutations',()=>{
  const h=host(); h.store.enqueue('x.png','png','pdf','png-pdf');
  const {FormatRegistry}=h.load('./services/FormatRegistry');
  const route=FormatRegistry.listPlannedRoutes().find(route=>route.id==='png-pdf');
  route.fidelityTier='compatible'; route.allowedDegradations.push('late-mutation');
  h.step(3500); h.store.advance(h.now()); const report=h.store.snapshot()[0].fidelityReport;
  assert.equal(report.achievedTier,'extreme'); assert.equal(report.requestedTier,'extreme');
  assert.equal(report.degradations.length,0);
});
test('Report snapshots deeply isolate metrics, evidence and warning arrays',()=>{
  const h=host(); task(h); h.step(3500); h.store.advance(h.now());
  const snapshot=h.store.snapshot()[0]; const originalValue=snapshot.fidelityReport.metrics[0].value;
  snapshot.qualityMode='fast'; snapshot.fidelityReport.metrics[0].value=42;
  snapshot.fidelityReport.metrics[0].evidenceRefs.push('fake-evidence');
  snapshot.fidelityReport.degradations.push('fake-loss'); snapshot.fidelityReport.unsupportedFeatures.length=0;
  const current=h.store.snapshot()[0];
  assert.equal(current.qualityMode,'balanced'); assert.equal(current.fidelityReport.metrics[0].value,originalValue);
  assert.equal(current.fidelityReport.metrics[0].evidenceRefs.length,0);
  assert.equal(current.fidelityReport.degradations.length,0);
  assert.ok(current.fidelityReport.unsupportedFeatures.length>0);
});
test('Explicitly approved compatible route records its degradation configuration',()=>{
  const h=host(); const options={qualityMode:'fast',requestedIntent:'layout_preserved',requestedTier:'compatible'};
  assert.throws(()=>h.store.enqueue('x.png','png','pdf','png-pdf-compatible',false,options),
    error=>error.reason==='DEMO_APPROVAL_REQUIRED');
  h.store.enqueue('x.png','png','pdf','png-pdf-compatible',true,options);
  h.step(2000); h.store.advance(h.now()); const report=h.store.snapshot()[0].fidelityReport;
  assert.equal(report.achievedTier,'compatible');
  assert.deepEqual(Array.from(report.degradations),['alpha_flatten','jpeg_reencode']);
});
test('Content-only report makes layout non-applicable and never emits measured document metrics',()=>{
  const h=host(); h.store.enqueue('x.pdf','pdf','txt','pdf-txt',false,
    {qualityMode:'high_fidelity',requestedIntent:'content_only',requestedTier:'compatible'});
  h.step(6000); h.store.advance(h.now()); const report=h.store.snapshot()[0].fidelityReport;
  assert.equal(report.intent,'content_only'); assert.equal(report.achievedTier,'compatible');
  assert.equal(report.metrics[0].state,'not_applicable'); assert.equal(report.metrics[0].value,undefined);
  assert.ok(report.metrics.every(metric=>metric.state!=='measured'));
  assert.ok(report.metrics.every(metric=>metric.evidenceRefs.length===0));
  assert.equal(report.sourcePageCount,undefined); assert.equal(report.outputPageCount,undefined);
  assert.equal(report.requiresManualReview,true); assert.equal(report.fontSubstitutions.length,0);
});
test('Cancelling or shutting down after commit removes provisional reports',()=>{
  for (const action of ['cancel','shutdown']) {
    const h=host(); const started=task(h); h.step(3000); h.store.advance(h.now());
    assert.ok(h.store.snapshot()[0].fidelityReport);
    if (action==='cancel') h.store.cancel(started.id); else h.store.shutdown();
    h.step(10000); h.store.advance(h.now()); const cancelled=h.store.snapshot()[0];
    assert.equal(cancelled.status,'cancelled'); assert.equal(cancelled.fidelityReport,undefined);
    assert.equal(cancelled.achievedTier,undefined); assert.equal(cancelled.resultLabel,'');
    assert.equal(h.timers.size,0);
  }
});
test('Mixed-quality queue preserves per-task duration and paused time exclusion',()=>{
  const h=host(); const first=task(h,'fast'); const second=task(h,'high_fidelity');
  h.step(1000); h.store.advance(h.now()); h.store.pause(first.id);
  h.step(6000); h.store.advance(h.now());
  assert.equal(h.store.snapshot().find(item=>item.id===second.id).status,'completed');
  h.store.resume(first.id); h.step(1000); h.store.advance(h.now());
  const resumed=h.store.snapshot().find(item=>item.id===first.id);
  assert.equal(resumed.status,'completed'); assert.equal(resumed.elapsedMs,2000);
});
test('Read-only protocol, generated registry, native binding and fifth page stay byte-identical',()=>{
  const baseline=JSON.parse(fs.readFileSync(path.join(root,'tests/generated/fidelity-baseline.json'),'utf8').replace(/^\uFEFF/,''));
  for (const file of baseline.readOnlyFiles) {
    const digest=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file.path))).digest('hex');
    assert.equal(digest.toUpperCase(),file.sha256,'Unexpected reference-file modification: '+file.path);
  }
});
const report={scope:'fidelity_demo_logic_not_real_document_validation',result:'passed',testedCases:cases.length,cases,
  nativeExecution:'not_executed',realFidelityMeasurement:'not_executed',previewerExecution:'not_executed',deviceExecution:'not_executed'};
fs.writeFileSync(path.join(root,'tests/generated/fidelity-check-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
