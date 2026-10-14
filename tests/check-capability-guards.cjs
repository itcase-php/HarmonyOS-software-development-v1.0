'use strict';
// Audit reproducer: real ArkTS services, modeled Native replies, no engine/device.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { host } = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
async function flush() { for (let index = 0; index < 80; index++) await Promise.resolve(); }
async function observe(name, change) {
  const h = host({ debugBuild: true });
  const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
  const meta = h.load('./generated/RegistryData').registryMetadata;
  const route = registry.listPlannedRoutes().find(item => item.id === 'jpeg-pdf');
  const request = { schemaVersion: 1, taskId: 'audit-task', attemptId: 'audit-attempt', sessionId: 'audit-session',
    workspaceRef: 'audit-workspace', operation: route.operation,
    inputs: [{ fileId: 'audit-file', sourceFormatId: 'jpeg', relativePath: 'source.jpg', byteSize: 1000, sha256: 'a'.repeat(64) }],
    targetFormatId: 'pdf', qualityMode: 'balanced', intent: route.intent, options: {}, resourceBudget: meta.defaultBudget,
    plan: { routeId: route.id, steps: route.steps, fallbackRouteIds: [], configVersion: meta.configVersion,
      configSha256: meta.matrixSha256, intent: route.intent, minimumTier: 'extreme', allowedDegradations: [],
      policyVersion: meta.securityPolicy.version } };
  const result = { schemaVersion: 1, taskId: request.taskId, attemptId: request.attemptId, status: 'success', warnings: [],
    outputs: [{ artifactId: 'audit-artifact', role: 'primary', formatId: 'pdf', internalRef: 'artifact:'+'a'.repeat(32),
      byteSize: 1000, sha256: 'b'.repeat(64) }],
    validation: { state: 'passed', validatorVersion: 'audit-model', evidenceRefs: ['audit-model-evidence'] },
    engines: [], elapsedMs: 1, nativePeakBytes: 1000, tempPeakBytes: 1000 };
  change(result);
  const stamp = { engineId: 'image', version: 'audit-model', buildHash: 'c'.repeat(64) };
  h.setNative({ getCapabilities: async () => ({ schemaVersion: 1, offlineOnly: true, abi: 'arm64-v8a',
    configVersion: meta.configVersion, engines: [stamp], routes: [{ routeId: route.id, availability: 'experimental' }] }),
    probeInputs: async () => [{ fileId: 'audit-file', actualFormatId: 'jpeg', protection: 'none', needsDeepCheck: false }],
    subscribeProgress: async () => 'audit-token', unsubscribeProgress: async () => true,
    execute: async () => result, releaseTask: async () => {}, releaseArtifact: async () => {} });
  h.store.enqueueNative('source.jpg', request);
  h.store.advance(h.now());
  await flush();
  const task = h.store.snapshot()[0];
  const observation = { name, displayedStatus: task.status, resultLabel: task.resultLabel,
    deliveryButtonsEligible: h.store.hasDeliverable(task.id), achievedTier: task.achievedTier || null, error: task.error };
  if (name === 'zero-byte primary PDF' || name === 'invalid output SHA-256' || name === 'missing opaque output reference') {
    const artifact = result.outputs[0];
    try {
      await h.load('./services/NativeBridge').NativeBridge.copyArtifactToFd(
        artifact.internalRef, 1, artifact.sha256, artifact.byteSize);
      observation.exportArgumentCheck = 'accepted';
    } catch (error) { observation.exportArgumentCheck = error.code + ':' + error.reason; }
  }
  await h.store.shutdown();
  await flush();
  return observation;
}
(async () => {
  const observations = [];
  for (const [name, change] of [
    ['valid modeled result (control)', () => {}],
    ['zero-byte primary PDF', result => { result.outputs[0].byteSize = 0; }],
    ['wrong primary format (DOCX for PDF request)', result => { result.outputs[0].formatId = 'docx'; }],
    ['only report output, no primary result', result => { result.outputs[0].role = 'report'; }],
    ['multiple outputs for a single-output route', result => { result.outputs.push({ ...result.outputs[0] }); }],
    ['invalid output SHA-256', result => { result.outputs[0].sha256 = 'invalid'; }],
    ['missing opaque output reference', result => { result.outputs[0].internalRef = ''; }],
    ['achieved extreme tier without any metrics or evidence', result => { result.fidelity = {
      schemaVersion: 1, intent: 'layout_preserved', requestedTier: 'extreme', achievedTier: 'extreme', metrics: [],
      fontSubstitutions: [], unsupportedFeatures: [], degradations: [], requiresManualReview: false,
      detectorVersion: 'audit-model', evidenceRefs: [] }; }],
    ['failed output validation (negative control)', result => { result.validation.state = 'failed'; }]
  ]) observations.push(await observe(name, change));
  assert.equal(observations[0].displayedStatus, 'completed');
  for (const observation of observations.slice(1)) assert.equal(observation.displayedStatus,'failed',observation.name);
  const report = { scope: 'regression for success/fidelity guards, actual services with modeled Native replies',
    realEngineExecution: 'not run', deviceExecution: 'not run', productionCodeModified: true, observations };
  fs.writeFileSync(path.join(root, 'tests/generated/capability-guards-regression.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
