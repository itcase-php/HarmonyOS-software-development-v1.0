'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { host } = require('./check-interactions.cjs');
const cases = [];
const output = { artifactId:'a'.repeat(32), internalRef:'artifact:'+'a'.repeat(32),
  role:'primary', formatId:'pdf', sha256:'b'.repeat(64), byteSize:1234 };
function fixture(options = {}) {
  const events = [], files = new Map(), descriptors = new Map();
  let nextFd = 10;
  const OpenMode = { WRITE_ONLY:1, CREATE:2, TRUNC:4 };
  const fileIo = { OpenMode, access:async directory=>false, mkdir:async()=>{},
    open:async (uri, mode)=>{
      if (!files.has(uri) && !(mode & OpenMode.CREATE)) throw Object.assign(new Error('Not created'),{code:13900002});
      const file = { fd:nextFd++, uri }; files.set(uri,0); descriptors.set(file.fd,file); return file;
    }, stat:async fd=>({size:options.badSize ? 0 : files.get(descriptors.get(fd).uri)}),
    close:async file=>{events.push(['close']); descriptors.delete(file.fd);} };
  const h = host({sdkModules:{'@kit.CoreFileKit':{fileIo,fileUri:{getUriFromPath:p=>'file://app'+p},
    picker:{DocumentSaveOptions:class{},DocumentViewPicker:class {
      async save(settings) { events.push(['picker',settings.newFileNames[0]]);
        return options.cancel ? [] : ['file://docs/new.pdf']; }
    }}},'@kit.ShareKit':{systemShare:{SharedData:class { constructor(record) { this.record=record; } },
      ShareController:class { constructor(data) { this.data=data; }
        async show(context,settings) {
          // beginShare refreshes TaskHistory and removes the busy task's action buttons.
          if (settings.anchor) throw Object.assign(new Error('Anchor no longer exists'),{code:401});
          assert.equal(files.get(this.data.record.uri.replace('file://app','')),output.byteSize);
          events.push(['share']);
        } },SelectionMode:{SINGLE:0},SharePreviewMode:{DETAIL:1}}}}});
  const store = {snapshot:()=>[{id:'task',fileName:'photo.jpg'}],
    beginExport:()=>output,beginShare:()=>output,
    finishExport:(id,artifactId,state)=>events.push(['finishExport',state]),
    finishShare:(id,shown)=>events.push(['finishShare',shown])};
  const native = {copyArtifactToFd:async (ref,fd,sha256,byteSize)=>{
    assert.equal(ref,output.internalRef); assert.equal(sha256,output.sha256); assert.equal(byteSize,output.byteSize);
    if (options.copyFailure) throw new Error('copy failed');
    files.set(descriptors.get(fd).uri,byteSize); events.push(['copy']); return byteSize;
  }};
  const {ArtifactDelivery}=h.load('./services/ArtifactDelivery');
  return {delivery:new ArtifactDelivery(store,native),events,descriptors,context:{cacheDir:'/cache'}};
}
async function test(name,body) { await body(); cases.push(name); }
(async()=>{
  await test('Save creates a newly selected document and closes it before reporting success',async()=>{
    const f=fixture(); assert.equal(await f.delivery.save('task',f.context),true);
    assert.deepEqual(f.events,[['picker','photo.pdf'],['copy'],['close'],['finishExport','exported']]);
  });
  await test('Share opens without depending on a removed action button',async()=>{
    const f=fixture(); await f.delivery.share('task',f.context);
    assert.deepEqual(f.events,[['copy'],['close'],['share'],['finishShare',true]]);
  });
  await test('Cancelling the picker creates no output and allows retry',async()=>{
    const f=fixture({cancel:true}); assert.equal(await f.delivery.save('task',f.context),false);
    assert.deepEqual(f.events,[['picker','photo.pdf'],['finishExport','cancelled']]);
  });
  for (const kind of ['copyFailure','badSize']) {
    await test(kind+' closes the descriptor and marks export failed',async()=>{
      const f=fixture({[kind]:true}); await assert.rejects(()=>f.delivery.save('task',f.context));
      assert.equal(f.descriptors.size,0); assert.deepEqual(f.events.at(-1),['finishExport','failed']);
    });
  }
  await test('Failed share preparation does not open the panel and permits retry',async()=>{
    const f=fixture({copyFailure:true}); await assert.rejects(()=>f.delivery.share('task',f.context));
    assert.equal(f.descriptors.size,0); assert.deepEqual(f.events,[['close'],['finishShare',false]]);
  });
  const report={result:'passed',scope:'host actual ArtifactDelivery with modeled SDK boundaries',cases};
  fs.writeFileSync(path.join(__dirname,'generated/artifact-delivery-host-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
