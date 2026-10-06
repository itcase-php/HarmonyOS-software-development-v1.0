import { BridgeError } from '../common/BridgeError';
import { SystemRuntime, withDeadline } from '../common/Deadline';
import { registryMetadata } from '../generated/RegistryData';
import { TaskRuntime } from '../models/InteractionModels';
import { FormatRegistryPort, NativeBridgePort } from './ServiceContracts';
import { FormatRegistry } from './FormatRegistry';
import { NativeBridge } from './NativeBridge';

// Capability queries do not grant access to files or register a conversion session.
export class RealTaskPreflight {
  private registry: FormatRegistryPort;
  private native: NativeBridgePort;
  private runtime: TaskRuntime;
  constructor(registry: FormatRegistryPort = FormatRegistry.shared(),
    native: NativeBridgePort = NativeBridge.shared(), runtime: TaskRuntime = new SystemRuntime()) {
    this.registry = registry; this.native = native; this.runtime = runtime;
  }

  async inspect(routeId: string, sourceId: string, targetId: string): Promise<void> {
    if (!this.registry.isInitialized()) { throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_NOT_READY'); }
    const route = this.registry.listPlannedRoutes().find((item) => item.id === routeId);
    if (!route || !route.from.includes(sourceId) || route.to !== targetId ||
      route.inputConstraints.minInputs > 1 || route.inputConstraints.maxInputs < 1) {
      throw new BridgeError('INVALID_REQUEST', 'NATIVE_ROUTE_REQUEST');
    }
    // Propagate loader/protocol failures; the dashboard's demo fallback is inappropriate here.
    const capabilities = await withDeadline(this.native.getCapabilities({ schemaVersion: registryMetadata.schemaVersion,
      sessionId: 'capability-only-bootstrap', configVersion: registryMetadata.configVersion }), 5000,
      () => new BridgeError('CONVERSION_TIMEOUT', 'CAPABILITY_CHECK_TIMEOUT'), this.runtime);
    if (route.steps.some((step) => !capabilities.engines.some((engine) =>
      engine.engineId === step.executorEngineId && engine.version.length > 0 && /^[a-f0-9]{64}$/.test(engine.buildHash)))) {
      throw new BridgeError('ENGINE_MISSING', 'NATIVE_ENGINE_UNAVAILABLE');
    }
    if (!this.registry.availableRoutes(capabilities).some((item) => item.id === route.id)) {
      throw new BridgeError('ENGINE_MISSING', 'NATIVE_ROUTE_UNAVAILABLE');
    }
  }
}
