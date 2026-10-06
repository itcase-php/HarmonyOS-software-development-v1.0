'use strict';
// Host regressions for real-device entry; this does not assert device execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { host } = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
const cases = [];
async function test(name, body) { await body(); cases.push(name); }
const reason = value => error => error.reason === value;
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
async function flush() { for (let i = 0; i < 50; i++) await Promise.resolve(); }
function languageFixture() {
  const logs = [], calls = [];
  const h = host({ sdkModules: { '@kit.PerformanceAnalysisKit': { hilog: {
    warn: (...args) => logs.push(args), info: (...args) => logs.push(args)
  } } } });
  const lm = h.load('./common/LanguageManager').LanguageManager;
  const zh = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/base/element/string.json'))).string;
  const en = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/en_US/element/string.json'))).string;
  let fail = false;
  const read = (locale, key, args) => {
    if (fail) throw { code: 9001002, message: 'private filename and URI' };
    const template = (locale === 'zh_CN' ? zh : en).find(row => row.name === key).value;
    let index = 0;
    return template.replace(/%%|%[sd]/g, match => match === '%%' ? '%' : String(args[index++]));
  };
  lm.bind({ resourceManager: {
    getOverrideConfiguration: () => ({}),
    getOverrideResourceManager: ({ locale }) => ({
      getStringByNameSync: (key, ...args) => { calls.push({ key, args }); return read(locale, key, args); },
      getStringSync: (id, ...args) => { assert.equal(id, 101); calls.push({ id, args }); return read(locale, 'browser_id', args); }
    })
  } });
  return { h, lm, logs, calls, fail: () => { fail = true; } };
}
function preflightFixture(options = {}) {
  const h = host(options);
  const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
  const metadata = h.load('./generated/RegistryData').registryMetadata;
  const route = registry.listPlannedRoutes().find(item => item.id === 'docx-pdf');
  let requests = [], response = { schemaVersion: 1, offlineOnly: true, abi: 'host',
    configVersion: metadata.configVersion, engines: [], routes: [] };
  const native = { getCapabilities: async request => { requests.push(request); return response; } };
  const create = () => new (h.load('./services/RealTaskPreflight').RealTaskPreflight)(registry, native);
  return { h, registry, route, native, create, requests, response,
    ready() {
      response.engines = route.steps.map(step => ({ engineId: step.executorEngineId, version: 'host-fixture', buildHash: 'a'.repeat(64) }));
      response.routes = [{ routeId: route.id, availability: 'available', releaseEvidenceId: 'host-fixture-only' }];
      registry.routes.find(item => item.id === route.id).status = 'available';
    } };
}
async function coordinatorFixture() {
  const f = preflightFixture();
  const { fixture } = require('./check-input-management.cjs');
  // Use the same runtime for registry, diagnostics, file service and coordinator.
  const input = fixture();
  f.h = input.h; f.registry = input.h.load('./services/FormatRegistry').FormatRegistry.shared();
  f.route = f.registry.listPlannedRoutes().find(item => item.id === 'docx-pdf');
  f.ready = () => {
    f.response.engines = f.route.steps.map(step => ({ engineId: step.executorEngineId, version: 'host-fixture', buildHash: 'a'.repeat(64) }));
    f.response.routes = [{ routeId: f.route.id, availability: 'available', releaseEvidenceId: 'host-fixture-only' }];
    f.registry.routes.find(item => item.id === f.route.id).status = 'available';
  };
  const ui = { read: (key, args) => input.h.load('./common/LanguageManager').LanguageManager.getString(key, args),
    tier: value => value, intent: value => value, quality: value => value, toast: () => {},
    showAlertDialog: () => { throw new Error('host inline fallback'); }, ensureRegistry: async () => {}, navigationParams: () => ({}) };
  const submitted = [];
  const store = { snapshot: () => [], subscribe: () => 1, unsubscribe: () => {},
    submitTask: async (...args) => { submitted.push(args); return { id: 'host-task' }; } };
  const status = new (input.h.load('./viewmodel/ConversionStatusVM').ConversionStatusVM)(store, ui);
  const planner = new (input.h.load('./viewmodel/ConversionPlanner').ConversionPlannerService)(f.registry);
  const formats = new (input.h.load('./viewmodel/FormatSelectionVM').FormatSelectionVM)(f.registry, planner, undefined, status, ui);
  const files = new (input.h.load('./viewmodel/FileAuthorizationVM').FileAuthorizationVM)(input.manager, status, formats, ui);
  const service = new (input.h.load('./services/RealTaskPreflight').RealTaskPreflight)(f.registry, f.native);
  const coordinator = new (input.h.load('./viewmodel/ConverterCoordinator').ConverterCoordinator)(formats, files, status, store, planner, ui, service);
  coordinator.appear(); await flush();
  input.select(['中文100%(1).docx']); await files.pickSourceFiles();
  formats.selectTarget(formats.targetFormats.findIndex(item => item.id === 'pdf'));
  return { ...f, input, status, formats, files, coordinator, submitted };
}
async function main() {
  await test('Resource args-only shape keeps its first ordinary string', () => {
    const f = languageFixture();
    assert.equal(f.lm.getString({ id: 101, params: ['pdf'] }), 'ID：pdf');
    assert.deepEqual(f.calls[0].args, ['pdf']);
  });
  await test('Named and ID resources pass explicit independent args, including zero and empty text', () => {
    const f = languageFixture();
    assert.equal(f.lm.getString('browser_id', ['pdf']), 'ID：pdf');
    assert.equal(f.lm.getString('browser_count', [0, 18]), '找到 0 / 18 个格式');
    f.lm.getString({ id: 101, params: ['app.string.browser_id', 'wrong'] }, ['']);
    assert.deepEqual(f.calls.at(-1).args, ['']);
    f.lm.getString({ id: 101 }, [0]); assert.deepEqual(f.calls.at(-1).args, [0]);
    f.lm.getString({ id: 101, params: ['wrong'] }, []); assert.deepEqual(f.calls.at(-1).args, []);
  });
  await test('Only an explicit resource reference is stripped, not a bare key used as a value', () => {
    const f = languageFixture();
    assert.equal(f.lm.getString({ id: 101, params: ['app.string.browser_id', 'pdf'] }), 'ID：pdf');
    assert.equal(f.lm.getString({ id: 101, params: ['browser_id'] }), 'ID：browser_id');
  });
  await test('Known bilingual fallback and user names preserve percent, Chinese, parentheses and zeros', () => {
    const f = languageFixture(); f.fail();
    assert.equal(f.lm.getString('browser_id', ['中文100%(1).pdf']), 'ID：中文100%(1).pdf');
    assert.equal(f.lm.getString('中文100%(1).pdf'), '中文100%(1).pdf');
    assert.equal(f.lm.getString({ id: 101, params: ['app.string.browser_id', 'pdf'] }), 'ID：pdf');
    f.lm.setLanguage('en'); assert.equal(f.lm.getString('browser_count', [0, 18]), 'Found 0 / 18 formats');
    f.lm.setLanguage('zh'); assert.equal(f.lm.getString('browser_id', ['']), 'ID：');
    const unknown = f.lm.getString({ id: 999, params: ['private filename'] });
    assert.ok(unknown.length > 0); assert.ok(!unknown.includes('private'));
    assert.ok(f.logs.length > 0); assert.ok(!JSON.stringify(f.logs).includes('private filename'));
  });
  // Check all app calls, including multiline/nested expressions with TypeScript's AST.
  await test('No formatted $r calls remain in app source', () => {
    const ts = require(process.env.HDM_TYPESCRIPT_PATH || 'D:/DevEco Studio2026/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
    const walkFiles = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(item =>
      item.isDirectory() ? walkFiles(path.join(dir, item.name)) : item.name.endsWith('.ets') ? [path.join(dir, item.name)] : []);
    for (const file of walkFiles(path.join(root, 'entry/src/main/ets'))) {
      const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
      const visit = node => {
        if (ts.isCallExpression(node) && node.expression.getText(ast) === '$r')
          assert.ok(node.arguments.length <= 1, path.relative(root, file) + ': ' + node.getText(ast));
        ts.forEachChild(node, visit);
      };
      visit(ast);
    }
  });
  await test('Real preflight rejects unverified config and route/source/target mismatch before querying Native', async () => {
    const f = preflightFixture();
    f.registry.ready = false;
    await assert.rejects(f.create().inspect('docx-pdf', 'docx', 'pdf'), reason('BUNDLED_RESOURCE_NOT_READY'));
    assert.equal(f.requests.length, 0); f.registry.ready = true;
    await assert.rejects(f.create().inspect('docx-pdf', 'pptx', 'pdf'), reason('NATIVE_ROUTE_REQUEST'));
    assert.equal(f.requests.length, 0);
  });
  await test('Real capabilities distinguish missing engine, bad stamp, closed route and missing evidence', async () => {
    const f = preflightFixture(), service = f.create();
    await assert.rejects(service.inspect('docx-pdf', 'docx', 'pdf'), reason('NATIVE_ENGINE_UNAVAILABLE'));
    assert.equal(f.requests[0].sessionId, 'capability-only-bootstrap'); f.ready();
    f.response.engines[0].buildHash = 'fake';
    await assert.rejects(service.inspect('docx-pdf', 'docx', 'pdf'), reason('NATIVE_ENGINE_UNAVAILABLE'));
    f.response.engines[0].buildHash = 'a'.repeat(64);
    f.response.routes[0].availability = 'planned';
    await assert.rejects(service.inspect('docx-pdf', 'docx', 'pdf'), reason('NATIVE_ROUTE_UNAVAILABLE'));
    f.response.routes[0].availability = 'available'; f.response.routes[0].releaseEvidenceId = '';
    await assert.rejects(service.inspect('docx-pdf', 'docx', 'pdf'), reason('NATIVE_ROUTE_UNAVAILABLE'));
    f.response.routes[0].releaseEvidenceId = 'host-fixture-only';
    await service.inspect('docx-pdf', 'docx', 'pdf');
  });
  await test('Native load/protocol errors stay intact; timeout permits retry and cannot authorize a late result', async () => {
    const f = preflightFixture(), service = f.create();
    const { BridgeError } = f.h.load('./common/BridgeError');
    for (const value of ['NATIVE_MODULE_NOT_AVAILABLE', 'CAPABILITY_RESPONSE']) {
      f.native.getCapabilities = async () => { throw new BridgeError('PROTOCOL_INCOMPATIBLE', value); };
      await assert.rejects(service.inspect('docx-pdf', 'docx', 'pdf'), reason(value));
    }
    const gate = deferred(); f.native.getCapabilities = () => gate.promise;
    const pending = service.inspect('docx-pdf', 'docx', 'pdf');
    const rejected = assert.rejects(pending, reason('CAPABILITY_CHECK_TIMEOUT')); f.h.fireTimeouts(); await rejected;
    f.ready(); f.native.getCapabilities = async () => f.response;
    await service.inspect('docx-pdf', 'docx', 'pdf'); gate.resolve(f.response); await flush();
  });
  await test('Missing engine blocks confirmation and queue; retry keeps the imported input until explicit confirmation', async () => {
    const f = await coordinatorFixture();
    const session = f.files.sessionContext.sessionId, fileId = f.files.authorizedFiles[0].fileId;
    await f.coordinator.startAuthorized();
    assert.equal(f.status.errorText, 'input_engine_missing'); assert.equal(f.status.confirming, false);
    assert.equal(f.status.realConfirmationText, ''); assert.equal(f.submitted.length, 0);
    assert.equal(f.files.authorizedFiles[0].fileId, fileId); assert.equal(f.files.sessionContext.sessionId, session);
    f.ready(); f.coordinator.retry(); await flush();
    assert.ok(f.status.realConfirmationText.includes('中文100%(1).docx')); assert.equal(f.submitted.length, 0);
    await f.coordinator.beginAuthorized(); assert.equal(f.submitted.length, 1);
    await f.input.manager.destroyAllSessions(); f.coordinator.hide(true);
  });
  await test('Selection changes during preflight or after confirmation cannot submit stale approval', async () => {
    for (const phase of ['during', 'after']) {
      const f = await coordinatorFixture(); f.ready();
      const gate = deferred(); f.native.getCapabilities = () => gate.promise;
      const pending = f.coordinator.startAuthorized(); await flush();
      if (phase === 'during') f.files.authorizedFiles[0].sha256 = 'b'.repeat(64);
      gate.resolve(f.response); await pending;
      if (phase === 'after') { f.formats.approved = !f.formats.approved; await f.coordinator.beginAuthorized(); }
      assert.equal(f.status.errorText, 'input_selection_changed'); assert.equal(f.submitted.length, 0);
      assert.equal(f.files.authorizedFiles.length, 1); assert.equal(f.status.confirming, false);
      f.coordinator.hide(true); await flush();
    }
  });
  await test('Timeout retries and navigation invalidate late capability results without creating tasks', async () => {
    for (const action of ['timeout', 'navigate']) {
      const f = await coordinatorFixture(); f.ready();
      const old = deferred(); f.native.getCapabilities = () => old.promise;
      const pending = f.coordinator.startAuthorized(); await flush();
      if (action === 'timeout') {
        f.h.fireTimeouts(); await pending;
        assert.equal(f.status.errorText, 'input_capability_timeout'); assert.equal(f.files.authorizedFiles.length, 1);
        const current = deferred(); f.native.getCapabilities = () => current.promise;
        const retry = f.coordinator.startAuthorized(); await flush();
        old.resolve(f.response); await flush(); assert.equal(f.status.realConfirmationText, '');
        current.resolve(f.response); await retry; assert.ok(f.status.realConfirmationText);
      } else {
        f.coordinator.hide(true); old.resolve(f.response); await pending; assert.equal(f.status.realConfirmationText, '');
      }
      assert.equal(f.submitted.length, 0); f.coordinator.hide(true); await flush();
    }
  });
  const report = { scope: 'host SDK adapters', cases, result: 'passed', device: 'not_executed' };
  fs.writeFileSync(path.join(__dirname, 'generated/device-entry-host-check-report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
