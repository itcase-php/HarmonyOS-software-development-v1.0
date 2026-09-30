// Explicit DTO ownership snapshots. Update with the schema; coverage checks detect omissions.
import { OptionValue, PlanStep } from './NativeProtocol';
import { RegistryFormat, ConversionRouteDefinition, InputConstraints } from './RegistryTypes';

import { ConversionSnapshot } from './ConversionSnapshot';

export class RegistrySnapshotCopy {
  static copyOptionValue(value: OptionValue): OptionValue {
    const copy: OptionValue = {
      key: value.key,
      kind: value.kind
    };
    const fields: string[] = Object.keys(value);
    if (fields.includes('stringValue')) { copy.stringValue = value.stringValue === undefined ? undefined : value.stringValue; }
    if (fields.includes('numberValue')) { copy.numberValue = value.numberValue === undefined ? undefined : value.numberValue; }
    if (fields.includes('booleanValue')) { copy.booleanValue = value.booleanValue === undefined ? undefined : value.booleanValue; }
    return copy;
  }
  static copyRegistryFormat(value: RegistryFormat): RegistryFormat {
    const copy: RegistryFormat = {
      id: value.id,
      displayName: value.displayName,
      extensions: value.extensions.slice(),
      mimeTypes: value.mimeTypes.slice(),
      operations: value.operations.slice(),
      category: value.category,
      defaultOptions: value.defaultOptions.map((item: OptionValue): OptionValue => RegistrySnapshotCopy.copyOptionValue(item)),
      availability: value.availability
    };
    return copy;
  }
  static copyConversionRouteDefinition(value: ConversionRouteDefinition): ConversionRouteDefinition {
    const copy: ConversionRouteDefinition = {
      id: value.id,
      from: value.from.slice(),
      to: value.to,
      operation: value.operation,
      pathMode: value.pathMode,
      intent: value.intent,
      fidelityTier: value.fidelityTier,
      engineIds: value.engineIds.slice(),
      priority: value.priority,
      status: value.status,
      phase: value.phase,
      steps: value.steps.map((item: PlanStep): PlanStep => ConversionSnapshot.copyPlanStep(item)),
      fallbackRouteIds: value.fallbackRouteIds.slice(),
      requiresUserApproval: value.requiresUserApproval,
      allowedDegradations: value.allowedDegradations.slice(),
      inputConstraints: RegistrySnapshotCopy.copyInputConstraints(value.inputConstraints),
      optionsProfileId: value.optionsProfileId,
      validationProfileId: value.validationProfileId
    };
    return copy;
  }
  static copyInputConstraints(value: InputConstraints): InputConstraints {
    const copy: InputConstraints = {
      minInputs: value.minInputs,
      maxInputs: value.maxInputs,
      protectedInputs: value.protectedInputs
    };
    return copy;
  }
}
