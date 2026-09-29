import { abilityDelegatorRegistry } from '@kit.TestKit';
import { FormatRegistry } from '../../../main/ets/services/FormatRegistry';
import { RawfileResources } from '../../../main/ets/services/RawfileResources';
import { ConversionRouteDefinition } from '../../../main/ets/models/RegistryTypes';
import { DemoTask, TaskRuntime } from '../../../main/ets/models/InteractionModels';

export async function initializeRegistry(): Promise<void> {
  await FormatRegistry.initialize(new RawfileResources(abilityDelegatorRegistry.getAbilityDelegator().getAppContext().resourceManager));
}

export function testRoute(id: string = 'pdf-png'): ConversionRouteDefinition {
  const route = FormatRegistry.listPlannedRoutes().find((item: ConversionRouteDefinition) => item.id === id);
  if (!route) { throw new Error(`Missing fixture route: ${id}`); }
  return JSON.parse(JSON.stringify(route)) as ConversionRouteDefinition;
}

export function testTask(): DemoTask {
  const task = new DemoTask();
  task.id = 'demo-fixture'; task.intent = 'layout_preserved'; task.requestedIntent = task.intent;
  task.requestedTier = 'compatible';
  return task;
}

interface PendingTick { id: number; due: number; callback: () => void; }

// A separate clock/queue per test: no wall-clock waits or shared singleton tasks.
export class ManualTaskRuntime implements TaskRuntime {
  private time: number = 1700000000000;
  private sequence: number = 0;
  private pending: PendingTick[] = [];
  now(): number { return this.time; }
  setTimeout(callback: () => void, delayMs: number): number {
    const id = ++this.sequence;
    this.pending.push({ id: id, due: this.time + delayMs, callback: callback });
    return id;
  }
  clearTimeout(id: number): void { this.pending = this.pending.filter((tick: PendingTick) => tick.id !== id); }
  timerCount(): number { return this.pending.length; }
  tick(ms: number): void {
    const end = this.time + ms;
    let next = this.pending.sort((a: PendingTick, b: PendingTick) => a.due - b.due)[0];
    while (next && next.due <= end) {
      this.time = next.due; this.clearTimeout(next.id); next.callback();
      next = this.pending.sort((a: PendingTick, b: PendingTick) => a.due - b.due)[0];
    }
    this.time = end;
  }
}
