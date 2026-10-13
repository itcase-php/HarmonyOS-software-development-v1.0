'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { host } = require('./check-interactions.cjs');
const cases = [];
const output = { artifactId:'a'.repeat(32), internalRef:'artifact:'+'a'.repeat(32),
  role:'primary', formatId:'pdf', sha256:crypto.createHash('sha256').update(Buffer.alloc(1234,120)).digest('hex'), byteSize:1234 };
function fixture(options = {}) {
  const events = [], files = new Map(), descriptors = new Map();
  let nextFd = 10;
  const OpenMode = { WRITE_ONLY:1, CREATE:2, TRUNC:4, READ_ONLY:8, READ_WRITE:16 };
  const pending = new Map();
  const fileIo = { OpenMode, access:async directory=>false, mkdir:async()=>{},
    open:async (uri, mode)=>{
      if (!files.has(uri) && !(mode & OpenMode.CREATE)) throw Object.assign(new Error('Not created'),{code:13900002});
      if (mode & OpenMode.TRUNC) files.set(uri,Buffer.alloc(0));
      const file = { fd:nextFd++, uri, position:0 }; descriptors.set(file.fd,file); return file;
    }, stat:async fd=>({size:files.get(descriptors.get(fd).uri).length}),
    read:async (fd,buffer)=>{
      if(options.readFailure) throw new Error('provider read failed');
      const file=descriptors.get(fd),data=files.get(file.uri);
      const count=Math.min(options.shortReads?17:buffer.byteLength,data.length-file.position);
      new Uint8Array(buffer).set(data.subarray(file.position,file.position+count));file.position+=count;return count;
    },
    close:async file=>{
      events.push(['close']);descriptors.delete(file.fd);
      if (options.closeFailure) throw new Error('provider close failed');
      if(pending.has(file.uri)){files.set(file.uri,pending.get(file.uri));pending.delete(file.uri);}
    } };
  const h = host({sdkModules:{'@kit.CoreFileKit':{fileIo,fileUri:{getUriFromPath:p=>'file://app'+p},
    picker:{DocumentSaveOptions:class{},DocumentViewPicker:class {
      async save(settings) { events.push(['picker',settings.newFileNames[0]]);
        return options.cancel ? [] : ['file://docs/new.pdf']; }
    }}},'@kit.ShareKit':{systemShare:{SharedData:class { constructor(record) { this.record=record; } },
      ShareController:class { constructor(data) { this.data=data; }
        async show(context,settings) {
          // beginShare refreshes TaskHistory and removes the busy task's action buttons.
          if (settings.anchor) throw Object.assign(new Error('Anchor no longer exists'),{code:401});
          assert.equal(files.get(this.data.record.uri.replace('file://app','')).length,output.byteSize);
          events.push(['share']);
        } },SelectionMode:{SINGLE:0},SharePreviewMode:{DETAIL:1}}}}});
  const selected={...output,artifactId:options.artifactId||output.artifactId};
  const store = {snapshot:()=>[{id:'task',fileName:options.name||'photo.jpg'}],
    beginExport:()=>selected,beginShare:()=>selected,
    finishExport:(id,artifactId,state)=>events.push(['finishExport',state]),
    finishShare:(id,shown)=>events.push(['finishShare',shown])};
  const native = {copyArtifactToFd:async (ref,fd,sha256,byteSize)=>{
    assert.equal(ref,output.internalRef); assert.equal(sha256,output.sha256); assert.equal(byteSize,output.byteSize);
    if (options.copyFailure) throw new Error('copy failed');
    const data=Buffer.alloc(options.badSize?0:byteSize,options.badHash?121:120);
    (options.finalizeOnClose?pending:files).set(descriptors.get(fd).uri,data);events.push(['copy']);return byteSize;
  }};
  const {ArtifactDelivery}=h.load('./services/ArtifactDelivery');
  return {delivery:new ArtifactDelivery(store,native),events,descriptors,files,context:{cacheDir:'/cache'}};
}
async function test(name,body) { await body(); cases.push(name); }
(async()=>{
  await test('Save creates a newly selected document and closes it before reporting success',async()=>{
    const f=fixture(); assert.equal(await f.delivery.save('task',f.context),true);
    assert.deepEqual(f.events,[['picker','photo.pdf'],['copy'],['close'],['close'],['finishExport','exported']]);
  });
  await test('Share opens without depending on a removed action button',async()=>{
    const f=fixture(); await f.delivery.share('task',f.context);
    assert.deepEqual(f.events,[['copy'],['close'],['close'],['share'],['finishShare',true]]);
  });
  await test('Cancelling the picker creates no output and allows retry',async()=>{
    const f=fixture({cancel:true}); assert.equal(await f.delivery.save('task',f.context),false);
    assert.deepEqual(f.events,[['picker','photo.pdf'],['finishExport','cancelled']]);
  });
  for (const kind of ['copyFailure','badSize','badHash','readFailure','closeFailure']) {
    await test(kind+' closes the descriptor and marks export failed',async()=>{
      const f=fixture({[kind]:true}); await assert.rejects(()=>f.delivery.save('task',f.context));
      assert.equal(f.descriptors.size,0); assert.deepEqual(f.events.at(-1),['finishExport','failed']);
    });
  }
  await test('A provider finalizing on close and returning short reads is verified before success',async()=>{
    const f=fixture({finalizeOnClose:true,shortReads:true});assert.equal(await f.delivery.save('task',f.context),true);
    assert.equal(f.descriptors.size,0);assert.deepEqual(f.events.at(-1),['finishExport','exported']);
  });
  await test('Same-size corruption never opens a share panel',async()=>{
    const f=fixture({badHash:true});await assert.rejects(f.delivery.share('task',f.context));
    assert.equal(f.events.some(event=>event[0]==='share'),false);
    assert.deepEqual(f.events.at(-1),['finishShare',false]);
  });
  await test('Share filenames use the validated opaque reference and cannot traverse via artifact IDs',async()=>{
    const f=fixture({artifactId:'../../escape'});await f.delivery.share('task',f.context);
    assert.deepEqual(Array.from(f.files.keys()),['/cache/shared-pdf/'+'a'.repeat(32)+'.pdf']);
  });
  await test('Long Unicode and control characters produce a safe PDF picker filename',async()=>{
    const f=fixture({name:'A'.repeat(79)+'😀\u0000.jpg'});await f.delivery.save('task',f.context);
    assert.equal(f.events[0][1],'A'.repeat(79)+'😀.pdf');
  });
  await test('Failed share preparation does not open the panel and permits retry',async()=>{
    const f=fixture({copyFailure:true}); await assert.rejects(()=>f.delivery.share('task',f.context));
    assert.equal(f.descriptors.size,0); assert.deepEqual(f.events,[['close'],['finishShare',false]]);
  });
  const report={result:'passed',scope:'host actual ArtifactDelivery with modeled SDK boundaries',cases};
  fs.writeFileSync(path.join(__dirname,'generated/artifact-delivery-host-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
