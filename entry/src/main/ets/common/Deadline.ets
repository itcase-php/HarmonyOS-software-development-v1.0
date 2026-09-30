import { TaskRuntime } from '../models/InteractionModels';
import { BridgeError } from './BridgeError';

export class SystemRuntime implements TaskRuntime {
  now(): number { return Date.now(); }
  setTimeout(callback: () => void, delayMs: number): number { return setTimeout(callback, delayMs); }
  clearTimeout(id: number): void { clearTimeout(id); }
}

// A deadline bounds the caller's wait. It does not claim to abort an SDK/NAPI operation.
export async function withDeadline<T>(operation: Promise<T>, timeoutMs: number,
  failure: () => BridgeError, runtime: TaskRuntime = new SystemRuntime()): Promise<T> {
  let timer: number = -1;
  const deadline: Promise<T> = new Promise<T>((resolve, reject) => {
    timer = runtime.setTimeout(() => { reject(failure()); }, timeoutMs);
  });
  try { return await Promise.race([operation, deadline]); }
  finally { if (timer !== -1) { runtime.clearTimeout(timer); } }
}
