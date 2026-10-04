import { LanguageManager } from '../common/LanguageManager';
import { DemoTask, isActiveTask } from '../models/InteractionModels';
import { TaskStorePort } from '../services/ServiceContracts';
import { TaskStore } from './TaskStore';
import { BridgeError } from '../common/BridgeError';
import { ErrorHandler } from '../common/ErrorHandler';
import { ConverterUiPort, PreviewConverterUi } from './ConverterUiPort';

@Observed
export class ConversionStatusVM {
  errorText: string = ''; taskId: string = ''; visibleTasks: DemoTask[] = [];
  working: boolean = false; confirming: boolean = false; inputBusy: boolean = false;
  inlineConfirmationText: string = ''; realConfirmationText: string = ''; retryable: boolean = false;
  private token: number = -1; private store: TaskStorePort; private ui: ConverterUiPort;
  private onChange: () => void = () => {};
  constructor(store: TaskStorePort = TaskStore.shared(), ui: ConverterUiPort = new PreviewConverterUi()) { this.store = store; this.ui = ui; }
  setUi(ui: ConverterUiPort): void { this.ui = ui; }
  setOnChange(callback: () => void): void { this.onChange = callback; }
  signal(): void { this.onChange(); }
  detach(): void { this.store.unsubscribe(this.token); this.token = -1; }
  showInputFailure(reason: string): void {
    this.errorText = this.inputFailureKey(reason); this.retryable = !this.working; this.ui.toast(LanguageManager.getString(this.errorText));
  }
  showInputError(error: Error): void {
    const failure: BridgeError = ErrorHandler.catchBridge(error, 'FileAuthorizationVM');
    this.showInputFailure(failure.reason);
  }
receiveTasks(tasks: DemoTask[]): void {
    this.visibleTasks = tasks.filter((task: DemoTask) => task.id === this.taskId);
    const task = this.visibleTasks[0];
    this.working = task !== undefined && isActiveTask(task.status);
    this.signal();
  }

observeTasks(): void {
    this.receiveTasks(this.store.snapshot());
    if (this.token === -1) {
      this.token = this.store.subscribe((tasks: DemoTask[]) => { this.receiveTasks(tasks); });
    }
  }

showError(error: Error): void {
    const failure: BridgeError = ErrorHandler.catchBridge(error, 'ConversionStatus');
    switch (failure.reason) {
      case 'DEMO_FILENAME_INVALID': this.errorText = 'demo_filename_invalid'; break;
      case 'DEMO_EXTENSION_REQUIRED': this.errorText = 'demo_extension_required'; break;
      case 'DEMO_EXTENSION_MISMATCH': this.errorText = 'demo_extension_mismatch'; break;
      case 'DRM_BLOCKED': this.errorText = 'demo_drm_blocked'; break;
      case 'DEMO_APPROVAL_REQUIRED': this.errorText = 'demo_approval_required'; break;
      case 'FIDELITY_INTENT_MISMATCH': this.errorText = 'intent_mismatch'; break;
      case 'FIDELITY_TIER_UNAVAILABLE': this.errorText = 'tier_unavailable'; break;
      default: this.errorText = 'demo_combination_unavailable'; break;
    }
    this.ui.toast(LanguageManager.getString(this.errorText));
  }

inputText(key: ResourceStr): string { return this.ui.read( key); }

inputFailure(reason: string): string { return LanguageManager.getString(this.inputFailureKey(reason)); }

inputFailureKey(reason: string): string {
    if (reason === 'FILE_TOO_LARGE') { return 'file_too_large'; }
    if (reason === 'BATCH_TOO_LARGE') { return 'input_batch_too_large'; }
    if (reason === 'NATIVE_SINGLE_FILE_REQUIRED') { return 'input_single_file_required'; }
    if (reason === 'DRM_BLOCKED' || reason === 'FILE_FORMAT_UNSUPPORTED') { return 'input_format_unsupported'; }
    if (reason === 'MIGRATED_CONTRACT_NOT_IMPLEMENTED' || reason === 'NATIVE_ROUTE_UNAVAILABLE' ||
      reason === 'NATIVE_ENGINE_UNAVAILABLE' || reason === 'NATIVE_MODULE_NOT_AVAILABLE') {
      return 'input_engine_not_ready';
    }
    if (reason === 'SANDBOX_FULL') { return 'input_storage_full'; }
    if (reason === 'NATIVE_SESSION_TIMEOUT') { return 'input_session_timeout'; }
    if (reason === 'FILE_GRANT_EXPIRED') { return 'input_grant_expired'; }
    return 'input_action_failed';
  }
}
