// Actual main-app engines and PDFKit; fixtures belong to this repository.
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { fileIo, hash, picker } from '@kit.CoreFileKit';
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
import { window } from '@kit.ArkUI';
import { artifactDeliverySmoke } from './ArtifactDeliverySmoke';
import { pdfService } from '@kit.PDFKit';
import { coreTestContext } from './CoreTestContext';

interface CoreFixture { name: string; label: string; approved: boolean; blocked: string; }

async function captureFixturePdf(path: string, byteSize: number, sha256: string, label: string): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
  const bytes = new ArrayBuffer(byteSize);
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
      label, sha256, part + 1, total, encoded.substring(part * 900, (part + 1) * 900));
    await new Promise<void>((resolve) => { setTimeout(resolve, 100); });
  }
}


export default function corePdfSmokeTest() {
  describe('CorePdfSmoke', () => {
    const fixtures: CoreFixture[] = [
      { name: 'core-layout.docx', label: 'docx', approved: true, blocked: '' },
      { name: 'core-layout.pptx', label: 'pptx', approved: false, blocked: '' },
      { name: 'core-layout.png', label: 'png', approved: false, blocked: '' },
      { name: 'core-cjk.docx', label: 'docx-cjk', approved: true, blocked: '' },
      { name: 'core-cjk.pptx', label: 'pptx-cjk', approved: true, blocked: '' },
      { name: 'core-default-font.docx', label: 'docx-default', approved: false, blocked: '' },
      { name: 'core-missing-font.docx', label: 'docx-font-reject', approved: false, blocked: 'OFFICE_REQUIRED_FONT_MISSING' },
      { name: 'core-missing-font.docx', label: 'docx-font-approved', approved: true, blocked: '' },
      { name: 'core-missing-symbol.docx', label: 'docx-missing-symbol', approved: false, blocked: 'OFFICE_SYMBOL_FONT_MISSING' },
      { name: 'core-missing-symbol.docx', label: 'docx-missing-symbol-approved', approved: true, blocked: 'OFFICE_SYMBOL_FONT_MISSING' }
    ];
    for (const testCase of fixtures) {
      const fixtureName = testCase.name;
      const format = fixtureName.substring(fixtureName.lastIndexOf('.') + 1);
      const label = testCase.label;
      const selected = abilityDelegatorRegistry.getArguments().parameters['-s fixtureLabel'];
      if (selected && selected !== label) { continue; }
      it('checks repository ' + label + ' using real engines and PDFKit', 0, async () => {
        const context = await coreTestContext();
        const parameters = abilityDelegatorRegistry.getArguments().parameters;
        const needsUi = label === 'docx' && (parameters['-s publishFixture'] === 'true' || parameters['-s deliveryUi'] === 'true');
        const ability = needsUi ? await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility() : undefined;
        const appWindow = ability ? await window.getLastWindow(ability.context) : undefined;
        if (appWindow) { await appWindow.setWindowKeepScreenOn(true); }
        hilog.info(0, 'CorePdfSmoke', 'CORE_CONTEXT format=%{public}s mode=entry-module ui=%{public}s', label, needsUi.toString());
        const testContext = await application.createModuleContext(context, 'entry_test');
        const fixture = await testContext.resourceManager.getRawFileContent(fixtureName);
        if (label === 'docx' && abilityDelegatorRegistry.getArguments().parameters['-s publishFixture'] === 'true') {
          const options = new picker.DocumentSaveOptions();
          const name = 'hdm-office-source-' + Date.now().toString() + '.docx';
          options.newFileNames = [name];
          hilog.info(0, 'CorePdfSmoke', 'FIXTURE_SOURCE_SAVE_START name=%{public}s', name);
          if (!ability) { throw new Error('CORE_UI_CONTEXT_REQUIRED'); }
          const uris = await new picker.DocumentViewPicker(ability.context).save(options);
          expect(uris.length).assertEqual(1);
          const destination = await fileIo.open(uris[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try {
            let offset = 0;
            while (offset < fixture.byteLength) {
              const count = await fileIo.write(destination.fd, fixture.slice(offset).buffer);
              if (count <= 0) { throw new Error('FIXTURE_PUBLISH_SHORT_WRITE'); }
              offset += count;
            }
          } finally { await fileIo.close(destination); }
          hilog.info(0, 'CorePdfSmoke', 'FIXTURE_SOURCE_SAVED name=%{public}s', name);
        }
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
          const allowed: string[] = office && testCase.approved ? ['font_substitution'] : [];
          const request: ConvertRequest = { schemaVersion: 1, sessionId, taskId, attemptId, workspaceRef,
            operation: route.operation, inputs: [input], targetFormatId: 'pdf', qualityMode: 'balanced',
            intent: route.intent, options: office ? { office: { missingFontPolicy: testCase.approved ? 'approved_fallback' : 'reject',
              allowedDegradations: allowed, includeReferencePages: false } } : {},
            resourceBudget: registryMetadata.defaultBudget,
            plan: { routeId: route.id, steps: route.steps, fallbackRouteIds: route.fallbackRouteIds,
              configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256,
              intent: route.intent, minimumTier: route.fidelityTier, allowedDegradations: allowed,
              policyVersion: registryMetadata.securityPolicy.version } };
          hilog.info(0, 'CorePdfSmoke', 'CORE_START format=%{public}s', label);
          const result = await native.execute(request);
          if (testCase.blocked.length > 0) {
            expect(result.status).assertEqual('failed');
            expect(result.error?.code).assertEqual('FONT_MISSING');
            expect(result.error?.reason).assertEqual(testCase.blocked);
            expect((result.fontDiagnostics?.length ?? 0) > 0).assertTrue();
            if (label === 'docx-font-reject') {
              expect(result.fontDiagnostics?.some((item) => item.family === 'HDM Missing Normal Font' && item.part === 'word/document.xml')).assertTrue();
            }
            expect(result.outputs.length).assertEqual(0);
            hilog.info(0, 'CorePdfSmoke', 'CORE_BLOCKED format=%{public}s reason=%{public}s', label, result.error?.reason ?? '');
            return;
          }
          if (result.error) {
            hilog.error(0, 'CorePdfSmoke', 'CORE_FAIL format=%{public}s code=%{public}s reason=%{public}s',
              label, result.error.code, result.error.reason);
          }
          expect(result.status).assertEqual('success');
          if (label === 'docx-default' || label === 'pptx') { expect(result.fontDiagnostics?.length ?? 0).assertEqual(0); }
          if (label === 'docx-font-approved') {
            expect(result.fidelity?.degradations.includes('font_substitution')).assertTrue();
            expect(result.fontDiagnostics?.some((item) => item.family === 'HDM Missing Normal Font')).assertTrue();
          }
          expect(result.validation.state).assertEqual('passed');
          expect(result.outputs.length).assertEqual(1);
          const artifact = result.outputs[0];
          await native.releaseTask(taskId, attemptId);
          await fileIo.rmdir(directory);
          const outputPath = context.cacheDir + '/core-device-' + label + '.pdf';
          const output = await fileIo.open(outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
          try { expect(await native.copyArtifactToFd(artifact.internalRef, output.fd, artifact.sha256, artifact.byteSize)).assertEqual(artifact.byteSize); }
          finally { await fileIo.close(output); }
          expect((await hash.hash(outputPath, 'sha256')).toLowerCase()).assertEqual(artifact.sha256);
          hilog.info(0, 'CorePdfSmoke', 'CORE_OK format=%{public}s bytes=%{public}d sha256=%{public}s',
            label, artifact.byteSize, artifact.sha256);
          if (abilityDelegatorRegistry.getArguments().parameters['-s captureCorePdf'] === 'true') {
            await captureFixturePdf(outputPath, artifact.byteSize, artifact.sha256, label);
          }
          if (label === 'docx' && abilityDelegatorRegistry.getArguments().parameters['-s deliveryUi'] === 'true') {
            if (!ability) { throw new Error('CORE_UI_CONTEXT_REQUIRED'); }
            await artifactDeliverySmoke(native, artifact, ability.context);
          }
          await native.releaseArtifact(artifact.internalRef);
        } catch (error) {
          const failure = ErrorHandler.catchBridge(error, 'CorePdfSmoke');
          hilog.error(0, 'CorePdfSmoke', 'CORE_EXCEPTION format=%{public}s code=%{public}s reason=%{public}s',
            label, failure.code, failure.reason);
          throw error as Error;
        } finally {
          try { await native.shutdown(); }
          finally {
            try { if (await fileIo.access(directory)) { await fileIo.rmdir(directory); } }
            finally { if (appWindow) { await appWindow.setWindowKeepScreenOn(false); } }
          }
        }
      });
    }
  });
  describe('SavedPdfReadback', () => {
    it('reopens the repository fixture saved by the main application', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1; options.fileSuffixFilters = ['.pdf'];
      hilog.info(0, 'CorePdfSmoke', 'SAVED_PDF_SELECT_START');
      const uris = await new picker.DocumentViewPicker(ability.context).select(options);
      expect(uris.length).assertEqual(1);
      const source = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
      const path = ability.context.cacheDir + '/saved-fixture-readback.pdf';
      const target = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      let total = 0;
      try {
        const buffer = new ArrayBuffer(65536);
        while (true) {
          const count = await fileIo.read(source.fd, buffer);
          if (count === 0) { break; }
          total += count; expect(total <= 1024 * 1024).assertTrue();
          let written = 0;
          while (written < count) {
            const amount = await fileIo.write(target.fd, buffer.slice(written, count));
            if (amount <= 0) { throw new Error('SAVED_FIXTURE_SHORT_WRITE'); }
            written += amount;
          }
        }
        expect(total).assertEqual((await fileIo.stat(source.fd)).size);
      } finally { await fileIo.close(source); await fileIo.close(target); }
      const document = new pdfService.PdfDocument();
      try {
        expect(document.loadDocument(path)).assertEqual(pdfService.ParseResult.PARSE_SUCCESS);
        expect(document.getPageCount()).assertEqual(2);
        let text = '';
        for (let index = 0; index < document.getPageCount(); index++) {
          const page = document.getPage(index);
          try { text += page.getTextContent(); } finally { page.release(); }
        }
        for (const expected of ['Harmony Office Conversion', '678.90', 'Second Page', '98765']) {
          expect(text.includes(expected)).assertTrue();
        }
        const digest = (await hash.hash(path, 'sha256')).toLowerCase();
        hilog.info(0, 'CorePdfSmoke', 'SAVED_PDF_READBACK_OK bytes=%{public}d sha256=%{public}s', total, digest);
        if (abilityDelegatorRegistry.getArguments().parameters['-s captureCorePdf'] === 'true') {
          await captureFixturePdf(path, total, digest, 'saved-docx');
        }
      } finally { document.releaseDocument(); await fileIo.unlink(path); }
    });
  });
}
