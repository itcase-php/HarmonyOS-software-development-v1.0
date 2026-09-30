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
    this.errorText = this.inputFailure(reason); this.retryable = !this.working; this.ui.toast(this.errorText);
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
      case 'DEMO_FILENAME_INVALID': this.errorText = '请输入有效文件名，不要包含目录路径或特殊字符'; break;
      case 'DEMO_EXTENSION_REQUIRED': this.errorText = '文件名需要扩展名，例如“报告.pdf”'; break;
      case 'DEMO_EXTENSION_MISMATCH': this.errorText = '扩展名与源格式不一致，请修改或填入示例'; break;
      case 'DRM_BLOCKED': this.errorText = '受保护格式已阻止演示'; break;
      case 'DEMO_APPROVAL_REQUIRED': this.errorText = '请先勾选同意所选路线的兼容降级'; break;
      case 'FIDELITY_INTENT_MISMATCH': this.errorText = '所选转换意图与路线不一致'; break;
      case 'FIDELITY_TIER_UNAVAILABLE': this.errorText = '当前路线不能满足最低保真等级，不会自动降级'; break;
      default: this.errorText = '此组合暂不能演示，请重新选择路线与保真设置'; break;
    }
    this.ui.toast( this.errorText);
  }

inputText(key: Resource): string { return this.ui.read( key); }

inputFailure(reason: string): string {
    if (reason === 'FILE_TOO_LARGE') { return this.inputText($r('app.string.file_too_large')); }
    if (reason === 'BATCH_TOO_LARGE') { return this.inputText($r('app.string.input_batch_too_large')); }
    if (reason === 'NATIVE_SINGLE_FILE_REQUIRED') { return this.inputText($r('app.string.input_single_file_required')); }
    if (reason === 'DRM_BLOCKED' || reason === 'FILE_FORMAT_UNSUPPORTED') { return this.inputText($r('app.string.input_format_unsupported')); }
    if (reason === 'MIGRATED_CONTRACT_NOT_IMPLEMENTED' || reason === 'NATIVE_ROUTE_UNAVAILABLE' ||
      reason === 'NATIVE_ENGINE_UNAVAILABLE' || reason === 'NATIVE_MODULE_NOT_AVAILABLE') {
      return this.inputText($r('app.string.input_engine_not_ready'));
    }
    if (reason === 'SANDBOX_FULL') { return this.inputText($r('app.string.input_storage_full')); }
    if (reason === 'NATIVE_SESSION_TIMEOUT') { return this.inputText($r('app.string.input_session_timeout')); }
    if (reason === 'FILE_GRANT_EXPIRED') { return this.inputText($r('app.string.input_grant_expired')); }
    return this.inputText($r('app.string.input_action_failed'));
  }
}
