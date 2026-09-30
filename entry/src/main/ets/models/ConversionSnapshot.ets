// Explicit DTO ownership snapshots. Update with the schema; coverage checks detect omissions.
import { AppError, ConversionWarning, Artifact, Validation, EngineStamp, ConvertResult, PageRange, PdfOptions, ImageOptions, OfficeOptions, AudioOptions, OcrOptions, ConvertOptions, PreparedInput, PlanStep, ApprovedPlan, ResourceBudget, ConvertRequest, Metric, FidelityReport } from './NativeProtocol';

export class ConversionSnapshot {
  static copyAppError(value: AppError): AppError {
    const copy: AppError = {
      code: value.code,
      reason: value.reason,
      module: value.module,
      stage: value.stage,
      retryable: value.retryable,
      traceId: value.traceId,
      messageKey: value.messageKey
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('detailKey')) { copy.detailKey = value.detailKey === undefined ? undefined : value.detailKey; }
    return copy;
  }
  static copyConversionWarning(value: ConversionWarning): ConversionWarning {
    const copy: ConversionWarning = {
      code: value.code,
      reason: value.reason,
      messageKey: value.messageKey,
      requiresManualReview: value.requiresManualReview
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('evidenceRef')) { copy.evidenceRef = value.evidenceRef === undefined ? undefined : value.evidenceRef; }
    return copy;
  }
  static copyArtifact(value: Artifact): Artifact {
    const copy: Artifact = {
      artifactId: value.artifactId,
      role: value.role,
      formatId: value.formatId,
      internalRef: value.internalRef,
      byteSize: value.byteSize,
      sha256: value.sha256
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('pageIndex')) { copy.pageIndex = value.pageIndex === undefined ? undefined : value.pageIndex; }
    return copy;
  }
  static copyValidation(value: Validation): Validation {
    const copy: Validation = {
      state: value.state,
      validatorVersion: value.validatorVersion,
      evidenceRefs: value.evidenceRefs.slice()
    };
    return copy;
  }
  static copyEngineStamp(value: EngineStamp): EngineStamp {
    const copy: EngineStamp = {
      engineId: value.engineId,
      version: value.version,
      buildHash: value.buildHash
    };
    return copy;
  }
  static copyConvertResult(value: ConvertResult): ConvertResult {
    const copy: ConvertResult = {
      schemaVersion: value.schemaVersion,
      taskId: value.taskId,
      attemptId: value.attemptId,
      status: value.status,
      warnings: value.warnings.map((item: ConversionWarning): ConversionWarning => ConversionSnapshot.copyConversionWarning(item)),
      outputs: value.outputs.map((item: Artifact): Artifact => ConversionSnapshot.copyArtifact(item)),
      validation: ConversionSnapshot.copyValidation(value.validation),
      engines: value.engines.map((item: EngineStamp): EngineStamp => ConversionSnapshot.copyEngineStamp(item)),
      elapsedMs: value.elapsedMs,
      nativePeakBytes: value.nativePeakBytes,
      tempPeakBytes: value.tempPeakBytes
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('error')) { copy.error = value.error === undefined ? undefined : ConversionSnapshot.copyAppError(value.error); }
    if (fields.includes('fidelity')) { copy.fidelity = value.fidelity === undefined ? undefined : ConversionSnapshot.copyFidelityReport(value.fidelity); }
    return copy;
  }
  static copyMetric(value: Metric): Metric {
    const copy: Metric = { name: value.name, state: value.state, unit: value.unit,
      algorithmVersion: value.algorithmVersion, evidenceRefs: value.evidenceRefs.slice() };
    const fields: string[] = Object.keys(value);
    if (fields.includes('value')) { copy.value = value.value; }
    if (fields.includes('denominator')) { copy.denominator = value.denominator; }
    return copy;
  }
  static copyFidelityReport(value: FidelityReport): FidelityReport {
    const copy: FidelityReport = { schemaVersion: value.schemaVersion, intent: value.intent,
      requestedTier: value.requestedTier, metrics: value.metrics.map((metric: Metric): Metric => ConversionSnapshot.copyMetric(metric)),
      fontSubstitutions: value.fontSubstitutions.slice(), unsupportedFeatures: value.unsupportedFeatures.slice(),
      degradations: value.degradations.slice(), requiresManualReview: value.requiresManualReview,
      detectorVersion: value.detectorVersion, evidenceRefs: value.evidenceRefs.slice() };
    const fields: string[] = Object.keys(value);
    if (fields.includes('achievedTier')) { copy.achievedTier = value.achievedTier; }
    if (fields.includes('sourcePageCount')) { copy.sourcePageCount = value.sourcePageCount; }
    if (fields.includes('outputPageCount')) { copy.outputPageCount = value.outputPageCount; }
    return copy;
  }
  static copyPageRange(value: PageRange): PageRange {
    const copy: PageRange = {
      first: value.first,
      last: value.last
    };
    return copy;
  }
  static copyPdfOptions(value: PdfOptions): PdfOptions {
    const copy: PdfOptions = {
      pages: value.pages.map((item: PageRange): PageRange => ConversionSnapshot.copyPageRange(item)),
      dpi: value.dpi,
      imageQuality: value.imageQuality,
      backgroundArgb: value.backgroundArgb,
      paperWidthPt: value.paperWidthPt,
      paperHeightPt: value.paperHeightPt,
      marginPt: value.marginPt,
      fitMode: value.fitMode,
      rotation: value.rotation
    };
    return copy;
  }
  static copyImageOptions(value: ImageOptions): ImageOptions {
    const copy: ImageOptions = {
      quality: value.quality,
      backgroundArgb: value.backgroundArgb,
      metadataPolicy: value.metadataPolicy,
      colorPolicy: value.colorPolicy,
      normalizeOrientation: value.normalizeOrientation
    };
    return copy;
  }
  static copyOfficeOptions(value: OfficeOptions): OfficeOptions {
    const copy: OfficeOptions = {
      allowedDegradations: value.allowedDegradations.slice(),
      includeReferencePages: value.includeReferencePages,
      missingFontPolicy: value.missingFontPolicy
    };
    return copy;
  }
  static copyAudioOptions(value: AudioOptions): AudioOptions {
    const copy: AudioOptions = {
      codecId: value.codecId,
      containerId: value.containerId,
      bitrateMode: value.bitrateMode,
      bitrateBps: value.bitrateBps,
      sampleRateHz: value.sampleRateHz,
      channels: value.channels,
      metadataPolicy: value.metadataPolicy
    };
    return copy;
  }
  static copyOcrOptions(value: OcrOptions): OcrOptions {
    const copy: OcrOptions = {
      modelId: value.modelId,
      languages: value.languages.slice(),
      lowConfidencePolicy: value.lowConfidencePolicy
    };
    return copy;
  }
  static copyConvertOptions(value: ConvertOptions): ConvertOptions {
    const copy: ConvertOptions = {

    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('pdf')) { copy.pdf = value.pdf === undefined ? undefined : ConversionSnapshot.copyPdfOptions(value.pdf); }
    if (fields.includes('image')) { copy.image = value.image === undefined ? undefined : ConversionSnapshot.copyImageOptions(value.image); }
    if (fields.includes('office')) { copy.office = value.office === undefined ? undefined : ConversionSnapshot.copyOfficeOptions(value.office); }
    if (fields.includes('audio')) { copy.audio = value.audio === undefined ? undefined : ConversionSnapshot.copyAudioOptions(value.audio); }
    if (fields.includes('ocr')) { copy.ocr = value.ocr === undefined ? undefined : ConversionSnapshot.copyOcrOptions(value.ocr); }
    return copy;
  }
  static copyPreparedInput(value: PreparedInput): PreparedInput {
    const copy: PreparedInput = {
      fileId: value.fileId,
      sourceFormatId: value.sourceFormatId,
      relativePath: value.relativePath,
      byteSize: value.byteSize,
      sha256: value.sha256
    };
    return copy;
  }
  static copyPlanStep(value: PlanStep): PlanStep {
    const copy: PlanStep = {
      stepId: value.stepId,
      engineIds: value.engineIds.slice(),
      executorEngineId: value.executorEngineId,
      inputFormatIds: value.inputFormatIds.slice(),
      outputFormatId: value.outputFormatId,
      operation: value.operation
    };
    return copy;
  }
  static copyApprovedPlan(value: ApprovedPlan): ApprovedPlan {
    const copy: ApprovedPlan = {
      routeId: value.routeId,
      steps: value.steps.map((item: PlanStep): PlanStep => ConversionSnapshot.copyPlanStep(item)),
      fallbackRouteIds: value.fallbackRouteIds.slice(),
      configVersion: value.configVersion,
      configSha256: value.configSha256,
      intent: value.intent,
      minimumTier: value.minimumTier,
      allowedDegradations: value.allowedDegradations.slice(),
      policyVersion: value.policyVersion
    };
    return copy;
  }
  static copyResourceBudget(value: ResourceBudget): ResourceBudget {
    const copy: ResourceBudget = {
      maxInputBytes: value.maxInputBytes,
      maxBatchBytes: value.maxBatchBytes,
      maxPages: value.maxPages,
      maxPixels: value.maxPixels,
      maxNativeBytes: value.maxNativeBytes,
      maxTempBytes: value.maxTempBytes,
      maxThreads: value.maxThreads,
      timeoutMs: value.timeoutMs
    };
    return copy;
  }
  static copyConvertRequest(value: ConvertRequest): ConvertRequest {
    const copy: ConvertRequest = {
      schemaVersion: value.schemaVersion,
      sessionId: value.sessionId,
      taskId: value.taskId,
      attemptId: value.attemptId,
      workspaceRef: value.workspaceRef,
      operation: value.operation,
      inputs: value.inputs.map((item: PreparedInput): PreparedInput => ConversionSnapshot.copyPreparedInput(item)),
      targetFormatId: value.targetFormatId,
      qualityMode: value.qualityMode,
      intent: value.intent,
      options: ConversionSnapshot.copyConvertOptions(value.options),
      resourceBudget: ConversionSnapshot.copyResourceBudget(value.resourceBudget),
      plan: ConversionSnapshot.copyApprovedPlan(value.plan)
    };
    return copy;
  }
}
