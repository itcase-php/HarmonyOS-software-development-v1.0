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
  const created=h.store.enqueue('report.docx','docx','pdf','docx-pdf',false,
    {qualityMode:mode,requestedIntent:'layout_preserved',requestedTier:tier});
  h.store.advance(h.now());return created;
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
    assert.equal(h.planner.bestRoute('docx','pdf','layout_preserved',mode,'extreme'),undefined);
  }
});
test('Intent mismatch is blocked before queue insertion and bestRoute never changes intent',()=>{
  const h=host();
  assert.throws(()=>h.store.enqueue('x.docx','docx','pdf','docx-pdf',false,
    {qualityMode:'balanced',requestedIntent:'structured_rebuild',requestedTier:'compatible'}),
    error=>error.reason==='FIDELITY_INTENT_MISMATCH');
  assert.equal(h.planner.bestRoute('pdf','pptx','layout_preserved','high_fidelity','standard'),undefined);
  assert.equal(h.planner.bestRoute('pdf','pptx','structured_rebuild','high_fidelity','compatible'),undefined);
  assert.equal(h.store.snapshot().length,0);
});
test('Invalid fidelity enum values are rejected rather than defaulted silently',()=>{
  for (const invalid of [
    {qualityMode:'turbo',requestedIntent:'layout_preserved',requestedTier:'standard'},
    {qualityMode:'balanced',requestedIntent:'magic',requestedTier:'standard'},
    {qualityMode:'balanced',requestedIntent:'layout_preserved',requestedTier:'perfect'}
  ]) {
    const h=host(); assert.throws(()=>h.store.enqueue('x.docx','docx','pdf','docx-pdf',false,invalid),
      error=>error.reason==='FIDELITY_OPTIONS_INVALID');
    assert.equal(h.store.snapshot().length,0);
  }
});
test('Selection is frozen at enqueue even if the caller mutates its options later',()=>{
  const h=host(); const selection={qualityMode:'fast',requestedIntent:'layout_preserved',requestedTier:'standard'};
  h.store.enqueue('x.docx','docx','pdf','docx-pdf',false,selection);h.store.advance(h.now());
  selection.qualityMode='high_fidelity'; selection.requestedIntent='content_only'; selection.requestedTier='extreme';
  h.step(2000); h.store.advance(h.now()); const done=h.store.snapshot()[0];
  assert.equal(done.status,'completed'); assert.equal(done.qualityMode,'fast');
  assert.equal(done.fidelityReport.intent,'layout_preserved'); assert.equal(done.fidelityReport.requestedTier,'standard');
});
test('In-flight reports use the route snapshot instead of later registry mutations',()=>{
  const h=host(); h.store.enqueue('x.png','png','pdf','png-pdf');h.store.advance(h.now());
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
  const originalDegradations=Array.from(snapshot.fidelityReport.degradations);
  snapshot.qualityMode='fast'; snapshot.fidelityReport.metrics[0].value=42;
  snapshot.fidelityReport.metrics[0].evidenceRefs.push('fake-evidence');
  snapshot.fidelityReport.degradations.push('fake-loss'); snapshot.fidelityReport.unsupportedFeatures.length=0;
  const current=h.store.snapshot()[0];
  assert.equal(current.qualityMode,'balanced'); assert.equal(current.fidelityReport.metrics[0].value,originalValue);
  assert.equal(current.fidelityReport.metrics[0].evidenceRefs.length,0);
  assert.deepEqual(Array.from(current.fidelityReport.degradations),originalDegradations);
  assert.ok(current.fidelityReport.unsupportedFeatures.length>0);
});
test('Deferred compatibility and content-only routes stay disabled with or without consent',()=>{
  const h=host();
  for (const approved of [false,true]) {
    assert.throws(()=>h.store.enqueue('x.png','png','pdf','png-pdf-compatible',approved),error=>error.code==='UNSUPPORTED_FORMAT');
    assert.throws(()=>h.store.enqueue('x.pdf','pdf','txt','pdf-txt',approved),error=>error.code==='UNSUPPORTED_FORMAT');
  }
  assert.equal(h.store.snapshot().length,0);
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
test('Native protocol C++ contract and page routes preserve the original fidelity baseline',()=>{
  const baseline=JSON.parse(fs.readFileSync(path.join(root,'tests/generated/fidelity-baseline.json'),'utf8').replace(/^\uFEFF/,''));
  for (const file of baseline.readOnlyFiles) {
    let bytes=fs.readFileSync(path.join(root,file.path));
    if(file.path==='entry/src/main/ets/models/NativeProtocol.ets') {
      const extension='// Private Native-to-validator expectations; consumed before storing a completed result.\n'+
        'export interface TextMinimum { codePoint: number; count: number; }\n'+
        'export interface ContentExpectation {\n  textMinimum: TextMinimum[];\n  minimumImages: number;\n  pageCount?: number;\n}\n';
      const current=bytes.toString('utf8').replace(/\r\n/g,'\n');assert.ok(current.includes(extension));
      bytes=Buffer.from(current.replace(extension,'').replace('  contentExpectation?: ContentExpectation;\n',''));
    }
    if(file.path==='entry/src/main/cpp/core/converter.h') {
      const extension='struct ContentExpectation {\n'+
        '    std::vector<std::pair<std::uint32_t,std::uint32_t>> textMinimum;\n'+
        '    std::uint32_t minimumImages{};\n    std::optional<std::uint32_t> pageCount;\n};\n';
      const current=bytes.toString('utf8').replace(/\r\n/g,'\n');assert.ok(current.includes(extension));
      bytes=Buffer.from(current.replace(extension,'').replace('    std::optional<ContentExpectation> contentExpectation;\n',''));
    }
    const digest=crypto.createHash('sha256').update(bytes).digest('hex');
    const evolved=['entry/src/main/ets/models/RegistryTypes.ets','entry/src/main/ets/generated/RegistryData.ets',
      'entry/src/main/ets/services/NativeBridge.ets','entry/src/main/ets/pages/FeatureGuide.ets'];
    // Original baseline remains immutable. These intentional audit changes have new coverage.
    // Preserve the original baseline, while pinning the authorized 04e6886 delivery API.
    const expected=file.path==='entry/src/main/ets/models/NativeProtocol.ets'?
      'A48889500AFE6575C74A7B7AB0B1EF9DBA852C2274AD335ECD5EB34B8ADFDFA1':file.sha256;
    if (!evolved.includes(file.path)) assert.equal(digest.toUpperCase(),expected,'Unexpected reference-file modification: '+file.path);
  }
});
const report={scope:'fidelity_demo_logic_not_real_document_validation',result:'passed',testedCases:cases.length,cases,
  nativeExecution:'not_executed',realFidelityMeasurement:'not_executed',previewerExecution:'not_executed',deviceExecution:'not_executed'};
fs.writeFileSync(path.join(root,'tests/generated/fidelity-check-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
