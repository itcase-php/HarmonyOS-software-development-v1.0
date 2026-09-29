import { RegistryFormat } from '../models/RegistryTypes';
import { FormatRegistry } from './FormatRegistry';

// An extension/MIME hint, never proof of content or absence of protection.
export class FormatDetector {
  static detect(fileName: string, mimeType: string): string {
    return FormatDetector.detectByExtension(fileName) ?? FormatDetector.detectByMime(mimeType) ?? '';
  }

  static detectByExtension(fileName: string): string | null {
    const name: string = fileName.trim();
    const dot: number = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) { return null; }
    const extension: string = name.substring(dot + 1).toLowerCase();
    const format: RegistryFormat | undefined = FormatRegistry.listFormats().find((item: RegistryFormat) =>
      item.extensions.includes(extension));
    return format ? format.id : null;
  }

  static detectByMime(mimeType: string): string | null {
    const mime: string = mimeType.split(';')[0].trim().toLowerCase();
    if (mime.length === 0) { return null; }
    const format: RegistryFormat | undefined = FormatRegistry.listFormats().find((item: RegistryFormat) =>
      item.mimeTypes.some((value: string) => value.toLowerCase() === mime));
    return format ? format.id : null;
  }
}
