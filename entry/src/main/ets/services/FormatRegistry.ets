import { resourceManager } from '@kit.LocalizationKit';
import { bundledFormats, bundledRoutes, registryMetadata } from '../generated/RegistryData';
import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { CapabilityMatrix } from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';

// Bundled cache is generated from validated shared JSON; runtime hot-update decoder is a later milestone.
export class FormatRegistry {
  static async verifyBundledResources(resources: resourceManager.ResourceManager): Promise<void> {
    try {
      const formats = await resources.getRawFileContent('format-registry/formats.json');
      const matrix = await resources.getRawFileContent('format-registry/conversion-matrix.json');
      if (formats.byteLength === 0 || matrix.byteLength === 0) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_EMPTY');
      }
    } catch (error) {
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_READ_FAILED');
    }
  }

  static listFormats(): RegistryFormat[] { return bundledFormats.slice(); }
  static listPlannedRoutes(): ConversionRouteDefinition[] { return bundledRoutes.slice(); }

  static normalizeFormat(id: string): string {
    const value = id.trim().toLowerCase().replace(/^\./, '');
    const alias = registryMetadata.migrationAliases.find((item) => item.from === value);
    if (alias) { return alias.to; }
    const format = bundledFormats.find((item: RegistryFormat) => item.id === value || item.extensions.includes(value));
    return format ? format.id : value;
  }

  static isBlocked(format: string): boolean {
    return registryMetadata.blockedFormats.includes(format.trim().toLowerCase().replace(/^\./, ''));
  }

  static availableRoutes(capabilities: CapabilityMatrix): ConversionRouteDefinition[] {
    return bundledRoutes.filter((route: ConversionRouteDefinition) => {
      const actual = capabilities.routes.find((item) => item.routeId === route.id);
      return route.status === 'available' && actual !== undefined && actual.availability === 'available' &&
        actual.releaseEvidenceId !== undefined && actual.releaseEvidenceId.length > 0;
    });
  }
}
