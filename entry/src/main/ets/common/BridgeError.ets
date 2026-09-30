import { AppError, ErrorCode, Stage } from '../models/NativeProtocol';
import { util } from '@kit.ArkTS';

export class BridgeError extends Error implements AppError {
  private static fallbackSequence: number = 0;
  code: ErrorCode;
  reason: string;
  module: string = 'NativeBridge';
  stage: Stage = 'preparing';
  retryable: boolean = false;
  traceId: string;
  messageKey: string;

  constructor(code: ErrorCode, reason: string) {
    super(`errors.${code}`);
    this.name = 'BridgeError';
    this.code = code;
    this.reason = reason;
    try { this.traceId = util.generateRandomUUID(false); }
    catch (error) { this.traceId = `bridge-${Date.now()}-${++BridgeError.fallbackSequence}`; }
    this.messageKey = `errors.${code}`;
  }
}
