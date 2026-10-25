import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application, common } from '@kit.AbilityKit';

// Engine cases need module resources/cache, not a foreground UIAbility. Keep
// their sandbox in entry so the engine uses the main application's cache root.
export async function coreTestContext(): Promise<common.Context> {
  const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  return application.createModuleContext(context, 'entry');
}
