'use strict';
// Execute actual ArkTS registry/preflight/dispatcher logic with host-only SDK/Native models.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { host } = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p));
const matrix = JSON.parse(read('shared/format-registry/conversion-matrix.json'));
const cases = [];
async function test(name, body) { await body(); cases.push(name); }
function fixture(debug) {
  const h = host({ debugBuild: debug });
  const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
  const route = registry.listPlannedRoutes().find(r => r.id === 'jpeg-pdf');
  const stamp = { engineId: 'image', version: 'test-model', buildHash: 'a'.repeat(64) };
  const caps = { schemaVersion: 1, offlineOnly: true, abi: 'arm64-v8a',
    configVersion: h.load('./generated/RegistryData').registryMetadata.configVersion,
    engines: [stamp], routes: [{ routeId: route.id, availability: 'experimental' }] };
  return { h, registry, route, caps };
}
async function main() {
  await test('Only JPEG is experimental; generated configuration bytes and digests agree', () => {
    assert.equal(matrix.routes.find(r => r.id === 'jpeg-pdf').status, 'experimental');
    assert.ok(matrix.routes.every(r => r.id === 'jpeg-pdf' || r.status === 'planned'));
    const f = fixture(true);
    const generated = f.h.load('./generated/RegistryData');
    assert.equal(f.route.status, 'experimental');
    assert.deepEqual(read('shared/format-registry/conversion-matrix.json'),
      read('entry/src/main/resources/rawfile/format-registry/conversion-matrix.json'));
    assert.equal(crypto.createHash('sha256').update(read('shared/format-registry/conversion-matrix.json')).digest('hex'),
      generated.registryMetadata.matrixSha256);
  });
  await test('Debug requires both route states, the whitelist and a real-shaped engine stamp; Release blocks it', () => {
    const f = fixture(true);
    assert.equal(f.registry.availableRoutes(f.caps).length, 1);
    assert.equal(fixture(false).registry.availableRoutes(f.caps).length, 0);
    f.caps.routes[0].availability = 'planned'; assert.equal(f.registry.availableRoutes(f.caps).length, 0);
    f.caps.routes[0].availability = 'experimental';
    f.caps.engines[0].buildHash = '0'.repeat(64); assert.equal(f.registry.availableRoutes(f.caps).length, 0);
    f.caps.engines[0].buildHash = 'a'.repeat(64); f.caps.engines = [];
    assert.equal(f.registry.availableRoutes(f.caps).length, 0);
    const planned = f.registry.routes.find(r => r.id === 'docx-pdf'); planned.status = 'experimental';
    f.caps.routes = [{ routeId: planned.id, availability: 'experimental' }];
    f.caps.engines = [{ engineId: 'office', version: 'test-model', buildHash: 'a'.repeat(64) }];
    assert.equal(f.registry.availableRoutes(f.caps).length, 0);
  });
  await test('Release available still requires release evidence', () => {
    const f = fixture(false); f.registry.routes.find(r => r.id === 'jpeg-pdf').status = 'available';
    f.caps.routes[0].availability = 'available'; assert.equal(f.registry.availableRoutes(f.caps).length, 0);
    f.caps.routes[0].releaseEvidenceId = 'host-test-only';
    assert.equal(f.registry.availableRoutes(f.caps).length, 1);
  });
  await test('Preflight and runner share Debug qualification; input probing remains mandatory', async () => {
    const f = fixture(true), meta = f.h.load('./generated/RegistryData').registryMetadata;
    let executions = 0, probes = 0, releases = 0;
    const native = { getCapabilities: async () => f.caps,
      probeInputs: async request => { probes++; return request.inputs.map(input => ({ fileId: input.fileId,
        actualFormatId: 'jpeg', protection: 'none', needsDeepCheck: false })); },
      subscribeProgress: async () => 'host-token', unsubscribeProgress: async () => {},
      execute: async request => { executions++; return { taskId: request.taskId, status: 'success' }; },
      releaseTask: async () => { releases++; } };
    const Preflight = f.h.load('./services/RealTaskPreflight').RealTaskPreflight;
    await new Preflight(f.registry, native).inspect('jpeg-pdf', 'jpeg', 'pdf');
    const request = { schemaVersion: 1, sessionId: 'host-session', taskId: 'host-task', attemptId: 'host-attempt',
      workspaceRef: 'host-ref', operation: f.route.operation, inputs: [{ fileId: 'input', sourceFormatId: 'jpeg' }],
      targetFormatId: 'pdf', qualityMode: 'balanced', intent: f.route.intent, options: {}, resourceBudget: {},
      plan: { routeId: f.route.id, steps: f.route.steps, intent: f.route.intent, minimumTier: 'extreme',
        configVersion: meta.configVersion, configSha256: meta.matrixSha256,
        policyVersion: meta.securityPolicy.version, allowedDegradations: [], fallbackRouteIds: [] } };
    const Runner = f.h.load('./services/NativeTaskRunner').NativeTaskRunnerService;
    const runner = new Runner(f.registry, native);
    await runner.run(runner.prepare(request, true), () => {}, () => true);
    assert.equal(executions, 1); assert.equal(probes, 1); assert.equal(releases, 1);
    native.probeInputs = async () => [{ fileId: 'input', actualFormatId: 'jpeg', protection: 'unknown', needsDeepCheck: true }];
    await assert.rejects(runner.run(request, () => {}, () => true), e => e.reason === 'NATIVE_INPUT_NOT_VERIFIED');
    assert.equal(executions, 1);
    assert.equal(releases, 2);
    const BridgeError = f.h.load('./common/BridgeError').BridgeError;
    native.probeInputs = async () => { throw new BridgeError('UNSUPPORTED_FEATURE', 'NATIVE_JPEG_METADATA_UNSUPPORTED'); };
    await assert.rejects(runner.run(request, () => {}, () => true),
      e => e.code === 'UNSUPPORTED_FEATURE' && e.reason === 'NATIVE_JPEG_METADATA_UNSUPPORTED');
    assert.equal(executions, 1);
    assert.equal(releases, 3);
  });
  await test('JPEG probe errors reach distinct translated UI messages without claiming protection', () => {
    const f = fixture(true);
    const Status = f.h.load('./viewmodel/ConversionStatusVM').ConversionStatusVM;
    const status = new Status();
    const language = f.h.load('./common/LanguageManager').LanguageManager;
    for (const lang of ['zh', 'en']) {
      language.setLanguage(lang);
      const reasons = ['METADATA_UNSUPPORTED', 'ENCODING_UNSUPPORTED', 'COLOR_UNSUPPORTED',
        'DENSITY_UNSUPPORTED', 'HEADER_UNSUPPORTED', 'PIXEL_LIMIT', 'MEMORY_LIMIT', 'CORRUPTED'];
      const messages = reasons.map(reason => status.inputFailure('NATIVE_JPEG_' + reason));
      assert.equal(new Set(messages).size, reasons.length);
      for (const message of messages) {
        assert.ok(message.length > 12 && !message.startsWith('input_'));
        assert.notEqual(message, status.inputFailure('NATIVE_INPUT_NOT_VERIFIED'));
      }
      assert.match(messages[0], /EXIF/);
      assert.equal(status.inputFailure('NATIVE_INPUT_DIGEST_MISMATCH'), status.inputFailure('FILE_COPY_FAILED'));
      assert.equal(status.inputFailure('NATIVE_INPUT_SIZE_MISMATCH'), status.inputFailure('FILE_COPY_FAILED'));
    }
  });
  fs.writeFileSync(path.join(root, 'tests/generated/debug-routes-host-report.json'),
    JSON.stringify({ scope: 'host_logic_with_mock_native_not_device_conversion', passed: cases.length, cases,
      device: 'not_executed', previewer: 'not_executed' }, null, 2) + '\n');
  console.log(JSON.stringify({ passed: cases.length, device: 'not_executed' }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
