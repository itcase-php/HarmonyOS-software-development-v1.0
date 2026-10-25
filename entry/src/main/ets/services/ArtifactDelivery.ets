import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Artifact } from '../models/NativeProtocol';
import { DemoTask } from '../models/InteractionModels';
import { TaskStore } from '../viewmodel/TaskStore';
import { NativeBridgePort } from './ServiceContracts';
import { BridgeError } from '../common/BridgeError';
import { ConversionDiagnostics } from '../common/ConversionDiagnostics';

interface DeliveryFailure { code?: number; }

// internalRef is an opaque Native key. Only Native opens and validates its committed output.
export class ArtifactDelivery {
  private store: TaskStore;
  private native: NativeBridgePort;
  constructor(store: TaskStore, native: NativeBridgePort) { this.store = store; this.native = native; }

  private failure(stage: string, error: Error): void {
    const sdk: DeliveryFailure = error as DeliveryFailure;
    if (error instanceof BridgeError) {
      ConversionDiagnostics.failure('ArtifactDelivery', stage, '', error);
    } else {
      ConversionDiagnostics.stage('ArtifactDelivery', stage, '',
        Number.isSafeInteger(sdk.code) ? `SDK_${sdk.code}` : 'SDK_UNKNOWN');
    }
  }

  private fileName(taskId: string): string {
    const task: DemoTask | undefined = this.store.snapshot().find((item: DemoTask) => item.id === taskId);
    const base: string = (task?.fileName ?? 'converted').replace(/\.[^.]+$/, '')
      .replace(/[\\/:*?"<>|\u0000-\u001f\u007f]/g, '_').trim();
    const name = Array.from(base).slice(0, 80).join('');
    return `${name.length > 0 ? name : 'converted'}.pdf`;
  }

  private async write(output: Artifact, uri: string, mode: number): Promise<void> {
    let target: fileIo.File | null = null;
    let stage: string = 'open';
    try {
      target = await fileIo.open(uri, mode);
      stage = 'copy';
      const copied: number = await this.native.copyArtifactToFd(output.internalRef, target.fd,
        output.sha256, output.byteSize);
      if (copied !== output.byteSize) {
        throw new BridgeError('IO_ERROR', 'PDF_EXPORT_SIZE_MISMATCH');
      }
      // Some providers finalize data on close. Verify the selected URI afterwards,
      // through its descriptor rather than treating a provider URI as a sandbox path.
      stage = 'close';
      const written = target; target = null; await fileIo.close(written);
      stage = 'readback';
      target = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const digest = cryptoFramework.createMd('SHA256');
      const buffer = new ArrayBuffer(64 * 1024);
      let read: number = 0;
      while (true) {
        const count = await fileIo.read(target.fd, buffer);
        if (count === 0) { break; }
        if (count < 0 || read + count > output.byteSize) {
          throw new BridgeError('IO_ERROR', 'PDF_EXPORT_SIZE_MISMATCH');
        }
        await digest.update({ data: new Uint8Array(buffer.slice(0, count)) });
        read += count;
      }
      const hash = await digest.digest();
      let actual: string = '';
      for (const byte of hash.data) { actual += byte.toString(16).padStart(2, '0'); }
      if (read !== output.byteSize || actual !== output.sha256) {
        throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'PDF_EXPORT_READBACK_MISMATCH');
      }
    } catch (error) { this.failure(stage, error); throw error as Error; }
    finally {
      if (target) { await fileIo.close(target); }
    }
  }

  async save(taskId: string, context: common.UIAbilityContext): Promise<boolean> {
    const output: Artifact = this.store.beginExport(taskId);
    let state: 'exported' | 'failed' | 'cancelled' = 'failed';
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [this.fileName(taskId)];
      const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) { state = 'cancelled'; return false; }
      if (uris.length !== 1) { throw new BridgeError('INVALID_REQUEST', 'PDF_SAVE_SELECTION'); }
      await this.write(output, uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      state = 'exported';
      return true;
    } catch (error) { this.failure('save', error); throw error as Error; }
    finally { this.store.finishExport(taskId, output.artifactId, state); }
  }

  async share(taskId: string, context: common.UIAbilityContext): Promise<void> {
    const output: Artifact = this.store.beginShare(taskId);
    let shown: boolean = false;
    try {
      // ShareKit accepts an app file URI. The copy stays in system-managed cache while the
      // receiving app reads it; deleting it as soon as the panel opens would break sharing.
      const directory: string = `${context.cacheDir}/shared-pdf`;
      if (!await fileIo.access(directory)) { await fileIo.mkdir(directory, true); }
      if (!/^artifact:[a-f0-9]{32}$/.test(output.internalRef)) {
        throw new BridgeError('INVALID_REQUEST', 'PDF_SHARE_REFERENCE');
      }
      const path: string = `${directory}/${output.internalRef.slice('artifact:'.length)}.pdf`;
      await this.write(output, path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'com.adobe.pdf', uri: fileUri.getUriFromPath(path), title: this.fileName(taskId), label: 'FILE'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      // beginShare refreshes the task row and removes its action buttons while busy.
      // Use the system default position instead of anchoring to a removed component.
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL });
      shown = true;
    } catch (error) { this.failure('share', error); throw error as Error; }
    finally { this.store.finishShare(taskId, shown); }
  }
}
