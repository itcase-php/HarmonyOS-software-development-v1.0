import { common } from '@kit.AbilityKit';
import { AuthorizedFile, FileAuthorizationPlatform, PickedFile, SessionContext } from '../models/SessionModels';
import { registryMetadata } from '../generated/RegistryData';
import { BridgeError } from '../common/BridgeError';
import { FormatRegistry } from './FormatRegistry';
import { HarmonyFilePlatform, fileAuthorizationError } from './HarmonyFilePlatform';
import { FormatRegistryPort, FileAuthorizationPort } from './ServiceContracts';
import { FormatDetectorIndex } from './FormatDetector';
import { TaskRuntime } from '../models/InteractionModels';
import { SystemRuntime, withDeadline } from '../common/Deadline';
import { ErrorHandler } from '../common/ErrorHandler';

class OwnedSession {
  context: SessionContext;
  closing: boolean = false;
  claimed: boolean = false;
  pending: Promise<void> = Promise.resolve();
  destroying: Promise<void> | null = null;
  operations: number = 0;
  lastUsedAt: number;
  constructor(context: SessionContext) { this.context = context; this.lastUsedAt = context.createdAt; }
}

// Injectable ownership logic; never accepts a caller-provided directory for deletion.
export class FileAuthorizationManager implements FileAuthorizationPort {
  private platform: FileAuthorizationPlatform;
  private sessions: Map<string, OwnedSession> = new Map<string, OwnedSession>();
  private grants: Map<string, PickedFile> = new Map<string, PickedFile>();
  private closed: boolean = false;
  private registry: FormatRegistryPort;
  private detector: FormatDetectorIndex;
  private runtime: TaskRuntime;
  private ttlMs: number;
  private expiryTimer: number = -1;
  private expiryListeners: Map<number, (id: string) => void> = new Map<number, (id: string) => void>();
  private expirySequence: number = 0;
  subscribeExpiry(listener: (id: string) => void): number { const token: number = ++this.expirySequence; this.expiryListeners.set(token, listener); return token; }
  unsubscribeExpiry(token: number): void { this.expiryListeners.delete(token); }
  constructor(platform: FileAuthorizationPlatform, registry: FormatRegistryPort = FormatRegistry.shared(),
    runtime: TaskRuntime = new SystemRuntime(), ttlMs: number = 30 * 60 * 1000) {
    this.platform = platform; this.registry = registry; this.detector = new FormatDetectorIndex(registry);
    this.runtime = runtime; this.ttlMs = ttlMs;
    if (!Number.isFinite(ttlMs) || ttlMs < 0) { throw new BridgeError('INVALID_REQUEST', 'SESSION_TTL_INVALID'); }
  }

  isAvailable(): boolean {
    try { return !this.closed && this.platform.isAvailable(); }
    catch (error) { ErrorHandler.swallow('FileAuthorization.available', error); return false; }
  }
  getWorkspaceRoot(): string {
    const cache: string = this.platform.cacheDir().replace(/\/+$/, '');
    if (!cache.startsWith('/') || cache.includes('\u0000') || cache.split('/').includes('..')) {
      throw new BridgeError('INVALID_REQUEST', 'SANDBOX_ROOT_INVALID');
    }
    return `${cache}/workspace`;
  }
  private requireAvailable(): void {
    if (!this.isAvailable()) { throw new BridgeError('UNSUPPORTED_FEATURE', 'FILE_PICKER_UNAVAILABLE'); }
  }
  private owned(sessionId: string): OwnedSession {
    const record: OwnedSession | undefined = this.sessions.get(sessionId);
    if (!record) { throw new BridgeError('INVALID_REQUEST', 'SESSION_NOT_FOUND'); }
    if (record.context.workspaceRef !== `${this.getWorkspaceRoot()}/${sessionId}` || !/^[a-f0-9-]{32,36}$/.test(sessionId)) {
      throw new BridgeError('PERMISSION_DENIED', 'WORKSPACE_NOT_OWNED');
    }
    return record;
  }
  getSession(sessionId: string): SessionContext {
    return JSON.parse(JSON.stringify(this.owned(sessionId).context)) as SessionContext;
  }
  activeSessions(): SessionContext[] {
    const result: SessionContext[] = [];
    for (const record of this.sessions.values()) {
      result.push(JSON.parse(JSON.stringify(record.context)) as SessionContext);
    }
    return result;
  }
  claimSession(sessionId: string): void {
    const record: OwnedSession = this.owned(sessionId);
    if (record.closing || record.claimed || record.operations > 0) { throw new BridgeError('TASK_BUSY', 'SESSION_ALREADY_SUBMITTED'); }
    record.claimed = true;
    this.scheduleExpiry();
  }

  async pickDocuments(maxCount: number): Promise<PickedFile[]> {
    try {
      this.requireAvailable();
      if (!Number.isInteger(maxCount) || maxCount < 1 || maxCount > 10) { throw new BridgeError('INVALID_REQUEST', 'FILE_SELECTION_LIMIT'); }
      const picked: PickedFile[] = await this.platform.pick(maxCount);
      if (this.closed) { throw new BridgeError('CONVERSION_CANCELLED', 'FILE_IMPORT_CANCELLED'); }
      if (picked.length > maxCount) { throw new BridgeError('INVALID_REQUEST', 'FILE_SELECTION_LIMIT'); }
      for (const file of picked) {
        if ((!file.uri.startsWith('file://') && !file.uri.startsWith('datashare://')) || file.uri.includes('\u0000')) {
          throw new BridgeError('INVALID_REQUEST', 'FILE_URI_INVALID');
        }
        if (!Number.isSafeInteger(file.fileSize) || file.fileSize <= 0) { throw new BridgeError('INVALID_REQUEST', 'FILE_EMPTY_OR_INVALID'); }
        if (file.fileSize > registryMetadata.defaultBudget.maxInputBytes) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'FILE_TOO_LARGE'); }
      }
      for (const file of picked) { this.grants.set(file.uri, JSON.parse(JSON.stringify(file)) as PickedFile); }
      return JSON.parse(JSON.stringify(picked)) as PickedFile[];
    } catch (error) { throw fileAuthorizationError(error, 'FILE_PICK_FAILED'); }
  }

  async createSession(): Promise<SessionContext> {
    let workspace: string = '';
    try {
      this.requireAvailable();
      const id: string = this.platform.uuid();
      if (!/^[a-f0-9-]{32,36}$/.test(id) || this.sessions.has(id)) { throw new BridgeError('INVALID_REQUEST', 'SESSION_ID_INVALID'); }
      workspace = `${this.getWorkspaceRoot()}/${id}`;
      if (await this.platform.exists(workspace)) { workspace = ''; throw new BridgeError('TASK_BUSY', 'WORKSPACE_ALREADY_EXISTS'); }
      await this.platform.mkdir(`${workspace}/inputs`);
      if (this.closed) { throw new BridgeError('CONVERSION_CANCELLED', 'FILE_IMPORT_CANCELLED'); }
      const context: SessionContext = { sessionId: id, workspaceRef: workspace, createdAt: this.platform.now(), inputFiles: [] };
      this.sessions.set(id, new OwnedSession(context));
      this.scheduleExpiry();
      return JSON.parse(JSON.stringify(context)) as SessionContext;
    } catch (error) {
      if (workspace.length > 0) { await this.platform.removeDirectory(workspace); }
      throw fileAuthorizationError(error, 'WORKSPACE_CREATE_FAILED');
    }
  }

  async copyToSandbox(file: PickedFile, sessionId: string): Promise<AuthorizedFile> {
    try {
      const record: OwnedSession = this.owned(sessionId);
      record.operations++;
      const previous: Promise<void> = record.pending;
      const operation: Promise<AuthorizedFile> = this.copyOwned(file, record, previous);
      record.pending = operation.then(() => {}).catch((error: Error) => { ErrorHandler.swallow('FileAuthorization.pending', error); });
      try { return await operation; }
      finally { record.operations--; record.lastUsedAt = this.platform.now(); this.scheduleExpiry(); }
    } catch (error) { throw fileAuthorizationError(error, 'FILE_COPY_FAILED'); }
  }

  private async copyOwned(file: PickedFile, record: OwnedSession, previous: Promise<void>): Promise<AuthorizedFile> {
    let destination: string = '';
    try {
      await previous;
      this.requireAvailable();
      if (record.closing || record.claimed) { throw new BridgeError('CONVERSION_CANCELLED', 'FILE_IMPORT_CANCELLED'); }
      const grant: PickedFile | undefined = this.grants.get(file.uri);
      if (!grant || grant.fileName !== file.fileName || grant.fileSize !== file.fileSize || grant.mimeType !== file.mimeType) {
        throw new BridgeError('PERMISSION_DENIED', 'FILE_NOT_PICKER_AUTHORIZED');
      }
      if (record.context.inputFiles.length >= 10) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'FILE_SELECTION_LIMIT'); }
      const extension: string = file.fileName.substring(file.fileName.lastIndexOf('.') + 1);
      if (this.registry.isBlocked(extension)) { throw new BridgeError('PERMISSION_DENIED', 'DRM_BLOCKED'); }
      const formatId: string = this.detector.detect(file.fileName, file.mimeType);
      if (formatId.length === 0) { throw new BridgeError('UNSUPPORTED_FORMAT', 'FILE_FORMAT_UNSUPPORTED'); }
      const used: number = record.context.inputFiles.reduce((total: number, item: AuthorizedFile) => total + item.byteSize, 0);
      const remaining: number = registryMetadata.defaultBudget.maxBatchBytes - used;
      if (file.fileSize > remaining) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'BATCH_TOO_LARGE'); }
      if (await this.platform.freeBytes(record.context.workspaceRef) < file.fileSize + 1024 * 1024) {
        throw new BridgeError('STORAGE_FULL', 'SANDBOX_FULL');
      }
      const id: string = this.platform.uuid();
      if (!/^[a-f0-9-]{32,36}$/.test(id)) { throw new BridgeError('INVALID_REQUEST', 'FILE_ID_INVALID'); }
      const relativePath: string = `inputs/${id}`;
      const target: string = `${record.context.workspaceRef}/${relativePath}`;
      if (await this.platform.exists(target)) { throw new BridgeError('TASK_BUSY', 'INPUT_ALREADY_EXISTS'); }
      destination = target;
      const size: number = await this.platform.copyUri(file.uri, target,
        Math.min(registryMetadata.defaultBudget.maxInputBytes, remaining), () => !record.closing && !this.closed);
      if (size > remaining) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'BATCH_TOO_LARGE'); }
      if (!Number.isSafeInteger(size) || size <= 0 || size > registryMetadata.defaultBudget.maxInputBytes) {
        throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'FILE_TOO_LARGE');
      }
      const digest: string = await this.platform.sha256(target);
      if (!/^[a-f0-9]{64}$/.test(digest)) { throw new BridgeError('IO_ERROR', 'FILE_HASH_INVALID'); }
      if (record.closing || this.closed) { throw new BridgeError('CONVERSION_CANCELLED', 'FILE_IMPORT_CANCELLED'); }
      const mimeId: string | null = this.detector.detectByMime(file.mimeType);
      const authorized: AuthorizedFile = { fileId: id, originalName: file.fileName, relativePath: relativePath,
        byteSize: size, sha256: digest, detectedFormatId: formatId, mimeType: file.mimeType,
        warnings: mimeId !== null && mimeId !== formatId ? ['FORMAT_MIME_MISMATCH'] : [] };
      record.context.inputFiles.push(authorized);
      this.grants.delete(file.uri);
      return JSON.parse(JSON.stringify(authorized)) as AuthorizedFile;
    } catch (error) {
      if (destination.length > 0) { await this.platform.unlink(destination); }
      throw fileAuthorizationError(error, 'FILE_COPY_FAILED');
    }
  }

  async removeFile(sessionId: string, fileId: string): Promise<void> {
    try {
      const record: OwnedSession = this.owned(sessionId);
      if (record.claimed || record.closing) { throw new BridgeError('TASK_BUSY', 'SESSION_ALREADY_SUBMITTED'); }
      const previous: Promise<void> = record.pending;
      record.operations++;
      const operation: Promise<void> = this.removeOwned(record, fileId, previous);
      record.pending = operation.catch((error: Error) => { ErrorHandler.swallow('FileAuthorization.pending', error); });
      try { await operation; }
      finally { record.operations--; record.lastUsedAt = this.platform.now(); this.scheduleExpiry(); }
    } catch (error) { throw fileAuthorizationError(error, 'FILE_REMOVE_FAILED'); }
  }
  private async removeOwned(record: OwnedSession, fileId: string, previous: Promise<void>): Promise<void> {
    try {
      await previous;
      if (record.closing || record.claimed) { throw new BridgeError('TASK_BUSY', 'SESSION_ALREADY_SUBMITTED'); }
      const file: AuthorizedFile | undefined = record.context.inputFiles.find((item: AuthorizedFile) => item.fileId === fileId);
      if (!file || file.relativePath !== `inputs/${fileId}` || !/^[a-f0-9-]{32,36}$/.test(fileId)) {
        throw new BridgeError('PERMISSION_DENIED', 'INPUT_NOT_OWNED');
      }
      await this.platform.unlink(`${record.context.workspaceRef}/${file.relativePath}`);
      record.context.inputFiles = record.context.inputFiles.filter((item: AuthorizedFile) => item.fileId !== fileId);
    } catch (error) { throw fileAuthorizationError(error, 'FILE_REMOVE_FAILED'); }
  }

  async destroySession(sessionId: string): Promise<void> {
    try {
      if (!this.sessions.has(sessionId)) { return; }
      const record: OwnedSession = this.owned(sessionId);
      record.closing = true;
      if (!record.destroying) { record.destroying = this.destroyOwned(record); }
      try { await record.destroying; }
      catch (error) { record.destroying = null; throw ErrorHandler.catchBridge(error, 'FileAuthorization.destroySession', 'IO_ERROR', 'WORKSPACE_REMOVE_FAILED'); }
    } catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
  }
  private async destroyOwned(record: OwnedSession): Promise<void> {
    try {
      await record.pending;
      await this.platform.removeDirectory(record.context.workspaceRef);
      this.sessions.delete(record.context.sessionId);
      this.scheduleExpiry();
    } catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
  }
  async destroyAllSessions(): Promise<void> {
    this.closed = true;
    this.stopExpiryTimer();
    this.grants.clear();
    await withDeadline(this.destroyAllOwned(), 5000,
      () => new BridgeError('CONVERSION_TIMEOUT', 'WORKSPACE_CLEANUP_TIMEOUT'), this.runtime);
  }
  private async destroyAllOwned(): Promise<void> {
    let failed: boolean = false;
    for (const id of Array.from(this.sessions.keys())) {
      try { await this.destroySession(id); }
      catch (error) { ErrorHandler.catchBridge(error, 'FileAuthorization.destroyAll'); failed = true; }
    }
    if (failed) { throw new BridgeError('IO_ERROR', 'WORKSPACE_REMOVE_FAILED'); }
  }
  private stopExpiryTimer(): void {
    if (this.expiryTimer !== -1) { this.runtime.clearTimeout(this.expiryTimer); this.expiryTimer = -1; }
  }
  private scheduleExpiry(): void {
    this.stopExpiryTimer();
    if (this.closed || this.ttlMs === 0) { return; }
    let delay: number = this.ttlMs;
    let hasDraft: boolean = false;
    for (const record of this.sessions.values()) {
      if (record.claimed || record.closing) { continue; }
      hasDraft = true;
      delay = Math.min(delay, Math.max(1000, record.lastUsedAt + this.ttlMs - this.platform.now()));
    }
    if (!hasDraft) { return; }
    this.expiryTimer = this.runtime.setTimeout(() => {
      this.expiryTimer = -1;
      this.expireIdleSessions().catch((error: Error) => { ErrorHandler.catchBridge(error, 'FileAuthorization.expiry'); });
    }, delay);
  }
  async expireIdleSessions(): Promise<void> {
    try {
      for (const record of Array.from(this.sessions.values())) {
        if (!record.claimed && !record.closing && record.operations === 0 &&
          this.platform.now() - record.lastUsedAt >= this.ttlMs && this.ttlMs > 0) {
          for (const listener of this.expiryListeners.values()) {
            try { listener(record.context.sessionId); }
            catch (error) { ErrorHandler.swallow('FileAuthorization.expiryObserver', error); }
          }
          await this.destroySession(record.context.sessionId);
        }
      }
    } finally { this.scheduleExpiry(); }
  }
}

export class FileAuthorizationService extends FileAuthorizationManager {
  private static manager: FileAuthorizationManager | null = null;
  static configure(context: common.UIAbilityContext): void {
    FileAuthorizationService.configurePlatform(new HarmonyFilePlatform(context));
  }
  static configurePlatform(platform: FileAuthorizationPlatform): void {
    if (FileAuthorizationService.manager && FileAuthorizationService.manager.activeSessions().length > 0) {
      throw new BridgeError('TASK_BUSY', 'FILE_SERVICE_HAS_ACTIVE_SESSIONS');
    }
    FileAuthorizationService.manager = new FileAuthorizationManager(platform);
  }
  static useDefault(manager: FileAuthorizationManager): void { FileAuthorizationService.manager = manager; }
  private static current(): FileAuthorizationManager {
    if (!FileAuthorizationService.manager) { throw new BridgeError('UNSUPPORTED_FEATURE', 'FILE_PICKER_UNAVAILABLE'); }
    return FileAuthorizationService.manager;
  }
  static isAvailable(): boolean {
    try { return FileAuthorizationService.current().isAvailable(); } catch (error) { ErrorHandler.swallow('FileAuthorizationService.fallback', error); return false; }
  }
  static getWorkspaceRoot(): string { return FileAuthorizationService.current().getWorkspaceRoot(); }
  static getSession(id: string): SessionContext { return FileAuthorizationService.current().getSession(id); }
  static claimSession(id: string): void { FileAuthorizationService.current().claimSession(id); }
  static async pickDocuments(maxCount: number): Promise<PickedFile[]> {
    try { return await FileAuthorizationService.current().pickDocuments(maxCount); }
    catch (error) { throw fileAuthorizationError(error, 'FILE_PICK_FAILED'); }
  }
  static async createSession(): Promise<SessionContext> {
    try { return await FileAuthorizationService.current().createSession(); }
    catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_CREATE_FAILED'); }
  }
  static async copyToSandbox(file: PickedFile, id: string): Promise<AuthorizedFile> {
    try { return await FileAuthorizationService.current().copyToSandbox(file, id); }
    catch (error) { throw fileAuthorizationError(error, 'FILE_COPY_FAILED'); }
  }
  static async removeFile(id: string, fileId: string): Promise<void> {
    try { await FileAuthorizationService.current().removeFile(id, fileId); }
    catch (error) { throw fileAuthorizationError(error, 'FILE_REMOVE_FAILED'); }
  }
  static async destroySession(id: string): Promise<void> {
    try { if (FileAuthorizationService.manager) { await FileAuthorizationService.manager.destroySession(id); } }
    catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
  }
  static async destroyAllSessions(): Promise<void> {
    try { if (FileAuthorizationService.manager) { await FileAuthorizationService.manager.destroyAllSessions(); } }
    catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
  }
  static captureCleanup(): () => Promise<void> {
    const manager: FileAuthorizationManager | null = FileAuthorizationService.manager;
    return async () => {
      try { if (manager) { await manager.destroyAllSessions(); } }
      catch (error) { throw fileAuthorizationError(error, 'WORKSPACE_REMOVE_FAILED'); }
    };
  }
}

// Legacy callers resolve the current facade at call time; app scopes inject an owned instance.
export class LegacyFileAuthorization implements FileAuthorizationPort {
  isAvailable(): boolean { return FileAuthorizationService.isAvailable(); }
  getWorkspaceRoot(): string { return FileAuthorizationService.getWorkspaceRoot(); }
  getSession(id: string): SessionContext { return FileAuthorizationService.getSession(id); }
  claimSession(id: string): void { return FileAuthorizationService.claimSession(id); }
  pickDocuments(maxCount: number): Promise<PickedFile[]> { return FileAuthorizationService.pickDocuments(maxCount); }
  createSession(): Promise<SessionContext> { return FileAuthorizationService.createSession(); }
  copyToSandbox(file: PickedFile, id: string): Promise<AuthorizedFile> { return FileAuthorizationService.copyToSandbox(file, id); }
  removeFile(id: string, fileId: string): Promise<void> { return FileAuthorizationService.removeFile(id, fileId); }
  destroySession(id: string): Promise<void> { return FileAuthorizationService.destroySession(id); }
  destroyAllSessions(): Promise<void> { return FileAuthorizationService.destroyAllSessions(); }
}
