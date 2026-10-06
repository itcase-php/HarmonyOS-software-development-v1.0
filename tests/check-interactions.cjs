'use strict';
// Execute the real non-UI ArkTS models/services in a controlled host runtime.
// This is not a substitute for ArkUI/Previewer/device execution or a real engine test.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {TextDecoder} = require('node:util');
const root = path.resolve(__dirname,'..');
const sourceRoot = path.join(root,'entry/src/main/ets');
const tsPath = process.env.HDM_TYPESCRIPT_PATH ||
  'D:/DevEco Studio2026/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js';
const ts = require(tsPath);
const formats = JSON.parse(fs.readFileSync(path.join(root,'shared/format-registry/formats.json'),'utf8'));
const matrix = JSON.parse(fs.readFileSync(path.join(root,'shared/format-registry/conversion-matrix.json'),'utf8'));
const cases = [];
function host(options = {}) {
  let clock = 1700000000000;
  let intervalId = 0;
  let nativeExports;
  let nativeLoads = 0;
  const timers = new Map();
  const timeouts = timers;
  const cache = new Map();
  const languageState = options.languageState || new Map();
  const persistedLanguage = options.persistedLanguage || new Map();
  class ClockDate extends Date { static now() { return clock; } }
  const context = vm.createContext({Date:ClockDate,Map,Math,Number,Array,Error,Object,Promise,String,Uint8Array,console,Observed:target=>target,
    $r:(name,...args)=>({id:name,params:[name,...args]}),
    AppStorage:{get:key=>languageState.get(key),setOrCreate:(key,value)=>{
      languageState.set(key,value);if(persistedLanguage.has(key))persistedLanguage.set(key,value);
    }},
    PersistentStorage:{persistProp:(key,value)=>{
      if(!persistedLanguage.has(key))persistedLanguage.set(key,value);
      languageState.set(key,persistedLanguage.get(key));
    }},
    canIUse:()=>options.cryptoAvailable!==false,
    setInterval(callback) { timers.set(++intervalId,callback); return intervalId; },
    clearInterval(id) { timers.delete(id); },
    setTimeout(callback) { timeouts.set(++intervalId,callback); return intervalId; },
    clearTimeout(id) { timeouts.delete(id); }});
  function load(relative, from=sourceRoot) {
    if (options.sdkModules && Object.prototype.hasOwnProperty.call(options.sdkModules,relative)) return options.sdkModules[relative];
    if (relative === 'BuildProfile') return {__esModule:true,default:{DEBUG:options.debugBuild===true}};
    if (relative === '@kit.PerformanceAnalysisKit') return {hilog:{info:()=>{},warn:()=>{}}};
    if (relative === '@kit.CoreFileKit') return {};
    if (relative === '@kit.LocalizationKit') return {i18n:{System:{getSystemLanguage:()=>options.systemLanguage || 'zh-CN'}}};
    if (relative === '@ohos/hypium' && options.hypium) return options.hypium;
    if (relative === '@kit.ArkTS') return {util:{generateRandomUUID:()=>crypto.randomUUID(),TextDecoder:{create:(encoding,settings)=>{
      const decoder=new TextDecoder(encoding,settings);return {decodeToString:bytes=>decoder.decode(bytes)};
    }}}};
    if (relative === '@kit.CryptoArchitectureKit') return {cryptoFramework:{createMd:algorithm=>{
      assert.equal(algorithm,'SHA256');const digest=crypto.createHash('sha256');
      return {update:async blob=>{digest.update(blob.data);},digest:async()=>({data:new Uint8Array(digest.digest())})};
    }}};
    if (relative === '@kit.TestKit' && options.hypium) return {abilityDelegatorRegistry:{
      getAbilityDelegator:()=>({getAppContext:()=>({resourceManager:resources})})}};
    if (relative==='libentry.so') {
      nativeLoads++;
      if (!nativeExports) throw new Error('Native library unavailable in host test');
      return {__esModule:true,default:nativeExports};
    }
    assert.ok(relative.startsWith('.'),'Unexpected runtime SDK dependency in pure logic test: '+relative);
    const file = path.resolve(from,relative)+'.ets';
    const testRoot = path.join(root,'entry/src/test');
    const deviceRoot = path.join(root,'entry/src/ohosTest/ets/test');
    assert.ok(file.startsWith(sourceRoot+path.sep) || (options.hypium &&
      (file.startsWith(testRoot+path.sep) || file.startsWith(deviceRoot+path.sep))),
      'Source path outside permitted application/test directories');
    if (cache.has(file)) return cache.get(file).exports;
    const module = {exports:{}};
    cache.set(file,module);
    const result = ts.transpileModule(fs.readFileSync(file,'utf8'),{fileName:file.replace(/\.ets$/,'.ts'),
      compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS,esModuleInterop:true},
      reportDiagnostics:true});
    assert.equal((result.diagnostics||[]).filter(item=>item.category===ts.DiagnosticCategory.Error).length,0);
    const fn = new vm.Script('(function(require,module,exports){'+result.outputText+'\n})',{filename:file})
      .runInContext(context);
    fn(request=>load(request,path.dirname(file)),module,module.exports);
    return module.exports;
  }
  const resources={getRawFileContent:async name=>new Uint8Array(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile',name)))};
  // Legacy synchronous logic checks seed an isolated registry from validated fixtures.
  // Runtime integrity/initialization suites use registryReady:false and the real loader.
  const {FormatRegistry}=load('./services/FormatRegistry');
  if(options.registryReady!==false) {
    FormatRegistry.shared().formats=JSON.parse(JSON.stringify(formats.formats));
    FormatRegistry.shared().routes=JSON.parse(JSON.stringify(matrix.routes));FormatRegistry.shared().ready=true;
  }
  const {TaskStore} = load('./viewmodel/TaskStore');
  const {ConversionPlanner} = load('./viewmodel/ConversionPlanner');
  return {store:new TaskStore(),planner:ConversionPlanner,load,
    resources,now:()=>clock,step(ms) { clock+=ms; },timers,timeouts,
    fireTimeouts() { const callbacks=Array.from(timeouts.values());timeouts.clear();callbacks.forEach(callback=>callback()); },
    setNative(value) { nativeExports=value; },nativeLoads:()=>nativeLoads};
}
function enqueue(h,name='报告.pdf') {
  const route = h.planner.routes('pdf','png')[0];
  const task=h.store.enqueue(name,'pdf','png',route.id);
  h.store.advance(h.now());return task;
}
async function test(name,fn) {
  await fn(); cases.push({name,result:'passed'});
}
async function main() {
  await test('Every selectable target is backed by a single-input planned route; priorities ascend',()=>{
    const h=host();
    for (const source of formats.formats) {
      const expected=matrix.routes.filter(route=>route.from.includes(source.id) &&
        route.inputConstraints.minInputs<=1 && route.inputConstraints.maxInputs>=1 && route.status!=='unavailable');
      assert.deepEqual(Array.from(h.planner.targets(source.id),item=>item.id),
        formats.formats.filter(item=>expected.some(route=>route.to===item.id)).map(item=>item.id));
      for (const target of h.planner.targets(source.id)) {
        const routes=h.planner.routes(source.id,target.id);
        for (let i=1;i<routes.length;i++) {
          if (routes[i-1].pathMode===routes[i].pathMode) assert.ok(routes[i-1].priority<=routes[i].priority);
          else assert.equal(routes[i-1].pathMode,'direct');
        }
      }
    }
    h.store.shutdown();
  });
  await test('File names reject paths, blocked extensions, missing suffixes and source mismatch',()=>{
    const h=host();
    for (const name of ['', '../report.pdf', 'x\\report.pdf', 'report', '.pdf', 'x.txt','x.pdf\u0000'])
      assert.throws(()=>h.planner.validateFileName(name,'pdf'));
    assert.throws(()=>h.planner.validateFileName('music.NCM','pdf'),error=>error.code==='PERMISSION_DENIED');
    assert.equal(h.planner.validateFileName(' image.JPG ','jpeg'),'image.JPG');
    assert.equal(h.planner.targets('jpg').length,h.planner.targets('jpeg').length);
  });
  await test('Unsupported route is rejected before creating a task',()=>{
    const h=host();
    assert.throws(()=>h.store.enqueue('x.pdf','pdf','mp3','not-a-route'));
    assert.equal(h.store.snapshot().length,0); assert.equal(h.timers.size,0);
  });
  await test('Degradation routes require approval in the store as well as the page',()=>{
    const h=host(); const route=matrix.routes.find(route=>route.requiresUserApproval && route.inputConstraints.minInputs<=1);
    assert.ok(route); const source=formats.formats.find(format=>format.id===route.from[0]);
    const name='report.'+source.extensions[0];
    assert.throws(()=>h.store.enqueue(name,source.id,route.to,route.id),error=>error.reason==='DEMO_APPROVAL_REQUIRED');
    assert.equal(h.store.snapshot().length,0);
    h.store.enqueue(name,source.id,route.to,route.id,true); assert.equal(h.store.snapshot().length,1);
    h.store.shutdown();
  });
  await test('FIFO queue permits one running task and a single timer',()=>{
    const h=host(); const first=enqueue(h,'first.pdf'); const second=enqueue(h,'second.pdf');
    assert.equal(h.store.snapshot().find(item=>item.id===first.id).status,'running');
    assert.equal(h.store.snapshot().find(item=>item.id===second.id).status,'queued');
    assert.equal(h.timers.size,1);
    h.step(3500); h.store.advance(h.now());
    assert.equal(h.store.snapshot().find(item=>item.id===first.id).status,'completed');
    assert.equal(h.store.snapshot().find(item=>item.id===second.id).status,'running');
    h.store.shutdown(); assert.equal(h.timers.size,0);
  });
  await test('Five stages are monotonic and completion is explicitly demo-only',()=>{
    const h=host(); enqueue(h);
    const moments=[0,525,2275,2975,3325,3500];
    const labels=['①','②','③','④','⑤','演示完成'];
    let previous=0; let previousMoment=0;
    moments.forEach((moment,index)=>{
      h.step(moment-previousMoment); previousMoment=moment; h.store.advance(h.now());
      const task=h.store.snapshot()[0];
      assert.ok(task.progress>=previous); previous=task.progress;
      const {LanguageManager}=h.load('./common/LanguageManager');
      assert.ok(LanguageManager.stage(task.stage,task.stageArgs).includes(labels[index]));
    });
    const done=h.store.snapshot()[0];
    assert.equal(done.mode,'demo'); assert.equal(done.status,'completed');
    assert.equal(done.progress,100);
    assert.ok(h.load('./common/LanguageManager').LanguageManager.getString(done.resultLabel,done.resultArgs).includes('未生成文件'));
    assert.equal(done.outputs,undefined); assert.equal(h.timers.size,0);
  });
  await test('Pause freezes progress; resume excludes paused wall time',()=>{
    const h=host(); const task=enqueue(h); h.step(750); h.store.advance(h.now());
    assert.equal(h.store.pause(task.id),true); const before=h.store.snapshot()[0];
    h.step(5000); h.store.advance(h.now());
    assert.equal(h.store.snapshot()[0].progress,before.progress);
    assert.equal(h.store.snapshot()[0].elapsedMs,before.elapsedMs); assert.equal(h.timers.size,0);
    assert.equal(h.store.resume(task.id),true); h.step(300); h.store.advance(h.now());
    assert.equal(h.store.snapshot()[0].elapsedMs,1050);
    h.store.shutdown();
  });
  await test('Cancellation near completion cannot later become completed',()=>{
    const h=host(); const task=enqueue(h); h.step(3499); h.store.advance(h.now());
    assert.equal(h.store.cancel(task.id),true); h.step(10000); h.store.advance(h.now());
    assert.equal(h.store.snapshot()[0].status,'cancelled');
    assert.equal(h.store.snapshot()[0].resultLabel,''); assert.equal(h.timers.size,0);
    assert.equal(h.store.resume(task.id),false); assert.equal(h.store.cancel(task.id),false);
  });
  await test('History cleanup retains running and paused tasks',()=>{
    const h=host(); enqueue(h,'one.pdf'); const second=enqueue(h,'two.pdf'); enqueue(h,'three.pdf');
    h.step(3500); h.store.advance(h.now()); assert.equal(h.store.pause(second.id),true);
    assert.equal(h.store.clearFinished(),1); assert.equal(h.store.snapshot().length,2);
    assert.deepEqual(Array.from(h.store.snapshot(),item=>item.status).sort(),['paused','running']);
    h.store.shutdown();
  });
  await test('Observers receive independent snapshots and unsubscribe cleanly',()=>{
    const h=host(); let notifications=0;
    h.store.subscribe(()=>{throw new Error('Detached page');});
    const token=h.store.subscribe(tasks=>{ notifications++; if(tasks.length)tasks[0].fileName='changed'; });
    enqueue(h); assert.equal(h.store.snapshot()[0].fileName,'报告.pdf');
    const before=notifications; h.store.unsubscribe(token); h.step(120); h.store.advance(h.now());
    assert.equal(notifications,before); h.store.shutdown();
  });
  await test('History is bounded; new tasks evict finished records only',()=>{
    const h=host(); for(let i=0;i<100;i++)enqueue(h,`report-${i}.pdf`);
    assert.throws(()=>enqueue(h,'overflow.pdf'),error=>error.code==='TASK_BUSY');
    const finished=h.store.snapshot()[99]; h.store.cancel(finished.id); enqueue(h,'replacement.pdf');
    assert.equal(h.store.snapshot().length,100); assert.equal(h.timers.size,1); h.store.shutdown();
  });
  await test('Native load failure stays unavailable and can be retried',async()=>{
    const h=host(); const {NativeBridge}=h.load('./services/NativeBridge');
    const request={schemaVersion:1,sessionId:'bootstrap',configVersion:formats.configVersion};
    assert.equal(NativeBridge.isNativeAvailable(),false);
    await assert.rejects(()=>NativeBridge.getCapabilities(request),error=>error.reason==='NATIVE_MODULE_NOT_AVAILABLE');
    assert.equal(NativeBridge.isNativeAvailable(),false);
    h.setNative({getCapabilities:async()=>({schemaVersion:1,offlineOnly:true,abi:'host-test-only',
      configVersion:formats.configVersion,engines:[],routes:[]})});
    const caps=await NativeBridge.getCapabilities(request);
    assert.equal(caps.routes.length,0); assert.equal(NativeBridge.isNativeAvailable(),true);
    assert.equal(h.nativeLoads(),2);
  });
  await test('Native requests block traversal/budget errors and empty or mismatched successful output',async()=>{
    const h=host(); const {NativeBridge}=h.load('./services/NativeBridge'); let calls=0;
    const route=matrix.routes.find(route=>route.id==='jpeg-pdf');
    const request={schemaVersion:1,sessionId:'test',taskId:'t',attemptId:'a',workspaceRef:'w',
      operation:route.operation,inputs:[{fileId:'f',sourceFormatId:'jpeg',relativePath:'input.jpg',byteSize:12,sha256:'a'.repeat(64)}],
      targetFormatId:'pdf',qualityMode:'balanced',intent:route.intent,options:{},resourceBudget:formats.resourceProfiles.default,
      plan:{routeId:route.id,steps:route.steps,fallbackRouteIds:[],configVersion:formats.configVersion,
        configSha256:'a'.repeat(64),intent:route.intent,minimumTier:'extreme',allowedDegradations:[],policyVersion:'1'}};
    h.setNative({getCapabilities:async()=>{},execute:async()=>{calls++;return {taskId:'t',attemptId:'a',
      status:'success',outputs:[],validation:{state:'passed'}};}});
    const badPath=JSON.parse(JSON.stringify(request));badPath.inputs[0].relativePath='..\\input.jpg';
    await assert.rejects(()=>NativeBridge.execute(badPath),error=>error.reason==='INPUT_REFERENCE');
    const badBudget=JSON.parse(JSON.stringify(request));badBudget.resourceBudget.maxThreads=0;
    await assert.rejects(()=>NativeBridge.execute(badBudget),error=>error.reason==='BUDGET_RANGE');
    assert.equal(calls,0);
    await assert.rejects(()=>NativeBridge.execute(request),error=>error.reason==='EXECUTE_RESPONSE');
    assert.equal(calls,1);
  });
  await test('Capability detection times out if preview platform does not settle its promise',async()=>{
    const h=host(); h.setNative({getCapabilities:()=>new Promise(()=>{})});
    const {FoundationViewModel}=h.load('./viewmodel/FoundationViewModel');
    const promise=new FoundationViewModel().inspect();
    assert.equal(h.timeouts.size,1);
    const assertion=assert.rejects(()=>promise,error=>error.reason==='CAPABILITY_CHECK_TIMEOUT');
    h.fireTimeouts(); await assertion;
    assert.equal(h.timeouts.size,0);
  });
  await test('All five pages are registered and task views invalidate on status/progress changes',()=>{
    const routes=JSON.parse(fs.readFileSync(path.join(root,'entry/src/main/resources/base/profile/main_pages.json'),'utf8')).src;
    assert.deepEqual(routes,['pages/Index','pages/FormatBrowser','pages/ConverterPage','pages/TaskHistory','pages/FeatureGuide']);
    for(const route of routes) assert.match(fs.readFileSync(path.join(sourceRoot,route+'.ets'),'utf8'),/@Entry/);
    for(const route of ['components/ConversionProgressPanel','pages/TaskHistory'])
      assert.match(fs.readFileSync(path.join(sourceRoot,route+'.ets'),'utf8'),/task\.id\}-\$\{task\.status\}-\$\{task\.progress\}/);
    for(const route of ['pages/Index','pages/ConverterPage','pages/TaskHistory']) {
      const source=fs.readFileSync(path.join(sourceRoot,route+'.ets'),'utf8');
      assert.match(source,/onPageShow\(\): void/);assert.match(source,/onPageHide\(\): void/);
    }
  });
  const report={scope:'host_non_ui_logic_and_route_contracts',result:'passed',cases,
    testedCases:cases.length,deviceExecution:'not_executed',previewerExecution:'not_executed',realConversion:'not_executed'};
  fs.writeFileSync(path.join(root,'tests/generated/interaction-check-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
}
module.exports = { host };
if (require.main === module) main().catch(error=>{console.error(error);process.exitCode=1;});
