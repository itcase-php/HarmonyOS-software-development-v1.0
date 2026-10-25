import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { ServiceContainer } from '../services/ServiceContainer';
import { UiFeedback } from '../common/UiFeedback';

@Component
export struct FontFallbackRetry {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  @Consume('services') services: ServiceContainer;
  taskId: string = '';
  onRetried: (taskId: string) => void = () => {};
  @State private busy: boolean = false;
  private tr(key: string): string { return LanguageManager.getString(key, [], this.language); }
  private confirm(): void {
    this.getUIContext().showAlertDialog({ title: this.tr('input_font_retry'), message: this.tr('input_font_approval'),
      primaryButton: { value: this.tr('back_edit'), action: () => {} },
      secondaryButton: { value: this.tr('input_font_retry_confirm'), action: () => { this.retry(); } } });
  }
  private async retry(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try { const task = await this.services.tasks.retryFontFallback(this.taskId, true); this.onRetried(task.id); }
    catch (error) { UiFeedback.toast(this.getUIContext(), this.tr('input_font_retry_failed')); }
    finally { this.busy = false; }
  }
  build() {
    if (this.services.tasks.canRetryFontFallback(this.taskId)) {
      Button(this.tr('input_font_retry')).enabled(!this.busy).onClick(() => { this.confirm(); })
    }
  }
}
