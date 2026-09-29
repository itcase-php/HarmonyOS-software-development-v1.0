import { Availability, FidelityTier, FormatDefinition, Intent, Operation, PlanStep, ResourceBudget } from './NativeProtocol';

export interface RegistryFormat extends FormatDefinition {
  availability: Availability;
}
export interface InputConstraints {
  minInputs: number;
  maxInputs: number;
  protectedInputs: 'block';
}
export interface ConversionRouteDefinition {
  id: string;
  from: string[];
  to: string;
  operation: Operation;
  pathMode: 'direct' | 'relay';
  intent: Intent;
  fidelityTier: FidelityTier;
  engineIds: string[];
  priority: number;
  status: Availability;
  phase: number;
  steps: PlanStep[];
  fallbackRouteIds: string[];
  requiresUserApproval: boolean;
  allowedDegradations: string[];
  inputConstraints: InputConstraints;
  optionsProfileId: string;
  validationProfileId: string;
}
export interface RegistrySecurityPolicy {
  version: string;
  allowDrm: boolean;
  allowEncrypted: boolean;
  allowSigned: boolean;
  unknownProtection: 'block';
  networkResources: 'deny';
}
export interface MigrationAlias { from: string; to: string; }
export interface RegistryMetadata {
  schemaVersion: number;
  configVersion: string;
  formatsSha256: string;
  matrixSha256: string;
  blockedFormats: string[];
  engineIds: string[];
  optionsProfileIds: string[];
  validationProfileIds: string[];
  migrationAliases: MigrationAlias[];
  securityPolicy: RegistrySecurityPolicy;
  defaultBudget: ResourceBudget;
}
