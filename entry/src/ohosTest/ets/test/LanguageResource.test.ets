import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import { LanguageManager } from '../../../main/ets/common/LanguageManager';

export default function languageResourceTest() {
  describe('LanguageResource', () => {
    it('formats real SDK resources and independent arguments in both languages', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      const previous = LanguageManager.currentLanguage;
      // Compile-time IDs belong to entry_test; create its manager from a real Stage context.
      LanguageManager.bind(await application.createModuleContext(context, 'entry_test'));
      try {
        const resource: Resource = $r('app.string.browser_id', 'pdf');
        const first: string | number | undefined = resource.params ? resource.params[0] as string | number : undefined;
        const namePrefix: boolean = typeof first === 'string' && first.startsWith('app.string.');
        // Shape evidence only; do not log parameter values or user file information.
        hilog.info(0x0000, 'LanguageResourceTest', 'id=%{public}d count=%{public}d namePrefix=%{public}s',
          resource.id, resource.params?.length ?? 0, namePrefix.toString());
        LanguageManager.setLanguage('zh');
        expect(LanguageManager.getString('browser_id', ['pdf'])).assertEqual('ID：pdf');
        expect(LanguageManager.getString(resource)).assertEqual('ID：pdf');
        expect(LanguageManager.getString($r('app.string.browser_id'), ['pdf'])).assertEqual('ID：pdf');
        expect(LanguageManager.getString('browser_count', [0, 18])).assertEqual('找到 0 / 18 个格式');
        LanguageManager.setLanguage('en');
        expect(LanguageManager.getString('browser_id', ['pdf'])).assertEqual('ID: pdf');
        expect(LanguageManager.getString('browser_count', [0, 18])).assertEqual('Found 0 / 18 formats');
        expect(LanguageManager.getString('中文100%(1).docx')).assertEqual('中文100%(1).docx');
      } finally { LanguageManager.bind(context); LanguageManager.setLanguage(previous); }
    });
  });
}
