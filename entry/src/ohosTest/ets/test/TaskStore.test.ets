import { describe, it, expect, beforeAll, beforeEach, afterEach } from '@ohos/hypium';
import { TaskStore } from '../../../main/ets/viewmodel/TaskStore';
import { initializeRegistry, ManualTaskRuntime } from './CoreFixtures';

export default function taskStoreTest() {
  describe('TaskStore', () => {
    let runtime: ManualTaskRuntime = new ManualTaskRuntime();
    let store: TaskStore = new TaskStore(runtime);
    beforeAll(initializeRegistry);
    beforeEach(() => { runtime = new ManualTaskRuntime(); store = new TaskStore(runtime); });
    afterEach(() => { store.shutdown(); expect(runtime.timerCount()).assertEqual(0); });

    it('returns a queued zero-progress task before the first 50 ms tick', 0, () => {
      const task = store.enqueue('sample.pdf', 'pdf', 'png', 'pdf-png');
      expect(task.status).assertEqual('queued'); expect(task.progress).assertEqual(0); expect(task.stage.length > 0).assertTrue();
      runtime.tick(49); expect(store.snapshot()[0].status).assertEqual('queued');
      runtime.tick(1); expect(store.snapshot()[0].status).assertEqual('running');
      expect(store.snapshot()[0].progress).assertEqual(0);
    });
    it('advances elapsed time and progress monotonically until completion', 0, () => {
      store.enqueue('sample.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(50);
      let previous = 0;
      for (let index = 0; index < 18; index++) {
        runtime.tick(200); const task = store.snapshot()[0];
        expect(task.progress >= previous).assertTrue(); previous = task.progress;
      }
      expect(store.snapshot()[0].elapsedMs > 0).assertTrue(); expect(store.snapshot()[0].progress).assertEqual(100);
      expect(store.snapshot()[0].status).assertEqual('completed'); expect(runtime.timerCount()).assertEqual(0);
    });
    it('completes three queued tasks in FIFO order with one timer', 0, () => {
      const first = store.enqueue('first.pdf', 'pdf', 'png', 'pdf-png');
      const second = store.enqueue('second.pdf', 'pdf', 'png', 'pdf-png');
      const third = store.enqueue('third.pdf', 'pdf', 'png', 'pdf-png');
      expect(runtime.timerCount()).assertEqual(1); runtime.tick(50);
      expect(store.snapshot().find((task) => task.id === first.id)?.status).assertEqual('running');
      expect(store.snapshot().find((task) => task.id === second.id)?.status).assertEqual('queued');
      runtime.tick(3600); expect(store.snapshot().find((task) => task.id === second.id)?.status).assertEqual('running');
      runtime.tick(3600); expect(store.snapshot().find((task) => task.id === third.id)?.status).assertEqual('running');
      runtime.tick(3600); expect(store.snapshot().every((task) => task.status === 'completed')).assertTrue();
      expect(runtime.timerCount()).assertEqual(0);
    });
    it('stops timers while paused and resumes without counting paused time', 0, () => {
      const task = store.enqueue('pause.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(1050);
      expect(store.pause(task.id)).assertTrue(); const elapsed = store.snapshot()[0].elapsedMs;
      expect(runtime.timerCount()).assertEqual(0); runtime.tick(5000); store.advance(runtime.now());
      expect(store.snapshot()[0].elapsedMs).assertEqual(elapsed); expect(store.snapshot()[0].status).assertEqual('paused');
      expect(store.resume(task.id)).assertTrue(); expect(runtime.timerCount()).assertEqual(1);
      runtime.tick(200); expect(store.snapshot()[0].elapsedMs > elapsed).assertTrue();
    });
    it('keeps cancellation terminal across later ticks and resume attempts', 0, () => {
      const task = store.enqueue('cancel.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(3050);
      expect(store.cancel(task.id)).assertTrue(); runtime.tick(10000); store.advance(runtime.now());
      expect(store.snapshot()[0].status).assertEqual('cancelled'); expect(store.snapshot()[0].fidelityReport).assertUndefined();
      expect(store.resume(task.id)).assertFalse(); expect(runtime.timerCount()).assertEqual(0);
    });
    it('clears finished history while retaining queued running and paused tasks', 0, () => {
      const done = store.enqueue('done.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(3650);
      const paused = store.enqueue('paused.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(50); store.pause(paused.id);
      store.enqueue('running.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(50);
      store.enqueue('queued.pdf', 'pdf', 'png', 'pdf-png');
      expect(store.clearFinished()).assertEqual(1); expect(store.snapshot().some((task) => task.id === done.id)).assertFalse();
      expect(store.snapshot().length).assertEqual(3);
    });
    it('isolates task fields and nested reports in returned snapshots', 0, () => {
      const task = store.enqueue('copy.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(3650);
      const copy = store.snapshot()[0]; expect(copy.id).assertEqual(task.id); copy.fileName = 'changed';
      if (copy.fidelityReport) { copy.fidelityReport.metrics[0].value = 0; copy.fidelityReport.degradations.push('changed'); }
      expect(store.snapshot()[0].fileName).assertEqual('copy.pdf');
      expect(store.snapshot()[0].fidelityReport?.metrics[0].value).assertEqual(0.90);
      expect(store.snapshot()[0].fidelityReport?.degradations.includes('changed')).assertFalse();
    });
    it('ignores reentrant observer advances and remains usable after an observer throws', 0, () => {
      store.subscribe(() => { store.advance(runtime.now()); throw new Error('observer fixture'); });
      store.enqueue('reentrant.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(3650);
      expect(store.snapshot()[0].status).assertEqual('completed'); expect(runtime.timerCount()).assertEqual(0);
    });
    it('does not count the same timestamp twice or move the clock backwards', 0, () => {
      store.enqueue('clock.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(50);
      const started = runtime.now(); store.advance(started + 500); const elapsed = store.snapshot()[0].elapsedMs;
      store.advance(started + 500); store.advance(started + 100); store.advance(started + 600);
      expect(store.snapshot()[0].elapsedMs).assertEqual(elapsed + 100);
    });
    it('allows queued work to continue when the running demo is paused', 0, () => {
      const first = store.enqueue('first.pdf', 'pdf', 'png', 'pdf-png');
      const second = store.enqueue('second.pdf', 'pdf', 'png', 'pdf-png'); runtime.tick(50);
      store.pause(first.id); runtime.tick(3600);
      expect(store.snapshot().find((task) => task.id === second.id)?.status).assertEqual('completed');
      expect(store.snapshot().find((task) => task.id === first.id)?.status).assertEqual('paused');
    });
  });
}
