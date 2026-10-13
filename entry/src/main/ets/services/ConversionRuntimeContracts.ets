import { ConvertResult, NativeModule, ResourceBudget } from '../models/NativeProtocol';
export interface ConversionRuntimePort {
  prepareOffice(): Promise<void>;
  verifyPdf(result: ConvertResult, native: NativeModule, budget: ResourceBudget, sourceFormatId?: string): Promise<void>;
}
