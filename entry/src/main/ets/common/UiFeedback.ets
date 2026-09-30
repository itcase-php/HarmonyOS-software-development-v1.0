import { ConverterNavigationParams } from '../models/InteractionModels';
import { ErrorHandler } from './ErrorHandler';

export class UiFeedback {
  static toast(context: UIContext, message: string): void {
    try { context.getPromptAction().showToast({ message: message, duration: 2000 }); }
    catch (error) { ErrorHandler.swallow('UiFeedback.toast', error); }
  }

  static async open(context: UIContext, url: string, params?: ConverterNavigationParams): Promise<void> {
    try { await context.getRouter().pushUrl({ url: url, params: params }); }
    catch (error) { ErrorHandler.toast(context, error, '页面跳转失败；预览时可单独选择对应页面查看'); }
  }

  static back(context: UIContext): void {
    try { context.getRouter().back(); }
    catch (error) { ErrorHandler.toast(context, error, '当前没有可返回的页面'); }
  }
}
