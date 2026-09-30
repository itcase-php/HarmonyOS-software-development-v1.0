import { FidelityTier, Intent, QualityMode, FidelityReport } from './NativeProtocol';
import { FidelityReportSnapshot } from './FidelityReportSnapshot';

export type ExecutionMode = 'demo' | 'native';

export type DemoTaskStatus = 'queued' | 'running' | 'paused' | 'cancelled' | 'completed' | 'failed';

export interface FidelitySelection {
  qualityMode: QualityMode;
  requestedIntent: Intent;
  requestedTier: FidelityTier;
}

export interface TaskRuntime {
  now(): number;
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(id: number): void;
}

// Page-owned selection and presentation state. Components receive one complete snapshot.
@Observed
export class FidelitySettingsVM {
  qualityMode: QualityMode = 'balanced';
  requestedIntent: Intent = 'layout_preserved';
  requestedTier: FidelityTier = 'standard';
  intentChoices: SelectOption[] = [];
  tierChoices: SelectOption[] = [];
  intentIndex: number = 0;
  tierIndex: number = 1;
  intentText: string = '';
  tierText: string = '';
  qualitySummary: string = '';
  routeDescription: string = '';
  routeNotice: string = '';
  selectionSummary: string = '';
  routeAvailable: boolean = false;
  interactive: boolean = true;

  clone(): FidelitySettingsVM {
    const copy = new FidelitySettingsVM();
    copy.qualityMode = this.qualityMode; copy.requestedIntent = this.requestedIntent;
    copy.requestedTier = this.requestedTier;
    copy.intentChoices = this.intentChoices.map((item: SelectOption): SelectOption => ({ value: item.value, icon: item.icon }));
    copy.tierChoices = this.tierChoices.map((item: SelectOption): SelectOption => ({ value: item.value, icon: item.icon }));
    copy.intentIndex = this.intentIndex; copy.tierIndex = this.tierIndex;
    copy.intentText = this.intentText; copy.tierText = this.tierText; copy.qualitySummary = this.qualitySummary;
    copy.routeDescription = this.routeDescription; copy.routeNotice = this.routeNotice;
    copy.selectionSummary = this.selectionSummary; copy.routeAvailable = this.routeAvailable;
    copy.interactive = this.interactive;
    return copy;
  }
}

export interface DemoSubmission {
  fileName: string;
  sourceId: string;
  targetId: string;
  routeId: string;
  approved: boolean;
  fidelity: FidelitySelection;
}

export interface QualityChoice { value: QualityMode; label: string; }
export interface IntentChoice { value: Intent; label: string; }
export interface TierChoice { value: FidelityTier; label: string; }
export interface ReportMetricRow { name: string; value: string; state: string; }

// Keep the public name for existing pages. Copy ownership belongs to this model.
export class DemoTask {
  id: string = '';
  mode: ExecutionMode = 'demo';
  fileName: string = '';
  sourceFormat: string = '';
  targetFormat: string = '';
  routeId: string = '';
  qualityMode: QualityMode = 'balanced';
  intent: Intent = 'layout_preserved';
  requestedIntent: Intent = 'layout_preserved';
  requestedTier: FidelityTier = 'standard';
  achievedTier: FidelityTier | undefined = undefined;
  fidelityReport: FidelityReport | undefined = undefined;
  status: DemoTaskStatus = 'queued';
  progress: number = 0;
  stage: string = '';
  createdAtMs: number = 0;
  elapsedMs: number = 0;
  resultLabel: string = '';
  error: string = '';

  clone(): DemoTask {
    const copy = new DemoTask();
    copy.id = this.id; copy.mode = this.mode; copy.fileName = this.fileName;
    copy.sourceFormat = this.sourceFormat; copy.targetFormat = this.targetFormat; copy.routeId = this.routeId;
    copy.qualityMode = this.qualityMode; copy.intent = this.intent; copy.requestedIntent = this.requestedIntent;
    copy.requestedTier = this.requestedTier; copy.achievedTier = this.achievedTier;
    copy.fidelityReport = this.fidelityReport ? FidelityReportSnapshot.copy(this.fidelityReport) : undefined;
    copy.status = this.status; copy.progress = this.progress; copy.stage = this.stage;
    copy.createdAtMs = this.createdAtMs; copy.elapsedMs = this.elapsedMs;
    copy.resultLabel = this.resultLabel; copy.error = this.error;
    return copy;
  }
}

export interface DemoTaskTiming {
  lastTickMs: number;
  activeMs: number;
  plannedTier: FidelityTier;
  allowedDegradations: string[];
}

export interface TaskListener {
  token: number;
  callback: (tasks: DemoTask[]) => void;
}

export interface ConverterNavigationParams {
  sourceFormatId?: string;
  qualityMode?: QualityMode;
}

export interface CategoryChoice { id: string; label: Resource; }

export function taskStatusLabel(status: DemoTaskStatus, mode: ExecutionMode = 'demo'): string {
  switch (status) {
    case 'queued': return '排队中';
    case 'running': return mode === 'demo' ? '演示中' : '转换中';
    case 'paused': return '已暂停';
    case 'cancelled': return '已取消';
    case 'completed': return mode === 'demo' ? '演示完成' : '转换完成';
    case 'failed': return '失败';
  }
}

export function taskStatusColor(status: DemoTaskStatus): ResourceColor {
  switch (status) {
    case 'running': return $r('app.color.palette_a65c00');
    case 'queued': case 'paused': return $r('app.color.palette_526077');
    case 'completed': return $r('app.color.palette_167644');
    case 'failed': return $r('app.color.palette_c53030');
    case 'cancelled': return $r('app.color.palette_526077');
  }
}

export function isActiveTask(status: DemoTaskStatus): boolean {
  return status === 'queued' || status === 'running' || status === 'paused';
}
