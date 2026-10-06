import { RegistryFormat } from '../models/RegistryTypes';
import { FormatRegistry } from './FormatRegistry';
import { FormatDetectorIndex } from './FormatDetector';
import { FormatRegistryPort } from './ServiceContracts';
import { ErrorHandler } from '../common/ErrorHandler';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri, hash, picker, statfs } from '@kit.CoreFileKit';
import { FileAuthorizationPlatform, PickedFile } from '../models/SessionModels';
import { BridgeError } from '../common/BridgeError';
import { ConversionDiagnostics } from '../common/ConversionDiagnostics';

interface FilePlatformFailure { code?: number; }

export function fileAuthorizationError(error: Error, reason: string): BridgeError {
  if (error instanceof BridgeError) { return error; }
  // SDK errors expose an optional numeric code; validate it before mapping recovery.
  const failure: FilePlatformFailure = error && typeof error === 'object' ? error as FilePlatformFailure : {};
  ErrorHandler.swallow('FilePlatform', error);
  if (failure.code === 13900025 || failure.code === 13900041) { return new BridgeError('STORAGE_FULL', 'SANDBOX_FULL'); }
  if (failure.code === 13900001 || failure.code === 13900012) { return new BridgeError('PERMISSION_DENIED', 'FILE_GRANT_EXPIRED'); }
  return new BridgeError('IO_ERROR', reason);
}

export class HarmonyFilePlatform implements FileAuthorizationPlatform {
  private context: common.UIAbilityContext;
  private registry: FormatRegistryPort;
  private detector: FormatDetectorIndex;
  constructor(context: common.UIAbilityContext, registry: FormatRegistryPort = FormatRegistry.shared()) {
    this.context = context; this.registry = registry; this.detector = new FormatDetectorIndex(registry);
  }
  isAvailable(): boolean {
    try {
      const pickerCapability: boolean = canIUse('SystemCapability.FileManagement.UserFileService');
      const ioCapability: boolean = canIUse('SystemCapability.FileManagement.File.FileIO');
      ConversionDiagnostics.stage('HarmonyFilePlatform', 'capability', '',
        `picker=${pickerCapability},io=${ioCapability},cache=${this.context.cacheDir.length > 0}`);
      if (this.context.cacheDir.length === 0 || !pickerCapability || !ioCapability) { return false; }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context);
      const selectable: boolean = typeof documentPicker.select === 'function';
      ConversionDiagnostics.stage('HarmonyFilePlatform', 'construct', '', selectable ? 'OK' : 'SELECT_MISSING');
      return selectable;
    } catch (error) { ErrorHandler.swallow('HarmonyFilePlatform.fallback', error); return false; }
  }
  cacheDir(): string { return this.context.cacheDir; }
  uuid(): string { return util.generateRandomUUID(false).toLowerCase(); }
  now(): number { return Date.now(); }

  async pick(maxCount: number): Promise<PickedFile[]> {
    try {
      const options: picker.DocumentSelectOptions = { maxSelectNumber: maxCount, fileSuffixFilters: [] };
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context);
      ConversionDiagnostics.stage('HarmonyFilePlatform', 'select');
      const uris: string[] = await documentPicker.select(options);
      ConversionDiagnostics.stage('HarmonyFilePlatform', uris.length === 0 ? 'cancelled' : 'selected');
      const files: PickedFile[] = [];
      if (uris.length > maxCount) { throw new BridgeError('INVALID_REQUEST', 'FILE_SELECTION_LIMIT'); }
      for (const uri of uris) {
        const source: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        try {
          const stat: fileIo.Stat = await fileIo.stat(source.fd);
          if (!stat.isFile()) { throw new BridgeError('INVALID_REQUEST', 'INPUT_NOT_REGULAR_FILE'); }
          const name: string = new fileUri.FileUri(uri).name;
          const detected: string | null = this.detector.detectByExtension(name);
          const format: RegistryFormat | undefined = detected ? this.registry.getFormat(detected) : undefined;
          // Picker returns URIs, not MIME metadata. Keep the registered hint separate from Native probing.
          const file: PickedFile = { uri: uri, fileName: name, fileSize: stat.size,
            mimeType: format && format.mimeTypes.length > 0 ? format.mimeTypes[0] : '' };
          files.push(file);
          ConversionDiagnostics.stage('HarmonyFilePlatform', 'input_opened');
        } finally { await fileIo.close(source); }
      }
      return files;
    } catch (error) { throw fileAuthorizationError(error, 'FILE_PICK_FAILED'); }
  }

  async exists(path: string): Promise<boolean> {
    try { return await fileIo.access(path); }
    catch (error) { throw fileAuthorizationError(error, 'FILE_ACCESS_FAILED'); }
  }
  async mkdir(path: string): Promise<void> {
    try { await fileIo.mkdir(path, true); }
    catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_CREATE_FAILED'); }
  }
  async freeBytes(path: string): Promise<number> {
    try { return await statfs.getFreeSize(path); }
    catch (error) { throw fileAuthorizationError(error, 'STORAGE_CHECK_FAILED'); }
  }

  async copyUri(uri: string, destination: string, maxBytes: number, active: () => boolean): Promise<number> {
    let source: fileIo.File | null = null;
    let target: fileIo.File | null = null;
    try {
      source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = await fileIo.stat(source.fd);
      if (!stat.isFile()) { throw new BridgeError('INVALID_REQUEST', 'INPUT_NOT_REGULAR_FILE'); }
      if (!Number.isSafeInteger(stat.size) || stat.size <= 0) { throw new BridgeError('INVALID_REQUEST', 'FILE_EMPTY_OR_INVALID'); }
      if (stat.size > maxBytes) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'FILE_TOO_LARGE'); }
      if (await this.freeBytes(this.context.cacheDir) < stat.size + 1024 * 1024) { throw new BridgeError('STORAGE_FULL', 'SANDBOX_FULL'); }
      target = await fileIo.open(destination, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const buffer: ArrayBuffer = new ArrayBuffer(256 * 1024);
      let total: number = 0;
      while (true) {
        if (!active()) { throw new BridgeError('CONVERSION_CANCELLED', 'FILE_IMPORT_CANCELLED'); }
        const count: number = await fileIo.read(source.fd, buffer);
        if (count === 0) { break; }
        if (count < 0 || count > buffer.byteLength) { throw new BridgeError('IO_ERROR', 'FILE_READ_INVALID'); }
        total += count;
        if (total > maxBytes) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'FILE_TOO_LARGE'); }
        let written: number = 0;
        while (written < count) {
          const chunk: ArrayBuffer = buffer.slice(written, count);
          const length: number = await fileIo.write(target.fd, chunk);
          if (length <= 0 || length > chunk.byteLength) { throw new BridgeError('IO_ERROR', 'FILE_WRITE_INCOMPLETE'); }
          written += length;
        }
      }
      const copied: fileIo.Stat = await fileIo.stat(target.fd);
      if (total !== stat.size || copied.size !== total) { throw new BridgeError('IO_ERROR', 'FILE_CHANGED_DURING_COPY'); }
      return total;
    } catch (error) { throw fileAuthorizationError(error, 'FILE_COPY_FAILED'); }
    finally {
      let failure: BridgeError | null = null;
      try { if (target) { await fileIo.close(target); } }
      catch (error) { failure = fileAuthorizationError(error, 'FILE_CLOSE_FAILED'); }
      try { if (source) { await fileIo.close(source); } }
      catch (error) { failure = fileAuthorizationError(error, 'FILE_CLOSE_FAILED'); }
      if (failure) { throw failure; }
    }
  }

  async sha256(path: string): Promise<string> {
    try { return (await hash.hash(path, 'sha256')).toLowerCase(); }
    catch (error) { throw fileAuthorizationError(error, 'FILE_HASH_FAILED'); }
  }
  async unlink(path: string): Promise<void> {
    try { if (await fileIo.access(path)) { await fileIo.unlink(path); } }
    catch (error) { throw fileAuthorizationError(error, 'FILE_REMOVE_FAILED'); }
  }
  async removeDirectory(path: string): Promise<void> {
    try { if (await fileIo.access(path)) { await fileIo.rmdir(path); } }
    catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
  }
}
