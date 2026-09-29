// Preserve the DevEco template module name and legacy add export.
export * from './Protocol';
import { NativeModule } from './Protocol';
export interface EntryNativeModule extends NativeModule {
  add(a: number, b: number): number;
}
export const add: (a: number, b: number) => number;
declare const entryNativeModule: EntryNativeModule;
export default entryNativeModule;
