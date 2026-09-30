import { RegistryFormat } from '../models/RegistryTypes';
import { FormatRegistry } from './FormatRegistry';
import { FormatRegistryPort } from './ServiceContracts';

// An extension/MIME hint, never proof of content or absence of protection.
export class FormatDetectorIndex {
  private registry: FormatRegistryPort;
  private revision: number = -1;
  private extensions: Map<string, string> = new Map<string, string>();
  private mimeTypes: Map<string, string> = new Map<string, string>();
  constructor(registry: FormatRegistryPort) { this.registry = registry; }
  private ensureIndex(): void {
    const version: number = this.registry.catalogueVersion();
    if (this.revision === version) { return; }
    this.extensions.clear(); this.mimeTypes.clear();
    for (const format of this.registry.listFormats()) {
      for (const extension of format.extensions) {
        const key: string = extension.toLowerCase();
        if (!this.extensions.has(key)) { this.extensions.set(key, format.id); }
      }
      for (const mime of format.mimeTypes) {
        const key: string = mime.toLowerCase();
        if (!this.mimeTypes.has(key)) { this.mimeTypes.set(key, format.id); }
      }
    }
    this.revision = version;
  }
  detect(fileName: string, mimeType: string): string {
    return this.detectByExtension(fileName) ?? this.detectByMime(mimeType) ?? '';
  }

  detectByExtension(fileName: string): string | null {
    const name: string = fileName.trim();
    const dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) { return null; }
    const extension: string = name.substring(dot + 1).toLowerCase();
    this.ensureIndex();
    return this.extensions.get(extension) ?? null;
  }

  detectByMime(mimeType: string): string | null {
    const mime: string = mimeType.split(';')[0].trim().toLowerCase();
    if (mime.length === 0) { return null; }
    this.ensureIndex();
    return this.mimeTypes.get(mime) ?? null;
  }
}

export class FormatDetector {
  private static registry: FormatRegistryPort = FormatRegistry.shared();
  private static index: FormatDetectorIndex = new FormatDetectorIndex(FormatDetector.registry);
  private static current(): FormatDetectorIndex {
    const registry: FormatRegistryPort = FormatRegistry.shared();
    if (registry !== FormatDetector.registry) {
      FormatDetector.registry = registry; FormatDetector.index = new FormatDetectorIndex(registry);
    }
    return FormatDetector.index;
  }
  static detect(name: string, mime: string): string { return FormatDetector.current().detect(name, mime); }
  static detectByExtension(name: string): string | null { return FormatDetector.current().detectByExtension(name); }
  static detectByMime(mime: string): string | null { return FormatDetector.current().detectByMime(mime); }
}
