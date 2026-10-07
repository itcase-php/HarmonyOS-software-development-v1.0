import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { fileIo, hash } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import { NativeBridgeService } from '../../../main/ets/services/NativeBridge';
import { FormatRegistryService } from '../../../main/ets/services/FormatRegistry';
import { RawfileResources } from '../../../main/ets/services/RawfileResources';
import { registryMetadata } from '../../../main/ets/generated/RegistryData';
import { PreparedInput, ConvertRequest, ProbeRequest, ErrorCode } from '../../../main/ets/models/NativeProtocol';
import { BridgeError } from '../../../main/ets/common/BridgeError';

async function expectProbeFailure(native: NativeBridgeService, request: ProbeRequest,
  code: ErrorCode, reason: string): Promise<void> {
  let rejected = false;
  try { await native.probeInputs(request); }
  catch (error) {
    const failure = error as BridgeError;
    expect(failure.code).assertEqual(code);
    expect(failure.reason).assertEqual(reason);
    rejected = true;
  }
  expect(rejected).assertTrue();
}

export default function jpegDebugSmokeTest() {
  describe('JpegDebugSmoke', () => {
    for (const fixtureName of ['jpeg-debug-baseline.jpg', 'jpeg-debug-exif-icc.jpg']) {
    it('converts ' + fixtureName + ' through the real Debug Native bridge', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const testContext = await application.createModuleContext(context, 'entry_test');
      const fixture = await testContext.resourceManager.getRawFileContent(fixtureName);
      if (fixtureName === 'jpeg-debug-baseline.jpg') { expect(fixture.byteLength).assertEqual(634); }
      const testRoot = context.cacheDir + '/jpeg-debug-smoke-' + Date.now().toString();
      const root = testRoot + '/cache';
      const workspaceId = '11111111111111111111111111111111';
      const fileId = '22222222222222222222222222222222';
      const taskId = '33333333333333333333333333333333';
      const attemptId = '44444444444444444444444444444444';
      fileIo.mkdirSync(root + '/workspace/' + workspaceId + '/inputs', true);
      const source = fileIo.openSync(root + '/workspace/' + workspaceId + '/inputs/' + fileId,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try { expect(fileIo.writeSync(source.fd, fixture.buffer)).assertEqual(fixture.byteLength); }
      finally { fileIo.closeSync(source); }
      const native = new NativeBridgeService();
      try {
        const sessionId = await native.initializeSession({ schemaVersion: 1, appSandboxRoot: root,
          configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256 });
        const capabilities = await native.getCapabilities({ schemaVersion: 1, sessionId,
          configVersion: registryMetadata.configVersion });
        const registry = new FormatRegistryService();
        await registry.initialize(new RawfileResources(context.resourceManager));
        const routes = registry.availableRoutes(capabilities);
        expect(routes.length).assertEqual(1);
        expect(routes[0].id).assertEqual('jpeg-pdf');
        const route = routes[0];
        const workspaceRef = await native.registerWorkspace({ sessionId, taskId, attemptId,
          relativeDirectory: 'workspace/' + workspaceId });
        const input: PreparedInput = { fileId, sourceFormatId: 'jpeg', relativePath: 'inputs/' + fileId,
          byteSize: fixture.byteLength,
          sha256: (await hash.hash(root + '/workspace/' + workspaceId + '/inputs/' + fileId, 'sha256')).toLowerCase() };
        const probes = await native.probeInputs({ schemaVersion: 1, sessionId, workspaceRef,
          inputs: [input], resourceBudget: registryMetadata.defaultBudget });
        expect(probes.length).assertEqual(1);
        expect(probes[0].actualFormatId).assertEqual('jpeg');
        expect(probes[0].protection).assertEqual('none');
        expect(probes[0].needsDeepCheck).assertFalse();
        const inputPath = root + '/workspace/' + workspaceId + '/inputs/' + fileId;
        const withUnknownSegment = new Uint8Array(fixture.byteLength + 10);
        withUnknownSegment.set(fixture.subarray(0, 2));
        withUnknownSegment.set(new Uint8Array([255, 227, 0, 8, 111, 112, 97, 113, 117, 101]), 2);
        withUnknownSegment.set(fixture.subarray(2), 12);
        const metadataFile = fileIo.openSync(inputPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try { expect(fileIo.writeSync(metadataFile.fd, withUnknownSegment.buffer)).assertEqual(withUnknownSegment.byteLength); }
        finally { fileIo.closeSync(metadataFile); }
        const metadataInput: PreparedInput = { fileId, sourceFormatId: 'jpeg', relativePath: input.relativePath,
          byteSize: withUnknownSegment.byteLength, sha256: (await hash.hash(inputPath, 'sha256')).toLowerCase() };
        await expectProbeFailure(native, { schemaVersion: 1, sessionId, workspaceRef,
          inputs: [metadataInput], resourceBudget: registryMetadata.defaultBudget },
          'UNSUPPORTED_FEATURE', 'NATIVE_JPEG_METADATA_UNSUPPORTED');
        const corruptFile = fileIo.openSync(inputPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try { expect(fileIo.writeSync(corruptFile.fd, new Uint8Array([1, 2, 3, 4]).buffer)).assertEqual(4); }
        finally { fileIo.closeSync(corruptFile); }
        const corruptInput: PreparedInput = { fileId, sourceFormatId: 'jpeg', relativePath: input.relativePath,
          byteSize: 4, sha256: (await hash.hash(inputPath, 'sha256')).toLowerCase() };
        await expectProbeFailure(native, { schemaVersion: 1, sessionId, workspaceRef,
          inputs: [corruptInput], resourceBudget: registryMetadata.defaultBudget },
          'FILE_CORRUPTED', 'NATIVE_JPEG_CORRUPTED');
        const restoredFile = fileIo.openSync(inputPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try { expect(fileIo.writeSync(restoredFile.fd, fixture.buffer)).assertEqual(fixture.byteLength); }
        finally { fileIo.closeSync(restoredFile); }
        const changedInput: PreparedInput = { fileId, sourceFormatId: 'jpeg', relativePath: input.relativePath,
          byteSize: fixture.byteLength, sha256: '0'.repeat(64) };
        await expectProbeFailure(native, { schemaVersion: 1, sessionId, workspaceRef,
          inputs: [changedInput], resourceBudget: registryMetadata.defaultBudget },
          'PERMISSION_DENIED', 'NATIVE_INPUT_DIGEST_MISMATCH');
        hilog.info(0x0000, 'JpegDebugSmoke', 'PROBE_DIAGNOSTICS=metadata,corruption,digest:passed');
        const request: ConvertRequest = { schemaVersion: 1, sessionId, taskId, attemptId, workspaceRef,
          operation: 'images_to_pdf', inputs: [input], targetFormatId: 'pdf', qualityMode: 'balanced',
          intent: route.intent, options: {}, resourceBudget: registryMetadata.defaultBudget,
          plan: { routeId: route.id, steps: route.steps, fallbackRouteIds: route.fallbackRouteIds,
            configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256,
            intent: route.intent, minimumTier: route.fidelityTier, allowedDegradations: [],
            policyVersion: registryMetadata.securityPolicy.version } };
        const result = await native.execute(request);
        if (result.error) {
          hilog.error(0x0000, 'JpegDebugSmoke', 'CONVERSION_ERROR=%{public}s REASON=%{public}s',
            result.error.code, result.error.reason);
        }
        expect(result.status).assertEqual('success');
        expect(result.validation.state).assertEqual('passed');
        expect(result.outputs.length).assertEqual(1);
        const artifact = result.outputs[0];
        const output = fileIo.openSync(root + '/baseline-output.pdf',
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
        try {
          const copied = await native.copyArtifactToFd(artifact.internalRef, output.fd,
            artifact.sha256, artifact.byteSize);
          expect(copied).assertEqual(artifact.byteSize);
          const bytes = new ArrayBuffer(artifact.byteSize);
          expect(fileIo.readSync(output.fd, bytes, { offset: 0, length: artifact.byteSize }))
            .assertEqual(artifact.byteSize);
          // Only the tiny, repository-owned synthetic fixture is logged, never a user document.
          const encoded = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
          if (fixtureName === 'jpeg-debug-baseline.jpg') {
            hilog.info(0x0000, 'JpegDebugSmoke', 'PDF_SHA256=%{public}s PDF_BASE64=%{public}s', artifact.sha256, encoded);
          } else {
            const total = Math.ceil(encoded.length / 1200);
            for (let part = 0; part < total; part++) {
              hilog.info(0x0000, 'JpegDebugSmoke', 'METADATA_PDF_SHA256=%{public}s PART=%{public}d/%{public}d BASE64=%{public}s',
                artifact.sha256, part + 1, total, encoded.substring(part * 1200, (part + 1) * 1200));
            }
          }
        } finally { fileIo.closeSync(output); }
        await native.releaseArtifact(artifact.internalRef);
        await native.releaseTask(taskId, attemptId);
      } finally {
        try { await native.shutdown(); } finally { fileIo.rmdirSync(testRoot); }
      }
    });
    }
  });
}
