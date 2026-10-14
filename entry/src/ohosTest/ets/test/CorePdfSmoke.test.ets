// Actual main-app engines and PDFKit; fixtures belong to this repository.
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { fileIo, hash } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import { NativeBridgeService } from '../../../main/ets/services/NativeBridge';
import { BundledConversionRuntime } from '../../../main/ets/services/BundledConversionRuntime';
import { FormatRegistryService } from '../../../main/ets/services/FormatRegistry';
import { RawfileResources } from '../../../main/ets/services/RawfileResources';
import { registryMetadata } from '../../../main/ets/generated/RegistryData';
import { PreparedInput, ConvertRequest } from '../../../main/ets/models/NativeProtocol';
import { ErrorHandler } from '../../../main/ets/common/ErrorHandler';

export default function corePdfSmokeTest() {
  describe('CorePdfSmoke', () => {
    for (const format of ['docx', 'pptx', 'png']) {
      it('converts repository ' + format + ' using real engines and PDFKit', 0, async () => {
        const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
        const context = ability.context;
        const testContext = await application.createModuleContext(context, 'entry_test');
        const fixture = await testContext.resourceManager.getRawFileContent('core-layout.' + format);
        const root = context.cacheDir;
        const workspace = util.generateRandomUUID(true).replace(/-/g, '');
        const taskId = util.generateRandomUUID(true).replace(/-/g, '');
        const attemptId = util.generateRandomUUID(true).replace(/-/g, '');
        const fileId = util.generateRandomUUID(true).replace(/-/g, '');
        const directory = root + '/workspace/' + workspace;
        await fileIo.mkdir(directory + '/inputs', true);
        const sourcePath = directory + '/inputs/' + fileId;
        const source = await fileIo.open(sourcePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        try {
          let offset = 0;
          while (offset < fixture.byteLength) {
            const count = await fileIo.write(source.fd, fixture.slice(offset).buffer);
            if (count <= 0) { throw new Error('FIXTURE_SHORT_WRITE'); }
            offset += count;
          }
        } finally { await fileIo.close(source); }
        const native = new NativeBridgeService(undefined, new BundledConversionRuntime(context));
        try {
          const registry = new FormatRegistryService();
          await registry.initialize(new RawfileResources(context.resourceManager));
          const sessionId = await native.initializeSession({ schemaVersion: 1, appSandboxRoot: root,
            configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256 });
          const capabilities = await native.getCapabilities({ schemaVersion: 1, sessionId,
            configVersion: registryMetadata.configVersion });
          const route = registry.availableRoutes(capabilities).find((item) => item.id === format + '-pdf');
          if (!route) { throw new Error('CORE_ROUTE_MISSING'); }
          const workspaceRef = await native.registerWorkspace({ sessionId, taskId, attemptId,
            relativeDirectory: 'workspace/' + workspace });
          const input: PreparedInput = { fileId, sourceFormatId: format, relativePath: 'inputs/' + fileId,
            byteSize: fixture.byteLength, sha256: (await hash.hash(sourcePath, 'sha256')).toLowerCase() };
          const office = format !== 'png';
          const allowed: string[] = office ? ['font_substitution'] : [];
          const request: ConvertRequest = { schemaVersion: 1, sessionId, taskId, attemptId, workspaceRef,
            operation: route.operation, inputs: [input], targetFormatId: 'pdf', qualityMode: 'balanced',
            intent: route.intent, options: office ? { office: { missingFontPolicy: 'approved_fallback',
              allowedDegradations: allowed, includeReferencePages: false } } : {},
            resourceBudget: registryMetadata.defaultBudget,
            plan: { routeId: route.id, steps: route.steps, fallbackRouteIds: route.fallbackRouteIds,
              configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256,
              intent: route.intent, minimumTier: route.fidelityTier, allowedDegradations: allowed,
              policyVersion: registryMetadata.securityPolicy.version } };
          hilog.info(0, 'CorePdfSmoke', 'CORE_START format=%{public}s', format);
          const result = await native.execute(request);
          if (result.error) {
            hilog.error(0, 'CorePdfSmoke', 'CORE_FAIL format=%{public}s code=%{public}s reason=%{public}s',
              format, result.error.code, result.error.reason);
          }
          expect(result.status).assertEqual('success');
          expect(result.validation.state).assertEqual('passed');
          expect(result.outputs.length).assertEqual(1);
          const artifact = result.outputs[0];
          await native.releaseTask(taskId, attemptId);
          await fileIo.rmdir(directory);
          const outputPath = context.cacheDir + '/core-device-' + format + '.pdf';
          const output = await fileIo.open(outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try { expect(await native.copyArtifactToFd(artifact.internalRef, output.fd, artifact.sha256, artifact.byteSize)).assertEqual(artifact.byteSize); }
          finally { await fileIo.close(output); }
          expect((await hash.hash(outputPath, 'sha256')).toLowerCase()).assertEqual(artifact.sha256);
          hilog.info(0, 'CorePdfSmoke', 'CORE_OK format=%{public}s bytes=%{public}d sha256=%{public}s',
            format, artifact.byteSize, artifact.sha256);
          if (abilityDelegatorRegistry.getArguments().parameters['-s captureCorePdf'] === 'true') {
            const file = await fileIo.open(outputPath, fileIo.OpenMode.READ_ONLY);
            const bytes = new ArrayBuffer(artifact.byteSize);
            try {
              let offset = 0;
              while (offset < bytes.byteLength) {
                const part = new ArrayBuffer(bytes.byteLength - offset);
                const count = await fileIo.read(file.fd, part);
                if (count <= 0) { throw new Error('FIXTURE_EXPORT_SHORT_READ'); }
                new Uint8Array(bytes).set(new Uint8Array(part, 0, count), offset); offset += count;
              }
            } finally { await fileIo.close(file); }
            const encoded = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
            const total = Math.ceil(encoded.length / 900);
            for (let part = 0; part < total; part++) {
              hilog.info(0, 'CorePdfSmoke', 'CORE_PDF format=%{public}s sha256=%{public}s part=%{public}d/%{public}d data=%{public}s',
                format, artifact.sha256, part + 1, total, encoded.substring(part * 900, (part + 1) * 900));
              await new Promise<void>((resolve) => { setTimeout(resolve, 100); });
            }
          }
          await native.releaseArtifact(artifact.internalRef);
        } catch (error) {
          const failure = ErrorHandler.catchBridge(error, 'CorePdfSmoke');
          hilog.error(0, 'CorePdfSmoke', 'CORE_EXCEPTION format=%{public}s code=%{public}s reason=%{public}s',
            format, failure.code, failure.reason);
          throw error as Error;
        } finally {
          await native.shutdown();
          if (await fileIo.access(directory)) { await fileIo.rmdir(directory); }
        }
      });
    }
  });
}
