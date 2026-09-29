import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NativeBridge } from '../services/NativeBridge';
import { TaskStore } from '../viewmodel/TaskStore';
import { FileAuthorizationService } from '../services/FileAuthorizationService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try { FileAuthorizationService.configure(this.context); }
    catch (_) { hilog.error(DOMAIN, 'FileAuthorization', '%{public}s', 'File service unavailable'); }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    const store: TaskStore = TaskStore.shared();
    const cleanup: () => Promise<void> = FileAuthorizationService.captureCleanup();
    store.shutdown();
    NativeBridge.shutdown().catch(() => {
      hilog.error(DOMAIN, 'NativeBridge', '%{public}s', 'Native shutdown failed');
    }).finally(() => {
      store.releaseAuthorizedSessions(cleanup).catch(() => {
        hilog.error(DOMAIN, 'FileAuthorization', '%{public}s', 'Owned workspace cleanup failed');
      });
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
