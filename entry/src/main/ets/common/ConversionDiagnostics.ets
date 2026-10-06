import { hilog } from '@kit.PerformanceAnalysisKit';
import { BridgeError } from './BridgeError';

export class ConversionDiagnostics {
  static stage(module: string, stage: string, routeId: string = '', code: string = 'OK', traceId: string = ''): void {
    hilog.info(0x0000, 'DocumentConverter',
      'module=%{public}s stage=%{public}s route=%{public}s code=%{public}s trace=%{public}s',
      module, stage, routeId, code, traceId);
  }
  static failure(module: string, stage: string, routeId: string, error: BridgeError): void {
    hilog.warn(0x0000, 'DocumentConverter',
      'module=%{public}s stage=%{public}s route=%{public}s code=%{public}s reason=%{public}s trace=%{public}s',
      module, stage, routeId, error.code, error.reason, error.traceId);
  }
}
