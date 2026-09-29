import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { FormatRegistry } from '../services/FormatRegistry';
import { BridgeError } from '../common/BridgeError';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { FidelityPolicy } from './FidelityPolicy';

// UI demonstration planning. It never changes the Native availability matrix.
export class ConversionPlanner {
  static targets(sourceId: string): RegistryFormat[] {
    const source = FormatRegistry.normalizeFormat(sourceId);
    const candidates = FormatRegistry.listPlannedRoutes().filter((route: ConversionRouteDefinition) =>
      route.from.includes(source) && route.inputConstraints.minInputs <= 1 &&
      route.inputConstraints.maxInputs >= 1 && route.status !== 'unavailable');
    return FormatRegistry.listFormats().filter((format: RegistryFormat) =>
      candidates.some((route: ConversionRouteDefinition) => route.to === format.id));
  }

  static routes(sourceId: string, targetId: string, qualityMode?: QualityMode,
    preferredIntent?: Intent, minimumTier?: FidelityTier): ConversionRouteDefinition[] {
    const source = FormatRegistry.normalizeFormat(sourceId);
    const target = FormatRegistry.normalizeFormat(targetId);
    return FormatRegistry.listPlannedRoutes().filter((route: ConversionRouteDefinition) =>
      route.from.includes(source) && route.to === target && route.inputConstraints.minInputs <= 1 &&
      route.inputConstraints.maxInputs >= 1 && route.status !== 'unavailable' &&
      (preferredIntent === undefined || route.intent === preferredIntent) &&
      (minimumTier === undefined || FidelityPolicy.tierRank(route.fidelityTier) >= FidelityPolicy.tierRank(minimumTier)))
      .sort((a: ConversionRouteDefinition, b: ConversionRouteDefinition) => {
        // Quality heuristics compare routes within the same semantic intent only.
        if (preferredIntent !== undefined && a.intent === b.intent && qualityMode === 'high_fidelity') {
          const tier = FidelityPolicy.tierRank(b.fidelityTier) - FidelityPolicy.tierRank(a.fidelityTier);
          if (tier !== 0) { return tier; }
        }
        if (qualityMode === 'fast') {
          const steps = a.steps.length - b.steps.length;
          if (steps !== 0) { return steps; }
        }
        const mode = (a.pathMode === 'direct' ? 0 : 1) - (b.pathMode === 'direct' ? 0 : 1);
        return mode !== 0 ? mode : a.priority - b.priority;
      });
  }

  static bestRoute(sourceId: string, targetId: string, preferredIntent: Intent,
    qualityMode: QualityMode = 'balanced', minimumTier: FidelityTier = 'compatible'): ConversionRouteDefinition | undefined {
    return ConversionPlanner.routes(sourceId, targetId, qualityMode, preferredIntent, minimumTier)[0];
  }

  static validateFileName(name: string, sourceId: string): string {
    const value = name.trim();
    if (value.length === 0 || value.length > 180 || /[\\/\x00-\x1F<>:"|?*]/.test(value)) {
      throw new BridgeError('INVALID_REQUEST', 'DEMO_FILENAME_INVALID');
    }
    const dot = value.lastIndexOf('.');
    if (dot <= 0 || dot === value.length - 1) {
      throw new BridgeError('INVALID_REQUEST', 'DEMO_EXTENSION_REQUIRED');
    }
    const extension = value.substring(dot + 1).toLowerCase();
    if (FormatRegistry.isBlocked(extension)) {
      throw new BridgeError('PERMISSION_DENIED', 'DRM_BLOCKED');
    }
    const source = FormatRegistry.listFormats().find((item: RegistryFormat) =>
      item.id === FormatRegistry.normalizeFormat(sourceId));
    if (!source || !source.extensions.includes(extension)) {
      throw new BridgeError('INVALID_REQUEST', 'DEMO_EXTENSION_MISMATCH');
    }
    return value;
  }

  static resultLabel(name: string, targetId: string): string {
    const target = FormatRegistry.listFormats().find((item: RegistryFormat) => item.id === FormatRegistry.normalizeFormat(targetId));
    if (!target) { throw new BridgeError('UNSUPPORTED_FORMAT', 'TARGET_NOT_REGISTERED'); }
    const base = name.substring(0, name.lastIndexOf('.'));
    return `${base}.${target.extensions[0]}（演示名称，未生成文件）`;
  }
}
