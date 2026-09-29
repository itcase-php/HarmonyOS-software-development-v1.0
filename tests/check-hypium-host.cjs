'use strict';
// Registered Hypium sources, with suite-scoped hooks and host SDK adapters.
// This is not the actual device Hypium runner or ArkUI execution.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {host}=require('./check-interactions.cjs');
const suites=[];let current;
const hypium={describe:(name,body)=>{
 const parent=current;current={name,cases:[],beforeAll:[],afterAll:[],beforeEach:[],afterEach:[]};
 suites.push(current);body();current=parent;
},it:(name,_flags,body)=>current.cases.push({name,body}),
 beforeAll:body=>current.beforeAll.push(body),afterAll:body=>current.afterAll.push(body),
 beforeEach:body=>current.beforeEach.push(body),afterEach:body=>current.afterEach.push(body),
 expect:actual=>({assertEqual:expected=>assert.equal(actual,expected),assertTrue:()=>assert.equal(actual,true),
 assertFalse:()=>assert.equal(actual,false),assertUndefined:()=>assert.equal(actual,undefined),
 assertThrowError:expected=>assert.throws(actual,typeof expected==='string' ? error=>error.message===expected : expected)})};
async function main() {
 const h=host({hypium,registryReady:false});
 const files=['../../../test/ConversionCore.test','./FidelityPolicy.test','./ConversionPlanner.test','./TaskStore.test',
 './DemoFidelityReport.test','./FidelityReportSnapshot.test','./FormatRegistry.test','./FidelitySettingsVM.test','./FormatDetector.test'];
 const testRoot=path.join(__dirname,'../entry/src/ohosTest/ets/test');
 for(const file of files) h.load(file,testRoot).default();
 const results=[];
 for(const suite of suites) {
  for(const hook of suite.beforeAll) await hook();
  try {
   for(const entry of suite.cases) {
    for(const hook of suite.beforeEach) await hook();
    try {await entry.body();results.push({suite:suite.name,name:entry.name,result:'passed'});}
    catch(error) {error.message=suite.name+' / '+entry.name+': '+error.message;throw error;}
    finally {for(const hook of suite.afterEach) await hook();}
   }
  } finally {for(const hook of suite.afterAll) await hook();}
 }
 assert.equal(h.timers.size,0,'Host timers leaked after all suites');
 for(const registryFile of ['entry/src/test/List.test.ets','entry/src/ohosTest/ets/test/List.test.ets']) {
  const source=fs.readFileSync(path.join(__dirname,'..',registryFile),'utf8');
  for(const file of files) assert.ok(source.includes(path.basename(file)),'Missing test registration '+file);
 }
 const report={scope:'hypium_test_source_executed_with_host_adapter',result:'passed',suiteCount:suites.length,
 testedCases:results.length,cases:results,rawfileVerification:'actual_ArkTS_loader_with_host_crypto_and_resource_adapters',
 actualHypiumRunner:'not_executed',deviceExecution:'not_executed',previewerExecution:'not_executed'};
 fs.writeFileSync(path.join(__dirname,'generated/hypium-host-check-report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify(report,null,2));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
