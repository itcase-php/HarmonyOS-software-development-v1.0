import { describe, it, expect, beforeAll, beforeEach, afterEach } from '@ohos/hypium';
import { initializeRegistry, ManualTaskRuntime } from '../ohosTest/ets/test/CoreFixtures';
import { FidelityPolicy } from '../main/ets/viewmodel/FidelityPolicy';
import { ConversionPlanner } from '../main/ets/viewmodel/ConversionPlanner';
import { TaskStore } from '../main/ets/viewmodel/TaskStore';
import { FormatRegistry } from '../main/ets/services/FormatRegistry';
import { ConversionRouteDefinition } from '../main/ets/models/RegistryTypes';
import { BridgeError } from '../main/ets/common/BridgeError';
import { FidelitySelection } from '../main/ets/models/InteractionModels';

function route(id: string): ConversionRouteDefinition {
  const result = FormatRegistry.listPlannedRoutes().find((item: ConversionRouteDefinition) => item.id === id);
  if (!result) { throw new Error('Missing test route'); }
  return result;
}

// Hypium uses describe()/it(), rather than decorator syntax.
export default function conversionCoreTest() {
  describe('ConversionCore', () => {
    let runtime: ManualTaskRuntime = new ManualTaskRuntime();
    let store: TaskStore = new TaskStore(runtime);
    beforeAll(initializeRegistry);
    beforeEach(() => { runtime = new ManualTaskRuntime(); store = new TaskStore(runtime); });
    afterEach(() => { store.shutdown(); });

    it('qualityDurations', 0, () => {
      expect(FidelityPolicy.durationMs('fast')).assertEqual(2000);
      expect(FidelityPolicy.durationMs('balanced')).assertEqual(3500);
      expect(FidelityPolicy.durationMs('high_fidelity')).assertEqual(6000);
    });
    it('matchingTierAndIntent', 0, () => {
      FidelityPolicy.validate(route('pdf-png'), { qualityMode: 'balanced',
        requestedIntent: 'layout_preserved', requestedTier: 'standard' });
      FidelityPolicy.validate(route('pdf-png'), { qualityMode: 'high_fidelity',
        requestedIntent: 'layout_preserved', requestedTier: 'compatible' });
    });
    it('tierAboveRouteIsRejected', 0, () => {
      let reason = '';
      try {
        FidelityPolicy.validate(route('pdf-png'), { qualityMode: 'high_fidelity',
          requestedIntent: 'layout_preserved', requestedTier: 'extreme' });
      } catch (error) { reason = (error as BridgeError).reason; }
      expect(reason).assertEqual('FIDELITY_TIER_UNAVAILABLE');
    });
    it('intentMismatchIsRejected', 0, () => {
      let reason = '';
      try {
        FidelityPolicy.validate(route('pdf-docx'), { qualityMode: 'balanced',
          requestedIntent: 'layout_preserved', requestedTier: 'compatible' });
      } catch (error) { reason = (error as BridgeError).reason; }
      expect(reason).assertEqual('FIDELITY_INTENT_MISMATCH');
    });
    it('invalidEnumFromBoundaryIsRejected', 0, () => {
      const invalid = JSON.parse('{"qualityMode":"turbo","requestedIntent":"layout_preserved","requestedTier":"standard"}') as FidelitySelection;
      let reason = '';
      try { FidelityPolicy.validate(route('pdf-png'), invalid); }
      catch (error) { reason = (error as BridgeError).reason; }
      expect(reason).assertEqual('FIDELITY_OPTIONS_INVALID');
    });
    it('targetAliasesAndUnknownInput', 0, () => {
      const jpg = ConversionPlanner.targets('.JPG').map((item) => item.id).join(',');
      const jpeg = ConversionPlanner.targets('jpeg').map((item) => item.id).join(',');
      expect(jpg).assertEqual(jpeg);
      expect(jpg.length > 0).assertTrue();
      expect(ConversionPlanner.targets('unknown-test-format').length).assertEqual(0);
    });
    it('plannerKeepsIntentAndMinimum', 0, () => {
      const result = ConversionPlanner.bestRoute('pdf', 'pptx', 'layout_preserved', 'high_fidelity', 'standard');
      expect(result?.id).assertEqual('pdf-pptx-visual');
      expect(ConversionPlanner.bestRoute('pdf', 'png', 'layout_preserved', 'fast', 'extreme')).assertUndefined();
    });
    it('advanceReportsAtCommitAndCompletes', 0, () => {
      const task = store.enqueue('sample.pdf', 'pdf', 'png', 'pdf-png');
      store.advance(runtime.now());
      store.advance(task.createdAtMs + 2974);
      expect(store.snapshot()[0].fidelityReport).assertUndefined();
      store.advance(task.createdAtMs + 2975);
      expect(store.snapshot()[0].progress).assertEqual(85);
      expect(store.snapshot()[0].fidelityReport?.detectorVersion).assertEqual('demo-fidelity-v1');
      store.advance(task.createdAtMs + 3500);
      expect(store.snapshot()[0].status).assertEqual('completed');
      expect(store.snapshot()[0].achievedTier).assertEqual('standard');
    });
    it('advancePromotesOnlyNextFifoTask', 0, () => {
      const first = store.enqueue('first.pdf', 'pdf', 'png', 'pdf-png');
      store.advance(runtime.now());
      const second = store.enqueue('second.pdf', 'pdf', 'png', 'pdf-png');
      expect(second.status).assertEqual('queued');
      store.advance(first.createdAtMs + 3500);
      expect(store.snapshot().find((item) => item.id === first.id)?.status).assertEqual('completed');
      expect(store.snapshot().find((item) => item.id === second.id)?.status).assertEqual('running');
      expect(store.snapshot().filter((item) => item.status === 'running').length).assertEqual(1);
    });
    it('cancelCannotBecomeCompleted', 0, () => {
      const task = store.enqueue('cancel.pdf', 'pdf', 'png', 'pdf-png');
      store.advance(runtime.now());
      expect(store.cancel(task.id)).assertTrue();
      store.advance(task.createdAtMs + 10000);
      expect(store.snapshot()[0].status).assertEqual('cancelled');
      expect(store.snapshot()[0].fidelityReport).assertUndefined();
    });
    it('pauseFreezesAdvanceAndResumeCompletes', 0, () => {
      const task = store.enqueue('pause.pdf', 'pdf', 'png', 'pdf-png');
      store.advance(runtime.now());
      store.advance(task.createdAtMs + 500);
      expect(store.pause(task.id)).assertTrue();
      const paused = store.snapshot()[0];
      store.advance(task.createdAtMs + 9000);
      expect(store.snapshot()[0].status).assertEqual('paused');
      expect(store.snapshot()[0].elapsedMs).assertEqual(paused.elapsedMs);
      expect(store.resume(task.id)).assertTrue();
      store.advance(runtime.now() + 3000);
      expect(store.snapshot()[0].status).assertEqual('completed');
    });
    it('cloneIsolatesNestedReport', 0, () => {
      const task = store.enqueue('copy.pdf', 'pdf', 'png', 'pdf-png');
      store.advance(runtime.now());
      store.advance(task.createdAtMs + 3500);
      const first = store.snapshot()[0];
      const copy = first.clone();
      if (copy.fidelityReport) { copy.fidelityReport.metrics[0].evidenceRefs.push('test-only'); }
      expect(first.fidelityReport?.metrics[0].evidenceRefs.length).assertEqual(0);
      expect(store.snapshot()[0].fidelityReport?.metrics[0].evidenceRefs.length).assertEqual(0);
    });
  });
}
