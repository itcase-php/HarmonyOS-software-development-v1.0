'use strict';
// Real TaskStore/ServiceContainer lifetime checks. Native/SDK are explicitly modeled.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {host}=require('./check-interactions.cjs');
const cases=[];
(async()=>{
  for(const action of ['save','share']) {
    const h=host(),store=h.store,released=[];
    store.services.runner.releaseOutputs=async result=>{released.push(result.outputs[0].artifactId);};
    const artifact={artifactId:'a'.repeat(32),internalRef:'artifact:'+'a'.repeat(32),role:'primary',formatId:'pdf',byteSize:10,sha256:'b'.repeat(64)};
    store.tasks.push({id:'task',mode:'native',status:'completed',fileName:'file.docx'});
    store.nativeResults.set('task',{status:'success',validation:{state:'passed'},outputs:[artifact]});
    if(action==='save')store.beginExport('task');else store.beginShare('task');
    store.shutdown();assert.equal(released.length,0);
    let drained=false;const wait=store.waitForDeliveries().then(()=>{drained=true;});
    await Promise.resolve();assert.equal(drained,false);
    if(action==='save')store.finishExport('task',artifact.artifactId,'exported');else store.finishShare('task',true);
    await wait;assert.equal(drained,true);assert.deepEqual(released,[artifact.artifactId]);
    cases.push(action+' keeps the Native artifact until delivery finishes during shutdown');
  }
  const h=host(),Container=h.load('./services/ServiceContainer').ServiceContainer;
  let resolveDelivery,shutdownCalls=0,cleaned=0;
  const scope=new Container();Container.currentScope=scope;
  scope.tasks.shutdown=()=>{};
  scope.tasks.waitForDeliveries=()=>new Promise(resolve=>{resolveDelivery=resolve;});
  scope.tasks.releaseAuthorizedSessions=async()=>{cleaned++;};
  scope.native.shutdown=async()=>{shutdownCalls++;};
  const close=scope.closeOwned();await Promise.resolve();assert.equal(shutdownCalls,0);
  Container.currentScope=new Container();resolveDelivery();await close;
  assert.equal(shutdownCalls,0);assert.equal(cleaned,1);
  h.store.shutdown();Container.currentScope.tasks.shutdown();
  cases.push('a closing older ability cannot shutdown the new ability Native runtime');
  for(const handoff of [false,true]) {
    const h3=host(),Container3=h3.load('./services/ServiceContainer').ServiceContainer;
    const scope3=new Container3();Container3.currentScope=scope3;
    let finishActiveCall,activeShutdowns=0;
    scope3.tasks.shutdown=()=>{};
    scope3.tasks.waitForDeliveries=async()=>{};
    scope3.tasks.releaseAuthorizedSessions=()=>new Promise(resolve=>{finishActiveCall=resolve;});
    scope3.native.shutdown=async()=>{activeShutdowns++;};
    const closing3=scope3.closeOwned();for(let i=0;i<12;i++)await Promise.resolve();
    assert.equal(activeShutdowns,0,'Native shutdown ran before the active conversion/input owner settled');
    if(handoff)Container3.currentScope=new Container3();
    finishActiveCall();await closing3;assert.equal(activeShutdowns,handoff?0:1);
    h3.store.shutdown();Container3.currentScope.tasks.shutdown();
    cases.push(handoff?'a scope recreated during conversion cleanup retains its Native runtime':
      'Native shutdown waits until the active conversion and owned input cleanup settle');
  }
  fs.writeFileSync(path.join(__dirname,'generated/delivery-lifecycle-regression.json'),JSON.stringify({scope:'host lifetime logic with modeled Native',passed:cases.length,cases},null,2)+'\n');
  console.log(JSON.stringify({passed:cases.length}));
})().catch(error=>{console.error(error);process.exitCode=1;});
