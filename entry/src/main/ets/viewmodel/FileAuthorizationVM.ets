import { AuthorizedFile, PickedFile, SessionContext } from '../models/SessionModels';
import { FileAuthorizationPort } from '../services/ServiceContracts';
import { LegacyFileAuthorization } from '../services/FileAuthorizationService';
import { ConversionStatusVM } from './ConversionStatusVM';
import { FormatSelectionVM } from './FormatSelectionVM';
import { ConverterUiPort, PreviewConverterUi } from './ConverterUiPort';
import { ErrorHandler } from '../common/ErrorHandler';
import { BridgeError } from '../common/BridgeError';
import { withDeadline } from '../common/Deadline';

export class AuthorizedFileDataSource implements IDataSource {
  private files: AuthorizedFile[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.files.length; }
  getData(index: number): AuthorizedFile { return this.files[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener);
  }
  replace(files: AuthorizedFile[]): void {
    this.files = files;
    for (const listener of this.listeners) { listener.onDataReloaded(); }
  }
}

@Observed
export class FileAuthorizationVM {
  authorizedFiles: AuthorizedFile[] = [];
  sessionContext: SessionContext | null = null;
  filePickerAvailable: boolean = false;
  pickingFile: boolean = false;
  fileSubmitting: boolean = false;
  readonly dataSource: AuthorizedFileDataSource = new AuthorizedFileDataSource();
  private importGeneration: number = 0;
  private inputPageAlive: boolean = true;
  private selectingPicker: boolean = false;
  private expiryToken: number = -1;
  private files: FileAuthorizationPort;
  private status: ConversionStatusVM;
  private formats: FormatSelectionVM;
  private ui: ConverterUiPort;
  constructor(files: FileAuthorizationPort = new LegacyFileAuthorization(), status: ConversionStatusVM = new ConversionStatusVM(),
    formats: FormatSelectionVM = new FormatSelectionVM(), ui: ConverterUiPort = new PreviewConverterUi()) {
    this.files = files; this.status = status; this.formats = formats; this.ui = ui;
  }
  setUi(ui: ConverterUiPort): void { this.ui = ui; }
  setFiles(files: AuthorizedFile[]): void { this.authorizedFiles = files; this.dataSource.replace(files); }
  private signal(): void { this.status.inputBusy = this.pickingFile || this.fileSubmitting; this.status.signal(); }
  appear(): void {
    this.inputPageAlive = true; this.filePickerAvailable = this.files.isAvailable();
    if (this.expiryToken === -1 && this.files.subscribeExpiry) {
      this.expiryToken = this.files.subscribeExpiry((id: string) => {
        if (this.sessionContext?.sessionId === id) {
          this.sessionContext = null; this.setFiles([]);
          this.status.confirming = false; this.status.realConfirmationText = ''; this.status.signal();
          this.status.showInputFailure('FILE_GRANT_EXPIRED');
        }
      });
    }
    if (this.sessionContext) {
      try { this.files.getSession(this.sessionContext.sessionId); }
      catch (error) { this.sessionContext = null; this.setFiles([]); this.status.showInputError(error); }
    }
  }
  hide(force: boolean = false): void {
    // A system Picker temporarily hides its caller; its result remains authorized.
    if (this.selectingPicker && !force) { return; }
    if (this.files.unsubscribeExpiry) { this.files.unsubscribeExpiry(this.expiryToken); }
    this.expiryToken = -1;
    this.inputPageAlive = false; this.importGeneration++; this.pickingFile = false;
    if (!this.fileSubmitting && this.sessionContext) {
      const session: SessionContext = this.sessionContext;
      this.sessionContext = null; this.setFiles([]);
      this.cleanup(session).catch((error: Error) => { ErrorHandler.swallow('FileVM.hide', error); });
    }
    this.signal();
  }
  private async cleanup(session: SessionContext): Promise<void> {
    await withDeadline(this.files.destroySession(session.sessionId), 5000,
      () => new BridgeError('CONVERSION_TIMEOUT', 'WORKSPACE_CLEANUP_TIMEOUT'));
  }
  async pickSourceFiles(): Promise<void> {
    if (this.pickingFile || this.fileSubmitting || this.status.working || this.status.confirming || this.authorizedFiles.length > 0) { return; }
    this.pickingFile = true; this.selectingPicker = true; this.signal();
    const generation: number = ++this.importGeneration;
    let owned: SessionContext | null = null;
    try {
      let picked: PickedFile[] = [];
      try { picked = await this.files.pickDocuments(10); }
      finally { this.selectingPicker = false; }
      if (!this.inputPageAlive || generation !== this.importGeneration || picked.length === 0) { return; }
      owned = await this.files.createSession();
      if (!this.inputPageAlive || generation !== this.importGeneration) { await this.cleanup(owned); return; }
      this.sessionContext = owned;
      for (const file of picked) {
        const authorized: AuthorizedFile = await this.files.copyToSandbox(file, owned.sessionId);
        if (!this.inputPageAlive || generation !== this.importGeneration) { await this.cleanup(owned); return; }
        this.setFiles(this.authorizedFiles.concat([authorized]));
      }
      this.sessionContext = this.files.getSession(owned.sessionId);
      this.formats.selectFormat(this.authorizedFiles[0].detectedFormatId); this.status.errorText = '';
    } catch (error) {
      if (owned) {
        try { await this.cleanup(owned); }
        catch (cleanupError) { ErrorHandler.swallow('FileVM.import.cleanup', cleanupError); }
      }
      if (this.inputPageAlive && generation === this.importGeneration) {
        this.setFiles([]); this.sessionContext = null; this.status.showInputError(error);
      }
    } finally {
      if (generation === this.importGeneration) { this.pickingFile = false; this.signal(); }
    }
  }
  async removeSourceFile(fileId: string): Promise<void> {
    const session: SessionContext | null = this.sessionContext;
    if (!session || this.pickingFile || this.fileSubmitting || this.status.confirming || this.status.working) { return; }
    this.pickingFile = true; this.signal();
    try {
      await this.files.removeFile(session.sessionId, fileId);
      this.setFiles(this.authorizedFiles.filter((file: AuthorizedFile) => file.fileId !== fileId));
      if (this.authorizedFiles.length === 0) { await this.cleanup(session); this.sessionContext = null; }
      else { this.sessionContext = this.files.getSession(session.sessionId); }
    } catch (error) { this.status.showInputError(error); }
    finally { this.pickingFile = false; this.signal(); }
  }
  beginSubmission(): void { this.fileSubmitting = true; this.signal(); }
  async finishSubmission(session: SessionContext, transferred: boolean): Promise<void> {
    this.setFiles([]); this.sessionContext = null;
    try { if (!transferred) { await this.cleanup(session); } }
    catch (error) { ErrorHandler.swallow('FileVM.submit.cleanup', error); }
    finally { this.fileSubmitting = false; this.signal(); }
  }
  isAlive(): boolean { return this.inputPageAlive; }
  fileSizeText(size: number): string {
    return size >= 1024 * 1024 ? `${(size / (1024 * 1024)).toFixed(1)} MB` : `${(size / 1024).toFixed(1)} KB`;
  }
}
