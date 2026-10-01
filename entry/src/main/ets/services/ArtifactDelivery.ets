import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { Artifact } from '../models/NativeProtocol';
import { DemoTask } from '../models/InteractionModels';
import { TaskStore } from '../viewmodel/TaskStore';
import { NativeBridgePort } from './ServiceContracts';
import { BridgeError } from '../common/BridgeError';

// internalRef is an opaque Native key. Only Native opens and validates its committed output.
export class ArtifactDelivery {
  private store: TaskStore;
  private native: NativeBridgePort;
  constructor(store: TaskStore, native: NativeBridgePort) { this.store = store; this.native = native; }

  private fileName(taskId: string): string {
    const task: DemoTask | undefined = this.store.snapshot().find((item: DemoTask) => item.id === taskId);
    const base: string = (task?.fileName ?? 'converted').replace(/\.[^.]+$/, '')
      .replace(/[\\/:*?"<>|]/g, '_').trim().slice(0, 80);
    return `${base.length > 0 ? base : 'converted'}.pdf`;
  }

  private async write(output: Artifact, uri: string, mode: number): Promise<void> {
    let target: fileIo.File | null = null;
    try {
      target = await fileIo.open(uri, mode);
      const copied: number = await this.native.copyArtifactToFd(output.internalRef, target.fd,
        output.sha256, output.byteSize);
      const stat: fileIo.Stat = await fileIo.stat(target.fd);
      if (copied !== output.byteSize || stat.size !== output.byteSize) {
        throw new BridgeError('IO_ERROR', 'PDF_EXPORT_SIZE_MISMATCH');
      }
    } finally {
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
      await this.write(output, uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      state = 'exported';
      return true;
    } finally { this.store.finishExport(taskId, output.artifactId, state); }
  }

  async share(taskId: string, context: common.UIAbilityContext): Promise<void> {
    const output: Artifact = this.store.beginShare(taskId);
    let shown: boolean = false;
    try {
      // ShareKit accepts an app file URI. The copy stays in system-managed cache while the
      // receiving app reads it; deleting it as soon as the panel opens would break sharing.
      const directory: string = `${context.cacheDir}/shared-pdf`;
      if (!await fileIo.access(directory)) { await fileIo.mkdir(directory, true); }
      const path: string = `${directory}/${output.artifactId}.pdf`;
      await this.write(output, path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'com.adobe.pdf', uri: fileUri.getUriFromPath(path), title: this.fileName(taskId), label: 'FILE'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL, anchor: `share-${taskId}` });
      shown = true;
    } finally { this.store.finishShare(taskId, shown); }
  }
}
