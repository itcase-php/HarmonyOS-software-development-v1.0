import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import { NativeBridgeService } from '../../../main/ets/services/NativeBridge';
import { FormatRegistryService } from '../../../main/ets/services/FormatRegistry';
import { RawfileResources } from '../../../main/ets/services/RawfileResources';
import { registryMetadata } from '../../../main/ets/generated/RegistryData';
import { PreparedInput, ConvertRequest } from '../../../main/ets/models/NativeProtocol';

export default function jpegDebugSmokeTest() {
  describe('JpegDebugSmoke', () => {
    it('converts the bundled baseline JPEG through the real Debug Native bridge', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const testContext = await application.createModuleContext(context, 'entry_test');
      const fixture = await testContext.resourceManager.getRawFileContent('jpeg-debug-baseline.jpg');
      expect(fixture.byteLength).assertEqual(634);
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
          byteSize: fixture.byteLength, sha256: 'dc9e246d39d38fb43ce0b784dc1c14baf9a3997466bb4c0a2ba65a39851417b5' };
        const probes = await native.probeInputs({ schemaVersion: 1, sessionId, workspaceRef,
          inputs: [input], resourceBudget: registryMetadata.defaultBudget });
        expect(probes.length).assertEqual(1);
        expect(probes[0].actualFormatId).assertEqual('jpeg');
        expect(probes[0].protection).assertEqual('none');
        expect(probes[0].needsDeepCheck).assertFalse();
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
          hilog.info(0x0000, 'JpegDebugSmoke', 'PDF_SHA256=%{public}s PDF_BASE64=%{public}s',
            artifact.sha256, new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes)));
        } finally { fileIo.closeSync(output); }
        await native.releaseArtifact(artifact.internalRef);
        await native.releaseTask(taskId, attemptId);
      } finally {
        try { await native.shutdown(); } finally { fileIo.rmdirSync(testRoot); }
      }
    });
  });
}
