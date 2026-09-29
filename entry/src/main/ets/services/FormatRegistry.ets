import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { bundledFormats, bundledRoutes, registryMetadata } from '../generated/RegistryData';
import { RegistryFormat, ConversionRouteDefinition, BundledResourceReader,
  FormatsDocument, MatrixDocument, RegistrySnapshot } from '../models/RegistryTypes';
import { CapabilityMatrix } from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';

// The complete generated catalogue is available immediately, including in Previewer.
// Pinned digests belong to this build; hot updates require a separate signed-config design.
export class FormatRegistry {
  private static ready: boolean = false;
  private static loading: Promise<void> | null = null;
  private static formats: RegistryFormat[] = bundledFormats;
  private static routes: ConversionRouteDefinition[] = bundledRoutes;

  // True only after rawfile verification; offline catalogue queries do not require it.
  static isInitialized(): boolean { return FormatRegistry.ready; }

  static async initialize(resources: BundledResourceReader): Promise<void> {
    if (FormatRegistry.ready) { return; }
    if (!FormatRegistry.loading) { FormatRegistry.loading = FormatRegistry.loadAndInstall(resources); }
    const pending = FormatRegistry.loading;
    try { await pending; }
    catch (error) {
      if (FormatRegistry.loading === pending) { FormatRegistry.loading = null; }
      throw error as Error;
    }
  }

  private static async loadAndInstall(resources: BundledResourceReader): Promise<void> {
    const snapshot = await FormatRegistry.readWithinDeadline(resources);
    // Replace both documents only after every integrity check succeeds.
    FormatRegistry.formats = snapshot.formats;
    FormatRegistry.routes = snapshot.routes;
    FormatRegistry.ready = true;
  }
  static async verifyBundledResources(resources: BundledResourceReader): Promise<void> {
    await FormatRegistry.readWithinDeadline(resources);
  }

  private static readWithinDeadline(resources: BundledResourceReader): Promise<RegistrySnapshot> {
    return new Promise<RegistrySnapshot>((resolve, reject) => {
      const timeout = setTimeout(() => { reject(new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_TIMEOUT')); }, 5000);
      FormatRegistry.readVerified(resources).then((snapshot: RegistrySnapshot) => {
        clearTimeout(timeout); resolve(snapshot);
      }).catch((error: Error) => { clearTimeout(timeout); reject(error); });
    });
  }

  private static async sha256(bytes: Uint8Array): Promise<string> {
    try {
      if (!canIUse('SystemCapability.Security.CryptoFramework')) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_HASH_UNAVAILABLE');
      }
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: bytes });
      const result = await digest.digest();
      let hex = '';
      for (const byte of result.data) { hex += byte.toString(16).padStart(2, '0'); }
      return hex;
    } catch (error) {
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_HASH_UNAVAILABLE');
    }
  }

  private static async readVerified(resources: BundledResourceReader): Promise<RegistrySnapshot> {
    try {
      const documents = await Promise.all([
        resources.getRawFileContent('format-registry/formats.json'),
        resources.getRawFileContent('format-registry/conversion-matrix.json')
      ]);
      if (documents.some((bytes: Uint8Array) => bytes.byteLength === 0)) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_EMPTY');
      }
      if (documents.some((bytes: Uint8Array) => bytes.byteLength > 2 * 1024 * 1024)) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_TOO_LARGE');
      }
      const hashes = await Promise.all(documents.map((bytes: Uint8Array) => FormatRegistry.sha256(bytes)));
      if (hashes[0] !== registryMetadata.formatsSha256 || hashes[1] !== registryMetadata.matrixSha256) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_HASH_MISMATCH');
      }
      // Exact bytes were validated by check-design.cjs at generation time.
      // These casts decode pinned artifacts, not arbitrary configuration updates.
      const decoder = util.TextDecoder.create('utf-8', { fatal: true });
      const formats = JSON.parse(decoder.decodeToString(documents[0])) as FormatsDocument;
      const matrix = JSON.parse(decoder.decodeToString(documents[1])) as MatrixDocument;
      if (formats.schemaVersion !== registryMetadata.schemaVersion || matrix.schemaVersion !== registryMetadata.schemaVersion ||
        formats.configVersion !== registryMetadata.configVersion || matrix.configVersion !== registryMetadata.configVersion ||
        !Array.isArray(formats.formats) || !Array.isArray(matrix.routes) ||
        formats.formats.length !== registryMetadata.formatsCount || matrix.routes.length !== registryMetadata.routesCount) {
        throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_METADATA_MISMATCH');
      }
      return { formats: formats.formats, routes: matrix.routes };
    } catch (error) {
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_READ_FAILED');
    }
  }

  static listFormats(): RegistryFormat[] {
    return JSON.parse(JSON.stringify(FormatRegistry.formats)) as RegistryFormat[];
  }
  static listPlannedRoutes(): ConversionRouteDefinition[] {
    return JSON.parse(JSON.stringify(FormatRegistry.routes)) as ConversionRouteDefinition[];
  }

  static normalizeFormat(id: string): string {
    const value = id.trim().toLowerCase().replace(/^\./, '');
    const alias = registryMetadata.migrationAliases.find((item) => item.from === value);
    if (alias) { return alias.to; }
    const format = FormatRegistry.formats.find((item: RegistryFormat) => item.id === value || item.extensions.includes(value));
    return format ? format.id : value;
  }

  static isBlocked(format: string): boolean {
    return registryMetadata.blockedFormats.includes(format.trim().toLowerCase().replace(/^\./, ''));
  }

  static availableRoutes(capabilities: CapabilityMatrix): ConversionRouteDefinition[] {
    if (!FormatRegistry.ready) { return []; }
    return FormatRegistry.listPlannedRoutes().filter((route: ConversionRouteDefinition) => {
      const actual = capabilities.routes.find((item) => item.routeId === route.id);
      return route.status === 'available' && actual !== undefined && actual.availability === 'available' &&
        actual.releaseEvidenceId !== undefined && actual.releaseEvidenceId.length > 0;
    });
  }
}
