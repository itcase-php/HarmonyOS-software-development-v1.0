import { AppError, ErrorCode, Stage } from '../models/NativeProtocol';

export class BridgeError extends Error implements AppError {
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
    this.traceId = `bridge-${Date.now()}`;
    this.messageKey = `errors.${code}`;
  }
}
