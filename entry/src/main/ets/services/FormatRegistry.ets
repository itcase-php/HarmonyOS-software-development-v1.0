import { ErrorHandler } from '../common/ErrorHandler';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { registryMetadata, catalogueCategories, formatOrder, routeOrder, loadBundledFormats,
  loadBundledRoutes } from '../generated/RegistryData';
import { RegistryFormat, ConversionRouteDefinition, BundledResourceReader,
  FormatsDocument, MatrixDocument, RegistrySnapshot } from '../models/RegistryTypes';
import { CapabilityMatrix } from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';
import { FormatRegistryPort } from './ServiceContracts';


// The complete generated catalogue is available immediately, including in Previewer.
// Pinned digests belong to this build; hot updates require a separate signed-config design.
export class FormatRegistryService implements FormatRegistryPort {
  private revision: number = 0;
  catalogueVersion(): number { return this.revision; }

  private ready: boolean = false;
  private loading: Promise<void> | null = null;
  private formats: RegistryFormat[] | null = null;
  private routes: ConversionRouteDefinition[] | null = null;
  private formatCategories: Map<string, RegistryFormat[]> = new Map<string, RegistryFormat[]>();
  private routeCategories: Map<string, ConversionRouteDefinition[]> = new Map<string, ConversionRouteDefinition[]>();

  // True only after rawfile verification; offline catalogue queries do not require it.
  isInitialized(): boolean { return this.ready; }

  async initialize(resources: BundledResourceReader): Promise<void> {
    if (this.ready) { return; }
    if (!this.loading) { this.loading = this.loadAndInstall(resources); }
    const pending = this.loading;
    try { await pending; }
    catch (error) {
      if (this.loading === pending) { this.loading = null; }
      throw ErrorHandler.catchBridge(error, 'FormatRegistry.initialize', 'CONFIG_INVALID', 'BUNDLED_RESOURCE_READ_FAILED');
    }
  }

  private async loadAndInstall(resources: BundledResourceReader): Promise<void> {
    const snapshot = await this.readWithinDeadline(resources);
    // Replace both documents only after every integrity check succeeds.
    this.formats = snapshot.formats;
    this.routes = snapshot.routes;
    this.ready = true;
    this.revision++;
  }
  async verifyBundledResources(resources: BundledResourceReader): Promise<void> {
    await this.readWithinDeadline(resources);
  }

  private readWithinDeadline(resources: BundledResourceReader): Promise<RegistrySnapshot> {
    return new Promise<RegistrySnapshot>((resolve, reject) => {
      const timeout = setTimeout(() => { reject(new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_TIMEOUT')); }, 5000);
      this.readVerified(resources).then((snapshot: RegistrySnapshot) => {
        clearTimeout(timeout); resolve(snapshot);
      }).catch((error: Error) => { clearTimeout(timeout); reject(error); });
    });
  }

  private async sha256(bytes: Uint8Array): Promise<string> {
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

  private async readVerified(resources: BundledResourceReader): Promise<RegistrySnapshot> {
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
      const hashes = await Promise.all(documents.map((bytes: Uint8Array) => this.sha256(bytes)));
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

  listFormats(category?: string): RegistryFormat[] {
    if (this.formats) {
      const selected: RegistryFormat[] = category ? this.formats.filter((format: RegistryFormat) => format.category === category) : this.formats;
      return JSON.parse(JSON.stringify(selected)) as RegistryFormat[];
    }
    let selected: RegistryFormat[] = [];
    for (const key of category ? [category] : catalogueCategories) {
      if (!this.formatCategories.has(key)) { this.formatCategories.set(key, loadBundledFormats(key)); }
      selected = selected.concat(this.formatCategories.get(key) ?? []);
    }
    selected.sort((a: RegistryFormat, b: RegistryFormat) => formatOrder.indexOf(a.id) - formatOrder.indexOf(b.id));
    return JSON.parse(JSON.stringify(selected)) as RegistryFormat[];
  }
  listPlannedRoutes(): ConversionRouteDefinition[] {
    if (!this.routes) {
      let selected: ConversionRouteDefinition[] = [];
      for (const key of catalogueCategories) {
        if (!this.routeCategories.has(key)) { this.routeCategories.set(key, loadBundledRoutes(key)); }
        selected = selected.concat(this.routeCategories.get(key) ?? []);
      }
      this.routes = selected.sort((a: ConversionRouteDefinition, b: ConversionRouteDefinition) => routeOrder.indexOf(a.id) - routeOrder.indexOf(b.id));
    }
    return JSON.parse(JSON.stringify(this.routes)) as ConversionRouteDefinition[];
  }

  normalizeFormat(id: string): string {
    const value = id.trim().toLowerCase().replace(/^\./, '');
    const alias = registryMetadata.migrationAliases.find((item) => item.from === value);
    if (alias) { return alias.to; }
    const format = this.listFormats().find((item: RegistryFormat) => item.id === value || item.extensions.includes(value));
    return format ? format.id : value;
  }

  isBlocked(format: string): boolean {
    return registryMetadata.blockedFormats.includes(format.trim().toLowerCase().replace(/^\./, ''));
  }

  availableRoutes(capabilities: CapabilityMatrix): ConversionRouteDefinition[] {
    if (!this.ready) { return []; }
    return this.listPlannedRoutes().filter((route: ConversionRouteDefinition) => {
      const actual = capabilities.routes.find((item) => item.routeId === route.id);
      return route.status === 'available' && actual !== undefined && actual.availability === 'available' &&
        actual.releaseEvidenceId !== undefined && actual.releaseEvidenceId.length > 0;
    });
  }
}

// Compatibility entry point; all operational state belongs to an injectable instance.
export class FormatRegistry {
  private static defaultService: FormatRegistryPort = new FormatRegistryService();
  static shared(): FormatRegistryPort { return FormatRegistry.defaultService; }
  static useDefault(service: FormatRegistryPort): void { FormatRegistry.defaultService = service; }
  static catalogueVersion(): number { return FormatRegistry.shared().catalogueVersion(); }
  static isInitialized(): boolean { return FormatRegistry.shared().isInitialized(); }
  static initialize(resources: BundledResourceReader): Promise<void> { return FormatRegistry.shared().initialize(resources); }
  static verifyBundledResources(resources: BundledResourceReader): Promise<void> { return FormatRegistry.shared().verifyBundledResources(resources); }
  static listFormats(category?: string): RegistryFormat[] { return FormatRegistry.shared().listFormats(category); }
  static listPlannedRoutes(): ConversionRouteDefinition[] { return FormatRegistry.shared().listPlannedRoutes(); }
  static normalizeFormat(id: string): string { return FormatRegistry.shared().normalizeFormat(id); }
  static isBlocked(format: string): boolean { return FormatRegistry.shared().isBlocked(format); }
  static availableRoutes(capabilities: CapabilityMatrix): ConversionRouteDefinition[] { return FormatRegistry.shared().availableRoutes(capabilities); }
}
