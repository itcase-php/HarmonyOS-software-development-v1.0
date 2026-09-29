import { ConverterNavigationParams } from '../models/InteractionModels';

export class UiFeedback {
  static toast(context: UIContext, message: string): void {
    try { context.getPromptAction().showToast({ message: message, duration: 2000 }); }
    catch (_) { return; }
  }

  static async open(context: UIContext, url: string, params?: ConverterNavigationParams): Promise<void> {
    try { await context.getRouter().pushUrl({ url: url, params: params }); }
    catch (_) { UiFeedback.toast(context, '页面跳转失败；预览时可单独选择对应页面查看'); }
  }

  static back(context: UIContext): void {
    try { context.getRouter().back(); }
    catch (_) { UiFeedback.toast(context, '当前没有可返回的页面'); }
  }
}
