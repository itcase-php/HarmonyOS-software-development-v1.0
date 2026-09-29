// Generated from models/NativeProtocol.ets. Do not edit independently.
// Protocol v1 migrated into ArkTS. Implemented binding subset is documented in IMPLEMENTATION_STATUS.md.
export type TaskState = 'queued' | 'running' | 'paused' | 'cancelled' | 'success' | 'failed' | 'interrupted';
export type Stage = 'preparing' | 'executing' | 'validating' | 'committing' | 'cleaning';
export type Intent = 'layout_preserved' | 'structured_rebuild' | 'content_only';
export type QualityMode = 'fast' | 'balanced' | 'high_fidelity';
export type FidelityTier = 'extreme' | 'standard' | 'compatible';
export type MetricState = 'measured' | 'estimated' | 'unavailable' | 'not_applicable';
export type Availability = 'planned' | 'experimental' | 'available' | 'unavailable';
export type ExportState = 'pending' | 'exporting' | 'exported' | 'failed' | 'cancelled';
export type Operation = 'convert' | 'images_to_pdf' | 'pdf_split' | 'pdf_merge' | 'extract_text' | 'ocr_extract';
export type ProtectionState = 'none' | 'drm' | 'encrypted' | 'signed' | 'unknown';
export type ErrorCode = 'UNSUPPORTED_FORMAT' | 'ENGINE_MISSING' | 'PASSWORD_REQUIRED' | 'PASSWORD_INVALID'
  | 'FILE_CORRUPTED' | 'RESOURCE_LIMIT_EXCEEDED' | 'OCR_LOW_CONFIDENCE'
  | 'OUTPUT_VALIDATION_FAILED' | 'CONVERSION_CANCELLED' | 'INVALID_REQUEST'
  | 'PERMISSION_DENIED' | 'INPUT_NOT_FOUND' | 'STORAGE_FULL' | 'CONVERSION_TIMEOUT'
  | 'TASK_INTERRUPTED' | 'FONT_MISSING' | 'UNSUPPORTED_FEATURE' | 'INTERNAL_ERROR'
  | 'PROTOCOL_INCOMPATIBLE' | 'CONFIG_INVALID' | 'ABI_UNSUPPORTED' | 'TASK_BUSY' | 'IO_ERROR';

export interface AppError {
  code: ErrorCode;
  reason: string;
  module: string;
  stage: Stage;
  retryable: boolean;
  traceId: string;
  messageKey: string;
  detailKey?: string;
}
export interface ConversionWarning {
  code: ErrorCode;
  reason: string;
  messageKey: string;
  requiresManualReview: boolean;
  evidenceRef?: string;
}
export interface DocumentEntity {
  fileId: string;
  displayName: string; // UI/repository only; never diagnostic log.
  sourceUri: string; // FileService only; never sent directly to a converter.
  sourceGrantState: 'active' | 'expired' | 'not_retained';
  internalCopyRef?: string;
  detectedFormatId?: string;
  byteSize: number;
  protection: ProtectionState;
  importedAtMs: number;
}
export interface OptionValue {
  key: string;
  kind: 'string' | 'number' | 'boolean';
  stringValue?: string;
  numberValue?: number;
  booleanValue?: boolean;
}
export interface FormatDefinition {
  id: string;
  displayName: string;
  extensions: string[];
  mimeTypes: string[];
  operations: ('import' | 'export')[];
  category: 'pdf' | 'office' | 'text' | 'image' | 'audio';
  defaultOptions: OptionValue[];
}
export interface ResourceBudget {
  maxInputBytes: number;
  maxBatchBytes: number;
  maxPages: number;
  maxPixels: number;
  maxNativeBytes: number;
  maxTempBytes: number;
  maxThreads: number;
  timeoutMs: number;
}
export interface PageRange { first: number; last: number; }
export interface PdfOptions {
  pages: PageRange[]; // 1-based, ascending, disjoint for v1; empty means all.
  dpi: number;
  imageQuality: number; // 1..100; applies to JPEG output only.
  backgroundArgb: number;
  paperWidthPt: number;
  paperHeightPt: number;
  marginPt: number;
  fitMode: 'fit' | 'fill' | 'original';
  rotation: 0 | 90 | 180 | 270;
}
export interface ImageOptions {
  quality: number;
  backgroundArgb: number;
  metadataPolicy: 'preserve_allowed' | 'remove';
  colorPolicy: 'preserve_profile' | 'convert_srgb';
  normalizeOrientation: boolean;
}
export interface OfficeOptions {
  allowedDegradations: string[]; // finite configuration whitelist.
  includeReferencePages: boolean;
  missingFontPolicy: 'reject' | 'approved_fallback';
}
export interface AudioOptions {
  codecId: string;
  containerId: string;
  bitrateMode: 'constant' | 'variable';
  bitrateBps: number;
  sampleRateHz: number;
  channels: number;
  metadataPolicy: 'preserve_allowed' | 'remove';
}
export interface OcrOptions {
  modelId: string;
  languages: string[];
  lowConfidencePolicy: 'review' | 'reject';
}
export interface ConvertOptions {
  pdf?: PdfOptions;
  image?: ImageOptions;
  office?: OfficeOptions;
  audio?: AudioOptions;
  ocr?: OcrOptions;
}
export interface PreparedInput {
  fileId: string;
  sourceFormatId: string;
  relativePath: string; // random internal name, validated against task workspace.
  byteSize: number;
  sha256: string;
}
export interface PlanStep {
  stepId: string;
  engineIds: string[];
  executorEngineId: string;
  inputFormatIds: string[];
  outputFormatId: string;
  operation: Operation;
}
export interface ApprovedPlan {
  routeId: string;
  steps: PlanStep[];
  fallbackRouteIds: string[]; // informative: ArkTS replans, Native never silently selects.
  configVersion: string;
  configSha256: string;
  intent: Intent;
  minimumTier: FidelityTier;
  allowedDegradations: string[];
  policyVersion: string;
}
export interface ConvertRequest {
  schemaVersion: number;
  sessionId: string;
  taskId: string;
  attemptId: string;
  workspaceRef: string;
  operation: Operation;
  inputs: PreparedInput[];
  targetFormatId: string;
  qualityMode: QualityMode;
  intent: Intent;
  options: ConvertOptions;
  resourceBudget: ResourceBudget;
  plan: ApprovedPlan;
}
export interface Metric {
  name: string;
  state: MetricState;
  value?: number;
  denominator?: number;
  unit: string;
  algorithmVersion: string;
  evidenceRefs: string[];
}
export interface FidelityReport {
  schemaVersion: number;
  intent: Intent;
  requestedTier: FidelityTier;
  achievedTier?: FidelityTier;
  sourcePageCount?: number;
  outputPageCount?: number;
  metrics: Metric[];
  fontSubstitutions: string[];
  unsupportedFeatures: string[];
  degradations: string[];
  requiresManualReview: boolean;
  detectorVersion: string;
  evidenceRefs: string[];
}
export interface Artifact {
  artifactId: string;
  role: 'primary' | 'reference' | 'report' | 'bundle';
  formatId: string;
  internalRef: string; // opaque committed ref; no external URI.
  byteSize: number;
  sha256: string;
  pageIndex?: number;
}
export interface Validation {
  state: 'passed' | 'failed' | 'not_evaluated';
  validatorVersion: string;
  evidenceRefs: string[];
}
export interface EngineStamp { engineId: string; version: string; buildHash: string; }
export interface ConvertResult {
  schemaVersion: number;
  taskId: string;
  attemptId: string;
  status: 'success' | 'failed' | 'cancelled';
  error?: AppError;
  warnings: ConversionWarning[];
  outputs: Artifact[];
  validation: Validation;
  fidelity?: FidelityReport;
  engines: EngineStamp[];
  elapsedMs: number;
  nativePeakBytes: number;
  tempPeakBytes: number;
}
export interface ExportRecord { artifactId: string; state: ExportState; error?: AppError; }
export interface ConversionTask {
  taskId: string;
  batchId?: string;
  attemptId: string;
  state: TaskState;
  stage?: Stage;
  stateVersion: number;
  priority: number;
  attemptCount: number;
  configVersion: string;
  plan: ApprovedPlan;
  result?: ConvertResult;
  exports: ExportRecord[]; // ArkTS owns export state; absent from Native result.
}
export interface ProgressEvent {
  taskId: string;
  attemptId: string;
  stage: Stage;
  sequence: number;
  unit: 'pages' | 'bytes' | 'audio_ms' | 'steps';
  completedUnits: number;
  totalUnits?: number;
  fraction?: number;
}
export interface RouteCapability {
  routeId: string;
  availability: Availability;
  reason: string;
  supportsPause: boolean;
  supportsCheckpoint: boolean;
  decoderIds: string[];
  encoderIds: string[];
  inputSubsetId: string;
  validationProfileId: string;
  releaseEvidenceId?: string;
}
export interface CapabilityMatrix {
  schemaVersion: number;
  offlineOnly: boolean;
  abi: string;
  configVersion: string;
  engines: EngineStamp[];
  routes: RouteCapability[];
}
export interface CapabilityRequest { schemaVersion: number; sessionId: string; configVersion: string; }
export interface ProbeRequest { schemaVersion: number; sessionId: string; workspaceRef: string; inputs: PreparedInput[]; resourceBudget: ResourceBudget; }
export interface InputProbe { fileId: string; actualFormatId?: string; protection: ProtectionState; pageCount?: number; needsDeepCheck: boolean; }
export interface ControlAck { taskId: string; attemptId: string; state: 'accepted' | 'too_late' | 'not_found' | 'unsupported'; }
export interface SessionInit { schemaVersion: number; appSandboxRoot: string; configVersion: string; configSha256: string; }
export interface WorkspaceGrant { sessionId: string; taskId: string; attemptId: string; relativeDirectory: string; }
export interface NativeModule {
  initializeSession(init: SessionInit): Promise<string>;
  registerWorkspace(grant: WorkspaceGrant): Promise<string>;
  getCapabilities(request: CapabilityRequest): Promise<CapabilityMatrix>;
  probeInputs(request: ProbeRequest): Promise<InputProbe[]>;
  execute(request: ConvertRequest): Promise<ConvertResult>;
  subscribeProgress(taskId: string, listener: (event: ProgressEvent) => void): string;
  unsubscribeProgress(subscriptionId: string): boolean;
  cancel(taskId: string, attemptId: string): Promise<ControlAck>;
  pause(taskId: string, attemptId: string): Promise<ControlAck>;
  resume(taskId: string, attemptId: string): Promise<ControlAck>;
  releaseTask(taskId: string, attemptId: string): Promise<void>;
  releaseArtifact(internalRef: string): Promise<void>;
  shutdown(): Promise<void>;
}
