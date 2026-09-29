'use strict';
// Runs the registered Hypium test source with a minimal host assertion adapter.
// This does not claim execution on the actual Hypium device runner.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const cases=[];
const hooks={before:[],after:[]};
const hypium={describe:(_name,body)=>body(),it:(name,_flags,body)=>cases.push({name,body}),
  beforeEach:body=>hooks.before.push(body),afterEach:body=>hooks.after.push(body),
  expect:actual=>({assertEqual:expected=>assert.equal(actual,expected),assertTrue:()=>assert.equal(actual,true),
    assertFalse:()=>assert.equal(actual,false),assertUndefined:()=>assert.equal(actual,undefined)})};
async function main() {
  const h=host({hypium});h.load('../../test/ConversionCore.test').default();
  const results=[];
  for(const entry of cases) {
    for(const before of hooks.before) await before();
    try { await entry.body();results.push({name:entry.name,result:'passed'}); }
    finally { for(const after of hooks.after) await after(); }
  }
  const report={scope:'hypium_test_source_executed_with_host_adapter',result:'passed',testedCases:results.length,cases:results,
    actualHypiumRunner:'not_executed',deviceExecution:'not_executed',previewerExecution:'not_executed'};
  fs.writeFileSync(path.join(__dirname,'generated/hypium-host-check-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
