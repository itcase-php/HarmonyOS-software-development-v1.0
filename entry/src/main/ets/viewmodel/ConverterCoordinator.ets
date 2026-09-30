import { DemoTask, DemoSubmission, FidelitySelection } from '../models/InteractionModels';
import { ConversionRouteDefinition } from '../models/RegistryTypes';
import { AuthorizedFile, SessionContext } from '../models/SessionModels';
import { TaskStorePort } from '../services/ServiceContracts';
import { ConversionPlannerService } from './ConversionPlanner';
import { FidelityPolicy } from './FidelityPolicy';
import { FormatSelectionVM } from './FormatSelectionVM';
import { FileAuthorizationVM } from './FileAuthorizationVM';
import { ConversionStatusVM } from './ConversionStatusVM';
import { ConverterUiPort, PreviewConverterUi } from './ConverterUiPort';
import { ErrorHandler } from '../common/ErrorHandler';
import { BridgeError } from '../common/BridgeError';

export class ConverterCoordinator {
  private pendingSubmission: DemoSubmission | undefined = undefined;
  private pendingRealSubmission: DemoSubmission | undefined = undefined;
  private formats: FormatSelectionVM; private files: FileAuthorizationVM; private status: ConversionStatusVM;
  private store: TaskStorePort; private planner: ConversionPlannerService; private ui: ConverterUiPort;
  constructor(formats: FormatSelectionVM, files: FileAuthorizationVM, status: ConversionStatusVM,
    store: TaskStorePort, planner: ConversionPlannerService, ui: ConverterUiPort = new PreviewConverterUi()) {
    this.formats = formats; this.files = files; this.status = status; this.store = store; this.planner = planner; this.ui = ui;
    status.setOnChange(() => { formats.syncInteractivity(); });
  }
  setUi(ui: ConverterUiPort): void { this.ui = ui; this.formats.setUi(ui); this.files.setUi(ui); this.status.setUi(ui); }
  appear(): void { this.files.appear(); this.status.observeTasks(); this.formats.loadFormats(); }
  show(): void { this.files.appear(); this.status.observeTasks(); }
  hide(force: boolean = false): void { this.status.detach(); this.cancelAuthorizedConfirmation(); this.files.hide(force); }
  retry(): void { if (!this.formats.registryReady) { this.formats.loadFormats(); } else { this.status.errorText = ''; this.files.pickSourceFiles(); } }
  start(): void {
    if (this.files.authorizedFiles.length > 0) { this.startAuthorized(); return; }
    if (!this.formats.registryReady || this.status.working || this.status.confirming || this.status.inputBusy) { return; }
    try {
      const route = this.formats.activeRoutes.find((item: ConversionRouteDefinition) => item.id === this.formats.routeId);
      if (!route) { throw new BridgeError('UNSUPPORTED_FORMAT', 'DEMO_ROUTE_NOT_FOUND'); }
      const name = this.planner.validateFileName(this.formats.fileName, this.formats.sourceId);
      const fidelity = this.formats.selection();
      FidelityPolicy.validate(route, fidelity);
      if (route.requiresUserApproval && !this.formats.approved) {
        throw new BridgeError('INVALID_REQUEST', 'DEMO_APPROVAL_REQUIRED');
      }
      this.pendingSubmission = { fileName: name, sourceId: this.formats.sourceId, targetId: this.formats.targetId,
        routeId: route.id, approved: this.formats.approved, fidelity: fidelity };
      this.status.errorText = '';
      this.status.confirming = true; this.status.signal();
      const message = `文件：${name}\n格式：${this.formats.sourceId} → ${this.formats.targetId}\n质量：${this.formats.fidelity.qualitySummary}\n意图：${this.formats.fidelity.intentText}\n最低期望：${this.formats.fidelity.tierText}\n${this.formats.fidelity.routeDescription}\n路线：${route.id}\n降级配置：${route.allowedDegradations.join('、') || '无'}\n\n演示不会读取文件或产生真实保真结果。`;
      try {
        this.ui.showAlertDialog({
          title: '确认保真度配置（演示）', message: message, autoCancel: true,
          primaryButton: { value: '返回修改', action: () => { this.cancelConfirmation(); } },
          secondaryButton: { value: '确认开始演示', action: () => { this.beginConfirmed(); } },
          cancel: () => { this.cancelConfirmation(); }
        });
      } catch (error) { ErrorHandler.swallow('Converter.confirmation', error);
        // Previewer fallback: keep the same confirmation, never start automatically.
        this.status.inlineConfirmationText = message;
      }
    } catch (error) { this.status.showError(error); }
  }
  cancelConfirmation(): void {
    this.status.confirming = false; this.status.inlineConfirmationText = ''; this.pendingSubmission = undefined; this.status.signal();
  }
  beginConfirmed(): void {
    const submission = this.pendingSubmission;
    if (!submission || this.status.working) { return; }
    this.cancelConfirmation();
    try {
      const task = this.store.enqueue(submission.fileName, submission.sourceId, submission.targetId,
        submission.routeId, submission.approved, submission.fidelity);
      this.status.taskId = task.id; this.status.receiveTasks(this.store.snapshot());
      this.ui.toast( '已按确认的保真度配置开始演示');
    } catch (error) { this.status.showError(error); }
  }

  startAuthorized(): void {
    if (this.files.pickingFile || this.files.fileSubmitting || this.status.working || this.status.confirming || !this.files.sessionContext) { return; }
    try {
      if (this.files.authorizedFiles.length !== 1) { throw new BridgeError('INVALID_REQUEST', 'NATIVE_SINGLE_FILE_REQUIRED'); }
      const file: AuthorizedFile = this.files.authorizedFiles[0];
      const route: ConversionRouteDefinition | undefined = this.formats.activeRoutes.find((item: ConversionRouteDefinition) => item.id === this.formats.routeId);
      if (!route || file.detectedFormatId !== this.formats.sourceId) {
        this.status.errorText = this.status.inputText($r('app.string.input_source_mismatch')); return;
      }
      const fidelity: FidelitySelection = this.formats.selection();
      FidelityPolicy.validate(route, fidelity);
      if (route.requiresUserApproval && !this.formats.approved) { throw new BridgeError('INVALID_REQUEST', 'NATIVE_APPROVAL_REQUIRED'); }
      this.pendingRealSubmission = { fileName: file.originalName, sourceId: this.formats.sourceId, targetId: this.formats.targetId,
        routeId: route.id, approved: this.formats.approved, fidelity: fidelity };
      this.status.confirming = true; this.status.signal();
      const message: string = `${file.originalName}\n${this.formats.sourceId} → ${this.formats.targetId}\n${this.formats.fidelity.selectionSummary}\n${this.formats.fidelity.intentText}\n${this.formats.fidelity.routeDescription}\n${route.id}\n\n${this.status.inputText($r('app.string.input_native_boundary'))}`;
      try {
        this.ui.showAlertDialog({ title: this.status.inputText($r('app.string.input_confirm_title')), message: message, autoCancel: true,
          primaryButton: { value: this.status.inputText($r('app.string.input_back_edit')), action: () => { this.cancelAuthorizedConfirmation(); } },
          secondaryButton: { value: this.status.inputText($r('app.string.input_start_real')), action: () => { this.beginAuthorized(); } },
          cancel: () => { this.cancelAuthorizedConfirmation(); } });
      } catch (error) { ErrorHandler.swallow('Converter.confirmation', error); this.status.realConfirmationText = message; }
    } catch (error) { this.status.showInputError(error); }
  }
  cancelAuthorizedConfirmation(): void {
    this.pendingRealSubmission = undefined; this.status.realConfirmationText = ''; this.cancelConfirmation();
  }
  async beginAuthorized(): Promise<void> {
    const submission: DemoSubmission | undefined = this.pendingRealSubmission;
    const session: SessionContext | null = this.files.sessionContext;
    if (!submission || !session || this.files.fileSubmitting || this.status.working) { return; }
    this.cancelAuthorizedConfirmation(); this.files.beginSubmission();
    let transferred: boolean = false;
    try {
      const task: DemoTask = await this.store.submitTask(submission.fileName, submission.sourceId, submission.targetId,
        submission.routeId, submission.approved, submission.fidelity, this.files.authorizedFiles, session);
      transferred = true;
      if (this.files.isAlive()) { this.status.taskId = task.id; this.status.receiveTasks(this.store.snapshot()); }
    } catch (error) { if (this.files.isAlive()) { this.status.showInputError(error); } }
    finally { await this.files.finishSubmission(session, transferred); }
  }

}
