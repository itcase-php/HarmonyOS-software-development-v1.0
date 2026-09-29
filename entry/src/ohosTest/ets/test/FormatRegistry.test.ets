import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { FormatRegistry } from '../../../main/ets/services/FormatRegistry';
import { BundledResourceReader } from '../../../main/ets/models/RegistryTypes';
import { BridgeError } from '../../../main/ets/common/BridgeError';
import { initializeRegistry } from './CoreFixtures';

class FixtureResources implements BundledResourceReader {
  private formats: Uint8Array;
  private matrix: Uint8Array;
  private fail: boolean;
  constructor(formats: Uint8Array, matrix: Uint8Array, fail: boolean = false) {
    this.formats = formats; this.matrix = matrix; this.fail = fail;
  }
  async getRawFileContent(path: string): Promise<Uint8Array> {
    if (this.fail) { throw new Error('resource fixture failure'); }
    return path.endsWith('/formats.json') ? this.formats : this.matrix;
  }
}

async function rejection(resources: BundledResourceReader): Promise<string> {
  try { await FormatRegistry.verifyBundledResources(resources); }
  catch (error) { expect(error instanceof BridgeError).assertTrue(); return (error as BridgeError).reason; }
  return '';
}

export default function formatRegistryTest() {
  describe('FormatRegistry', () => {
    let formats: Uint8Array = new Uint8Array();
    let matrix: Uint8Array = new Uint8Array();
    beforeAll(async () => {
      await initializeRegistry();
      const resources = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().resourceManager;
      formats = await resources.getRawFileContent('format-registry/formats.json');
      matrix = await resources.getRawFileContent('format-registry/conversion-matrix.json');
    });
    it('accepts exactly the generated rawfile documents', 0, async () => {
      await FormatRegistry.verifyBundledResources(new FixtureResources(formats, matrix));
      expect(FormatRegistry.listFormats().length).assertEqual(18);
      expect(FormatRegistry.listPlannedRoutes().length).assertEqual(43);
    });
    it('rejects a nonempty modified formats document', 0, async () => {
      const changed = formats.slice(); changed[changed.length - 1] ^= 1;
      expect(await rejection(new FixtureResources(changed, matrix))).assertEqual('BUNDLED_RESOURCE_HASH_MISMATCH');
    });
    it('rejects a nonempty modified matrix document', 0, async () => {
      const changed = matrix.slice(); changed[changed.length - 1] ^= 1;
      expect(await rejection(new FixtureResources(formats, changed))).assertEqual('BUNDLED_RESOURCE_HASH_MISMATCH');
    });
    it('rejects empty or oversized documents before decoding', 0, async () => {
      expect(await rejection(new FixtureResources(new Uint8Array(), matrix))).assertEqual('BUNDLED_RESOURCE_EMPTY');
      expect(await rejection(new FixtureResources(formats, new Uint8Array(2 * 1024 * 1024 + 1)))).assertEqual('BUNDLED_RESOURCE_TOO_LARGE');
    });
    it('normalizes resource read failures and keeps the current snapshot intact', 0, async () => {
      expect(await rejection(new FixtureResources(formats, matrix, true))).assertEqual('BUNDLED_RESOURCE_READ_FAILED');
      expect(FormatRegistry.isInitialized()).assertTrue(); expect(FormatRegistry.listFormats().length).assertEqual(18);
    });
    it('returns deep snapshots so callers cannot alter future planning', 0, () => {
      const formatsCopy = FormatRegistry.listFormats(); formatsCopy[0].extensions.push('fixture-mutation');
      const routesCopy = FormatRegistry.listPlannedRoutes(); routesCopy[0].steps[0].executorEngineId = 'fixture-mutation';
      expect(FormatRegistry.listFormats()[0].extensions.includes('fixture-mutation')).assertFalse();
      expect(FormatRegistry.listPlannedRoutes()[0].steps[0].executorEngineId === 'fixture-mutation').assertFalse();
    });
  });
}
