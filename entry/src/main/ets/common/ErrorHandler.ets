import { LanguageManager } from './LanguageManager';
import { BridgeError } from './BridgeError';
import { AppError, ErrorCode } from '../models/NativeProtocol';

export interface ErrorReporter { report(error: AppError, context: string): void; }

export function isBridgeError(error: Error): boolean { return error instanceof BridgeError; }

// Diagnostics contain codes and trace IDs, never raw SDK messages, file names or URIs.
export class ErrorHandler {
  private static reporter: ErrorReporter | null = null;
  static setReporter(reporter: ErrorReporter | null): void { ErrorHandler.reporter = reporter; }
  static catchBridge(error: Error, context: string = 'Unhandled',
    code: ErrorCode = 'INTERNAL_ERROR', reason: string = 'UNEXPECTED_FAILURE'): BridgeError {
    const failure: BridgeError = error instanceof BridgeError ? error : new BridgeError(code, reason);
    console.error(JSON.stringify({ context: context, code: failure.code, reason: failure.reason, traceId: failure.traceId }));
    if (ErrorHandler.reporter) {
      try { ErrorHandler.reporter.report(failure, context); }
      catch (reportError) { ErrorHandler.swallow('ErrorReporter', reportError); }
    }
    return failure;
  }
  static swallow(context: string, error: Error): void {
    const failure: BridgeError = error instanceof BridgeError ? error : new BridgeError('INTERNAL_ERROR', 'OPTIONAL_ACTION_FAILED');
    console.debug(JSON.stringify({ context: context, code: failure.code, traceId: failure.traceId }));
  }
  static toast(context: UIContext, error: Error, message: string = LanguageManager.getString('action_failed')): void {
    ErrorHandler.catchBridge(error, 'UserAction');
    try { context.getPromptAction().showToast({ message: message, duration: 2000 }); }
    catch (toastError) { ErrorHandler.swallow('Toast', toastError); }
  }
}
