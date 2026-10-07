'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { host } = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
execFileSync(process.execPath, ['tools/generate-language-catalog.cjs', '--check'], { cwd: root });
const read = locale => JSON.parse(fs.readFileSync(path.join(root,
  `entry/src/main/resources/${locale}/element/string.json`), 'utf8')).string;
const zh = read('base'), en = read('en_US');
const placeholder = value => [...value.matchAll(/%[sd]/g)].map(item => item[0]);
for (const row of zh) {
  const english = en.find(item => item.name === row.name);
  assert.deepEqual(placeholder(row.value), placeholder(english.value), row.name + ' placeholders');
  assert.ok(!/[\u4e00-\u9fff]/.test(english.value), row.name + ' untranslated English');
}
const checks = [];
const check = (name, body) => { body(); checks.push(name); };
const h = host();
const { LanguageManager: language } = h.load('./common/LanguageManager');
const resource = (name, ...args) => ({ id: 100, params: ['app.string.' + name, ...args] });
check('System default, resources and round-trip switch', () => {
  assert.equal(language.currentLanguage, 'zh');
  assert.equal(language.currentLocale, 'zh_CN');
  assert.equal(language.getString('home_title'), '文档转换工具箱');
  language.toggle();
  assert.equal(language.currentLocale, 'en_US');
  assert.equal(language.getString('home_title'), 'Document Conversion Toolbox');
  assert.equal(language.getString(resource('history_count', 3)), '3 tasks');
  assert.equal(language.getString('demo_result', ['客户报告.pdf']), '客户报告.pdf (demo name; no file generated)');
  language.toggle();
  assert.equal(language.getString(resource('history_count', 3)), '3 条记录');
});
check('Native stages, task status, report limitations and degradation labels follow the app language', () => {
  const { taskStatusLabel } = h.load('./models/InteractionModels');
  language.setLanguage('en');
  for (const stage of ['preparing', 'executing', 'validating', 'committing', 'cleaning']) {
    const text = language.stage('native_stage', ['native_' + stage]);
    assert.ok(!text.includes('native_')); assert.ok(!/[\u4e00-\u9fff]/.test(text));
  }
  for (const status of ['queued', 'running', 'paused', 'cancelled', 'completed', 'failed']) {
    for (const mode of ['demo', 'native']) assert.ok(!/[\u4e00-\u9fff]/.test(language.getString(taskStatusLabel(status, mode))));
  }
  assert.equal(language.detail('alpha_flatten'), 'Alpha flattening');
  assert.match(language.detail('report_demo_limitation'), /did not parse a real file/);
  language.setLanguage('zh');
  assert.equal(language.stage('native_stage', ['native_executing']), 'Native · 转换');
});
check('Persistence across process adapters and system-language override', () => {
  const persistedLanguage = new Map();
  const a = host({ systemLanguage: 'fr-FR', persistedLanguage }).load('./common/LanguageManager').LanguageManager;
  assert.equal(a.currentLanguage, 'en');
  a.setLanguage('zh');
  const b = host({ systemLanguage: 'en-US', persistedLanguage }).load('./common/LanguageManager').LanguageManager;
  assert.equal(b.currentLanguage, 'zh');
  b.toggle();
  assert.equal(host({ systemLanguage: 'zh-CN', persistedLanguage }).load('./common/LanguageManager').LanguageManager.currentLanguage, 'en');
});
check('Listeners unsubscribe and same-language selection is inert', () => {
  let calls = 0;
  const token = language.subscribe(() => calls++);
  language.setLanguage('zh'); assert.equal(calls, 0);
  language.toggle(); assert.equal(calls, 1);
  language.unsubscribe(token); language.toggle(); assert.equal(calls, 1);
});
check('Override resource managers are cached per locale; application language waits for loaded window', () => {
  const lm = host().load('./common/LanguageManager').LanguageManager;
  const created = [], applied = [];
  lm.bind({ resourceManager: {
    getOverrideConfiguration: () => ({ colorMode: 7 }),
    getOverrideResourceManager: config => {
      assert.equal(config.colorMode, 7); created.push(config.locale);
      return { getStringByNameSync: name => `${config.locale}:${name}`,
        getStringSync: id => `${config.locale}:${id}` };
    }
  }, getApplicationContext: () => ({ setLanguage: value => applied.push(value) }) });
  lm.setLanguage('en'); assert.equal(applied.length, 0);
  assert.equal(lm.getString('home_title'), 'en_US:home_title');
  lm.getString('home_subtitle'); assert.equal(created.length, 1);
  lm.windowReady(); assert.deepEqual(applied, ['en-US']);
  lm.toggle(); assert.equal(lm.getString(resource('home_title')), 'zh_CN:100');
  assert.deepEqual(created, ['en_US', 'zh_CN']);
});
check('Active and completed tasks retain keys, timing, names and detached arguments', () => {
  const task = h.store.enqueue('客户报告.pdf', 'pdf', 'png', h.planner.routes('pdf', 'png')[0].id);
  h.store.advance(h.now());
  const before = h.store.snapshot()[0];
  language.setLanguage('en');
  assert.match(language.stage(before.stage, before.stageArgs), /Simulated preparation/);
  assert.deepEqual(JSON.parse(JSON.stringify(h.store.snapshot()[0])), JSON.parse(JSON.stringify(before)));
  h.step(4000); h.store.advance(h.now());
  const completed = h.store.snapshot()[0];
  assert.equal(completed.resultLabel, 'demo_result');
  assert.deepEqual(Array.from(completed.resultArgs), ['客户报告.png']);
  assert.match(language.getString(completed.resultLabel, completed.resultArgs), /demo name/);
  language.toggle();
  assert.match(language.getString(completed.resultLabel, completed.resultArgs), /演示名称/);
  completed.resultArgs[0] = 'changed';
  assert.equal(h.store.snapshot()[0].resultArgs[0], '客户报告.png');
});
check('Selector refresh preserves route, consent, user name, quality and error state', () => {
  const { FormatSelectionVM } = h.load('./viewmodel/FormatSelectionVM');
  const { ConversionStatusVM } = h.load('./viewmodel/ConversionStatusVM');
  const status = new ConversionStatusVM(h.store);
  const formats = new FormatSelectionVM(undefined, undefined, undefined, status);
  formats.initializeSelections(); formats.approved = true; formats.fileName = '客户报告.pdf';
  status.errorText = 'demo_filename_invalid';
  const before = [formats.sourceId, formats.targetId, formats.routeId, formats.approved, formats.fileName,
    formats.fidelity.qualityMode, formats.fidelity.requestedTier, formats.fidelity.requestedIntent];
  language.setLanguage('en'); formats.refreshLanguage();
  assert.deepEqual([formats.sourceId, formats.targetId, formats.routeId, formats.approved, formats.fileName,
    formats.fidelity.qualityMode, formats.fidelity.requestedTier, formats.fidelity.requestedIntent], before);
  assert.ok(!/[\u4e00-\u9fff]/.test(formats.fidelity.selectionSummary));
  assert.equal(status.errorText, 'demo_filename_invalid');
  assert.match(language.getString(status.errorText), /valid filename/);
  assert.equal(formats.sourceChoices.find(item => item.value.includes('(txt)')).value, 'Plain text (txt)');
  language.toggle(); formats.refreshLanguage();
  assert.match(formats.fidelity.selectionSummary, /标准|质量|均衡/);
});
check('Pending preview confirmation rebuilds in the new language without submission', () => {
  const { FormatSelectionVM } = h.load('./viewmodel/FormatSelectionVM');
  const { ConversionStatusVM } = h.load('./viewmodel/ConversionStatusVM');
  const { FileAuthorizationVM } = h.load('./viewmodel/FileAuthorizationVM');
  const { ConverterCoordinator } = h.load('./viewmodel/ConverterCoordinator');
  const { ConversionPlannerService } = h.load('./viewmodel/ConversionPlanner');
  const status = new ConversionStatusVM(h.store);
  const formats = new FormatSelectionVM(undefined, undefined, undefined, status);
  const files = new FileAuthorizationVM(undefined, status, formats);
  formats.initializeSelections(); formats.fileName = 'report.pdf'; formats.approved = true;
  const coordinator = new ConverterCoordinator(formats, files, status, h.store, new ConversionPlannerService());
  const count = h.store.snapshot().length;
  coordinator.start(); assert.match(status.inlineConfirmationText, /文件：report.pdf/);
  language.setLanguage('en'); coordinator.refreshLanguage();
  assert.match(status.inlineConfirmationText, /File: report.pdf/);
  assert.ok(!/[\u4e00-\u9fff]/.test(status.inlineConfirmationText));
  assert.equal(formats.approved, true); assert.equal(status.confirming, true);
  assert.equal(h.store.snapshot().length, count);
  coordinator.beginConfirmed(); assert.equal(h.store.snapshot().length, count + 1);
  h.store.shutdown();
});
// Static guard for untouched execution contracts and bilingual bindings on every page.
for (const name of ['Index', 'FormatBrowser', 'ConverterPage', 'TaskHistory', 'FeatureGuide']) {
  const source = fs.readFileSync(path.join(root, `entry/src/main/ets/pages/${name}.ets`), 'utf8');
  assert.ok(source.includes("@StorageLink('appLanguage')"), name + ' reactive binding');
}
const matrix = JSON.parse(fs.readFileSync(path.join(root, 'shared/format-registry/conversion-matrix.json')));
assert.ok(matrix.routes.every(route => route.status === (route.id === 'jpeg-pdf' ? 'experimental' : 'planned')));
const preLanguage = '04e6886f5e1ada231970fc07430b4a51004f3826';
const protectedPaths = ['entry/src/main/cpp', 'shared/format-registry', 'entry/src/main/resources/rawfile',
  'entry/src/main/ets/services/NativeBridge.ets', 'entry/src/main/ets/services/ArtifactDelivery.ets',
  'entry/src/main/ets/services/NativeTaskRunner.ets', 'entry/src/main/ets/models/NativeProtocol.ets',
  'entry/src/main/ets/common/FidelityText.ets', 'entry/src/main/ets/generated/RegistryData.ets',
  'entry/src/main/module.json5',
  'entry/src/main/resources/base/profile/main_pages.json', 'docs/migration-source'];
// Keep the historical baseline; allow only the approved report serialization and JPEG Debug repair files.
const approvedNativeRepair = new Set([
  'entry/src/main/ets/services/ArtifactDelivery.ets',
  'entry/src/main/cpp/CMakeLists.txt', 'entry/src/main/cpp/engines/image/image_converter.cpp',
  'entry/src/main/cpp/generated/registry_metadata.h', 'entry/src/main/cpp/napi/native_bridge.cpp',
  'entry/src/main/cpp/napi/production_napi.cpp', 'entry/src/main/cpp/napi/result_serializer.cpp',
  'entry/src/main/cpp/napi/result_serializer.h', 'entry/src/main/cpp/production/build_manifest.cmake',
  'entry/src/main/cpp/production/route_policy.h', 'entry/src/main/cpp/production/runtime.cpp',
  'entry/src/main/cpp/production/output_validator.cpp',
  'entry/src/main/cpp/tests/output_validator_tests.cpp',
  'entry/src/main/cpp/tests/runtime_tests.cpp', 'entry/src/main/cpp/tests/CMakeLists.txt',
  'entry/src/main/cpp/tests/napi_tests.cpp', 'entry/src/main/ets/generated/RegistryData.ets',
  'entry/src/main/resources/rawfile/format-registry/conversion-matrix.json',
  'entry/src/main/resources/rawfile/format-registry/manifest.json',
  'shared/format-registry/conversion-matrix.json', 'shared/format-registry/debug-routes.json'
]);
const protectedChanges = execFileSync('git', ['diff', '--name-only', preLanguage, '--', ...protectedPaths],
  { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/).filter(Boolean);
assert.deepEqual(protectedChanges.filter(name => !approvedNativeRepair.has(name)), [],
  'Protected conversion/permission contracts changed beyond approved repairs');
// Personal signing settings are local-only and intentionally excluded from commits.
assert.equal(execFileSync('git', ['diff', '--name-only', preLanguage, 'HEAD', '--', 'build-profile.json5'],
  { cwd: root, encoding: 'utf8' }).trim(), '', 'Committed build profile changed');
// User-approved removal of presentation helpers is the only allowed policy change.
const ts = require(process.env.HDM_TYPESCRIPT_PATH ||
  'D:/DevEco Studio2026/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const policyPath = 'entry/src/main/ets/viewmodel/FidelityPolicy.ets';
const priorPolicy = execFileSync('git', ['show', preLanguage + ':' + policyPath], { cwd: root, encoding: 'utf8' });
const priorAst = ts.createSourceFile('FidelityPolicy.ts', priorPolicy, ts.ScriptTarget.Latest, true);
const priorClass = priorAst.statements.find(item => ts.isClassDeclaration(item));
const legacyLabels = new Set(['tierLabel', 'intentLabel', 'qualityLabel']);
let expectedPolicy = priorPolicy;
for (const member of [...priorClass.members].reverse()) {
  if (ts.isMethodDeclaration(member) && legacyLabels.has(member.name.getText(priorAst))) {
    expectedPolicy = expectedPolicy.slice(0, member.getFullStart()) + expectedPolicy.slice(member.end);
  }
}
expectedPolicy = expectedPolicy.replace('FidelityTier, Intent, QualityMode', 'FidelityTier, QualityMode');
assert.equal(fs.readFileSync(path.join(root, policyPath), 'utf8').replace(/\r\n/g, '\n'),
  expectedPolicy.replace(/\r\n/g, '\n'), 'Policy changes exceed the approved label-helper removal');
const report = { scope: 'Runtime language logic with host SDK/storage adapters', resourceCount: zh.length,
  checks, protectedBaseline: preLanguage, approvedPolicyCleanup: [...legacyLabels], result: 'passed',
  actualPreviewer: 'not_executed', actualDevice: 'not_executed',
  actualRestartPersistence: 'not_executed', editorDiagnostics: 'tool_unavailable' };
fs.writeFileSync(path.join(root, 'tests/generated/runtime-language-check-report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
