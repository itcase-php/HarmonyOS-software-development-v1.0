import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { i18n } from '@kit.LocalizationKit';
import { languageCatalog, LanguageEntry } from '../generated/LanguageCatalog';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';

export type AppLanguage = 'zh' | 'en';
interface LanguageListener { token: number; callback: () => void; }

// AppStorage drives ArkUI; PersistentStorage retains the user's choice across launches.
// A resource-only fallback also works when Previewer has no host ResourceManager.
export class LanguageManager {
  private static initialized: boolean = false;
  private static context: common.Context | undefined = undefined;
  private static ready: boolean = false;
  private static managers: Map<AppLanguage, resourceManager.ResourceManager> = new Map();
  private static listeners: LanguageListener[] = [];
  private static nextToken: number = 0;

  static initialize(): void {
    if (LanguageManager.initialized) { return; }
    LanguageManager.initialized = true;
    let initial: AppLanguage = 'zh';
    try { initial = i18n.System.getSystemLanguage().toLowerCase().startsWith('zh') ? 'zh' : 'en'; } catch (_) {}
    try { PersistentStorage.persistProp('appLanguage', initial); } catch (_) {}
    const stored = AppStorage.get<string>('appLanguage');
    if (stored !== 'zh' && stored !== 'en') { AppStorage.setOrCreate('appLanguage', initial); }
  }

  static get currentLanguage(): AppLanguage {
    LanguageManager.initialize();
    return AppStorage.get<string>('appLanguage') === 'en' ? 'en' : 'zh';
  }
  static get currentLocale(): string { return LanguageManager.currentLanguage === 'zh' ? 'zh_CN' : 'en_US'; }
  static bind(context: common.Context | undefined): void {
    if (context && LanguageManager.context !== context) {
      LanguageManager.context = context; LanguageManager.managers.clear();
    }
    LanguageManager.initialize();
  }
  static windowReady(): void { LanguageManager.ready = true; LanguageManager.applyLanguage(); }
  private static applyLanguage(): void {
    if (!LanguageManager.ready) { return; }
    try { LanguageManager.context?.getApplicationContext().setLanguage(LanguageManager.currentLocale.replace('_', '-')); } catch (_) {}
  }
  static setLanguage(language: AppLanguage): void {
    if (LanguageManager.currentLanguage === language) { return; }
    AppStorage.setOrCreate('appLanguage', language);
    LanguageManager.applyLanguage();
    const callbacks = LanguageManager.listeners.slice();
    callbacks.forEach((listener: LanguageListener) => { listener.callback(); });
  }
  static toggle(): void { LanguageManager.setLanguage(LanguageManager.currentLanguage === 'zh' ? 'en' : 'zh'); }
  static subscribe(callback: () => void): number {
    const token = ++LanguageManager.nextToken;
    LanguageManager.listeners.push({ token: token, callback: callback }); return token;
  }
  static unsubscribe(token: number): void {
    LanguageManager.listeners = LanguageManager.listeners.filter((listener: LanguageListener) => listener.token !== token);
  }
  private static manager(language: AppLanguage): resourceManager.ResourceManager | undefined {
    const cached = LanguageManager.managers.get(language);
    if (cached) { return cached; }
    try {
      const host = LanguageManager.context?.resourceManager;
      if (!host) { return undefined; }
      const config = host.getOverrideConfiguration();
      config.locale = language === 'zh' ? 'zh_CN' : 'en_US';
      const manager = host.getOverrideResourceManager(config);
      LanguageManager.managers.set(language, manager); return manager;
    } catch (_) { return undefined; }
  }
  static getString(resource: ResourceStr, args: (string | number)[] = [],
    language: AppLanguage = LanguageManager.currentLanguage): string {
    let name: string = ''; let values: (string | number)[] = args;
    if (typeof resource === 'string') { name = resource.replace('app.string.', ''); }
    else {
      name = resource.params && typeof resource.params[0] === 'string' ?
        (resource.params[0] as string).replace('app.string.', '') : '';
      if (args.length === 0 && resource.params) {
        values = resource.params.slice(1).filter((value: string | number) =>
          typeof value === 'string' || typeof value === 'number') as (string | number)[];
      }
    }
    const entry = languageCatalog.find((item: LanguageEntry) => item.name === name);
    // Already formatted labels and user filenames pass through unchanged.
    if (!entry && typeof resource === 'string') { return resource; }
    try {
      const manager = LanguageManager.manager(language);
      if (manager) { return typeof resource === 'string' ? manager.getStringByNameSync(name, ...values) :
        manager.getStringSync(resource.id, ...values); }
    } catch (_) {}
    let index: number = 0;
    const template = entry ? language === 'zh' ? entry.zh : entry.en : name;
    return template.replace(/%%|%[sd]/g, (match: string): string => {
      if (match === '%%') { return '%'; }
      const value = values[index++]; return value === undefined ? match : value.toString();
    });
  }
  static tier(tier: FidelityTier): string {
    return LanguageManager.getString(tier === 'extreme' ? 'fidelity_extreme' :
      tier === 'standard' ? 'fidelity_standard' : 'fidelity_compatible');
  }
  static intent(intent: Intent): string {
    return LanguageManager.getString(intent === 'layout_preserved' ? 'intent_layout' :
      intent === 'structured_rebuild' ? 'intent_structure' : 'intent_content');
  }
  static quality(mode: QualityMode): string {
    return LanguageManager.getString(mode === 'fast' ? 'quality_fast' : mode === 'balanced' ? 'quality_balanced' : 'quality_high');
  }
  static operation(value: string): string {
    return LanguageManager.getString('operation_' + value).replace('operation_', '');
  }
  static formatName(id: string, fallback: string): string {
    const key = 'format_' + id;
    return languageCatalog.some((item: LanguageEntry) => item.name === key) ? LanguageManager.getString(key) : fallback;
  }
  static stage(key: string, args: (string | number)[], language: AppLanguage = LanguageManager.currentLanguage): string {
    const translated = key === 'native_stage' ? args.map((value: string | number): string | number =>
      typeof value === 'string' ? languageCatalog.some((item: LanguageEntry) => item.name === value) ?
        LanguageManager.getString(value, [], language) : value.replace('native_', '') : value) : args;
    return LanguageManager.getString(key, translated, language);
  }
  static detail(value: string): string {
    const key = 'degradation_' + value;
    return languageCatalog.some((item: LanguageEntry) => item.name === key) ? LanguageManager.getString(key) :
      LanguageManager.getString(value);
  }
}

LanguageManager.initialize();
