'use strict';
// Exercise the real device harness setup with modeled SDK contexts; no phone.
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {host} = require('./check-interactions.cjs');
const testRoot = path.resolve(__dirname, '../entry/src/ohosTest/ets/test');
let topCalls = 0, moduleCalls = 0;
const app = {cacheDir:'/application/cache'};
const main = {cacheDir:'/application/haps/entry/cache'};
const marker = new Error('CONTROLLED_FIXTURE_READ');
const fixtureContext = {resourceManager:{getRawFileContent:async()=>{throw marker;}}};
const sdk = {
  '@kit.TestKit':{abilityDelegatorRegistry:{getAbilityDelegator:()=>({getAppContext:()=>app,
    getCurrentTopAbility:async()=>{topCalls++;throw new Error('Calling GetCurrentTopAbility failed.');}}),
    getArguments:()=>({parameters:{'-s fixtureLabel':'docx-default','-s publishFixture':'true'}})}},
  '@kit.AbilityKit':{application:{createModuleContext:async(context,name)=>{
    moduleCalls++;if(name==='entry'){assert.equal(context,app);return main;}
    assert.equal(context,main);assert.equal(name,'entry_test');return fixtureContext;
  }}},
  '@kit.ArkUI':{window:{getLastWindow:async()=>{throw new Error('HEADLESS_CASE_REQUESTED_WINDOW');}}},
  '@ohos.UiTest':{}, '@kit.ShareKit':{}
};
const cases=[];
const h=host({hypium:{describe:(name,fn)=>{const previous=group;group=name;fn();group=previous;},
  it:(name,flags,fn)=>{cases.push({name,group,fn});},expect:()=>{throw new Error('UNEXPECTED_ASSERTION');}},sdkModules:sdk});
let group='';
(async()=>{
  const helper=h.load('./CoreTestContext',testRoot).coreTestContext;
  for(let i=0;i<10;i++)assert.equal(await helper(),main);
  assert.equal(moduleCalls,10);assert.equal(topCalls,0);
  h.load('./CorePdfSmoke.test',testRoot).default();
  const core=cases.filter(item=>item.group==='CorePdfSmoke');assert.equal(core.length,1);
  await assert.rejects(core[0].fn(),error=>error===marker);
  assert.equal(topCalls,0);assert.equal(moduleCalls,12);
  const saved=cases.filter(item=>item.group==='SavedPdfReadback');assert.equal(saved.length,1);
  await assert.rejects(saved[0].fn(),error=>error.message==='Calling GetCurrentTopAbility failed.');
  assert.equal(topCalls,1); // Interactive acceptance still requires a real UI.
  h.load('./JpegDebugSmoke.test',testRoot).default();
  const jpeg=cases.filter(item=>item.group==='JpegDebugSmoke');assert.equal(jpeg.length,2);
  for(const item of jpeg)await assert.rejects(item.fn(),error=>error===marker);
  assert.equal(topCalls,1);assert.equal(moduleCalls,16);
  h.store.shutdown();
  const report={scope:'actual CorePdfSmoke/JPEG context setup with modeled SDK; no device',passed:5,
    headlessCasesDoNotRequireTopAbility:true,entryModuleCacheRetained:true,interactiveCaseStillRequiresUi:true};
  fs.writeFileSync(path.join(__dirname,'generated/core-test-context.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
})().catch(error=>{h.store.shutdown();console.error(error);process.exitCode=1;});
