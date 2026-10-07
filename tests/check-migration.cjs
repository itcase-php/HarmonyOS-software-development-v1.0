'use strict';
// Completeness checks for this migration, not conversion/device acceptance tests.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative));
const text = relative => read(relative).toString('utf8');
const json = relative => JSON.parse(text(relative));
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes:true}).flatMap(entry =>
    entry.isDirectory() ? walk(path.join(dir,entry.name)) : [path.join(dir,entry.name)]);
}
const manifest = json('docs/MIGRATION_MANIFEST.json');
assert.equal(manifest.records.length, manifest.sourceFiles);
const records = manifest.records.map(record => {
  assert.equal(hash(read(record.exactSourceSnapshot)), record.sourceSha256,
    `Original snapshot changed: ${record.source}`);
  assert.ok(fs.existsSync(path.join(root,record.target)), `Missing active target: ${record.target}`);
  const originalFile = path.join(manifest.source,record.source);
  if (fs.existsSync(originalFile)) assert.equal(hash(fs.readFileSync(originalFile)), record.sourceSha256,
    `Original outputs changed: ${record.source}`);
  return {source:record.source,target:record.target,
    sourceSha256:record.sourceSha256,currentTargetSha256:hash(read(record.target)),
    changedSinceFirstImport:hash(read(record.target)) !== record.targetSha256};
});
assert.equal(hash(read(manifest.attachment.target)),manifest.attachment.sha256);
assert.ok(read('entry/src/main/cpp/core/converter.h').equals(read('docs/migration-source/contracts/converter.h')),
  'Original C++ contract lost or changed');
const protocol = text('entry/src/main/ets/models/NativeProtocol.ets');
const expectedProtocol = text('docs/migration-source/contracts/native_bridge.d.ts')
  .replace('/** Design contract v1. Not a compiled/implemented HarmonyOS binding. */',
    '// Protocol v1 migrated into ArkTS. Implemented binding subset is documented in IMPLEMENTATION_STATUS.md.')
  .replace(/declare const nativeModule: NativeModule;\nexport default nativeModule;\s*$/,'');
// The previously approved delivery method is the only addition to the original protocol.
const deliveryProtocol=expectedProtocol.replace('  shutdown(): Promise<void>;',
  '  copyArtifactToFd(internalRef: string, destinationFd: number, sha256: string, byteSize: number): Promise<number>;\n  shutdown(): Promise<void>;');
assert.equal(protocol,deliveryProtocol,'Original model declarations or approved delivery contract changed');
assert.equal(text('entry/src/main/cpp/types/libentry/Protocol.d.ts'),
  '// Generated from models/NativeProtocol.ets. Do not edit independently.\n'+protocol,
  'Native and ArkTS protocol copies drifted');
assert.doesNotMatch(text('entry/src/main/cpp/types/libentry/Index.d.ts'), /\.ets|\.\.\/.*ets\//);
const methods = [...protocol.match(/export interface NativeModule \{([\s\S]*?)\}/)[1]
  .matchAll(/^\s+([a-zA-Z]+)\(/gm)].map(match=>match[1]);
const native = text('entry/src/main/cpp/napi/native_bridge.cpp');
const bridge = text('entry/src/main/ets/services/NativeBridge.ets');
assert.equal(methods.length,14);
for (const method of methods) {
  assert.match(native,new RegExp(`\\{"${method}", nullptr,`),`NAPI export missing: ${method}`);
  assert.match(bridge,new RegExp(`static (?:async )?${method}\\(`),`ArkTS wrapper missing: ${method}`);
}
assert.match(text('entry/src/main/cpp/napi_init.cpp'), /"add", nullptr, Add/);
assert.match(text('entry/src/main/cpp/napi_init.cpp'), /\.nm_modname = "entry"/);
const etsFiles = walk(path.join(root,'entry/src/main/ets')).filter(file=>file.endsWith('.ets'));
const directImports = etsFiles.filter(file=>/(?:from\s+|import\()['"]libentry\.so['"]/.test(fs.readFileSync(file,'utf8')));
assert.deepEqual(directImports.map(file=>path.relative(root,file).replaceAll('\\','/')),
  ['entry/src/main/ets/services/NativeBridge.ets']);
for (const file of etsFiles) assert.doesNotMatch(fs.readFileSync(file,'utf8'), /\bany\b/,
  `Explicit any in application source: ${file}`);
const formats = json('shared/format-registry/formats.json');
const matrix = json('shared/format-registry/conversion-matrix.json');
const metadata = json('entry/src/main/resources/rawfile/format-registry/manifest.json');
for (const name of ['formats.json','conversion-matrix.json']) {
  const source = read(`shared/format-registry/${name}`);
  assert.ok(source.equals(read(`entry/src/main/resources/rawfile/format-registry/${name}`)),
    `Packaged rawfile differs: ${name}`);
  const historical=read(`docs/migration-source/shared/format-registry/${name}`);
  if(name==='conversion-matrix.json') {
    const approved=JSON.parse(historical);
    approved.routes.find(route=>route.id==='jpeg-pdf').status='experimental';
    approved.notes='JPEG to PDF is experimental for explicit Debug testing only; other routes remain planned. Lower-fidelity relay requires explicit user approval and cannot satisfy a higher minimum tier.';
    assert.deepEqual(JSON.parse(source),approved,'Configuration changes exceed approved JPEG Debug repair');
  } else assert.ok(source.equals(historical),`Original configuration lost: ${name}`);
}
assert.equal(metadata.formatsSha256, hash(read('shared/format-registry/formats.json')));
assert.equal(metadata.matrixSha256, hash(read('shared/format-registry/conversion-matrix.json')));
const generated = text('entry/src/main/ets/generated/RegistryData.ets');
const pinnedMetadata = JSON.parse(generated.match(/export const registryMetadata: RegistryMetadata = ([\s\S]*?);\n/)[1]);
assert.deepEqual(pinnedMetadata,metadata);
assert.equal(pinnedMetadata.formatsCount,formats.formats.length);
assert.equal(pinnedMetadata.routesCount,matrix.routes.length);
const catalogueFiles=['Pdf','Office','Text','Image','Media'];
const bundledFormats=catalogueFiles.flatMap(name=>JSON.parse(text(`entry/src/main/ets/generated/catalogue/${name}.ets`)
  .match(/export function createFormats\(\): RegistryFormat\[\] \{ return ([\s\S]*?); \}/)[1]))
  .sort((a,b)=>formats.formats.findIndex(item=>item.id===a.id)-formats.formats.findIndex(item=>item.id===b.id));
const bundledRoutes=catalogueFiles.flatMap(name=>JSON.parse(text(`entry/src/main/ets/generated/catalogue/${name}.ets`)
  .match(/export function createRoutes\(\): ConversionRouteDefinition\[\] \{ return ([\s\S]*?); \}/)[1]))
  .sort((a,b)=>matrix.routes.findIndex(item=>item.id===a.id)-matrix.routes.findIndex(item=>item.id===b.id));
assert.deepEqual(bundledFormats,formats.formats,'Offline catalogue lost approved formats');
assert.deepEqual(bundledRoutes,matrix.routes,'Offline catalogue changed approved route definitions');
assert.ok(matrix.routes.every(route=>route.status===(route.id==='jpeg-pdf'?'experimental':'planned')),
  'Only the approved JPEG Debug route may be experimental');
for (const id of formats.engineIds) {
  const engine = `entry/src/main/cpp/engines/${id}/${id}_converter.cpp`;
  assert.ok(fs.existsSync(path.join(root,engine)),`Engine entry missing: ${id}`);
  assert.match(text('entry/src/main/cpp/generated/engine_sources.cmake'),new RegExp(`engines/${id}/${id}_converter\\.cpp`));
}
assert.equal(json('entry/src/main/resources/base/profile/backup_config.json').allowToBackupRestore,false);
assert.doesNotMatch(text('entry/src/main/module.json5'),/ohos\.permission\.INTERNET/);
const backup = path.resolve(root,'../migration-backups/harmonyOS-before-outputs-migration-20260928');
let originalProjectFilesRetained = null;
let originalProjectChanges = [];
if (fs.existsSync(backup)) {
  const baseline = walk(backup);
  originalProjectFilesRetained = baseline.length;
  for (const original of baseline) {
    const relative = path.relative(backup,original);
    assert.ok(fs.existsSync(path.join(root,relative)),`Original project file removed: ${relative}`);
    if (!fs.readFileSync(original).equals(read(relative))) originalProjectChanges.push(relative.replaceAll('\\','/'));
  }
}
const report = {scope:'migration_integrity_not_runtime_conversion',result:'passed',
  exactSourceSnapshots:records.length,originalOutputFilesChecked:records.filter(record=>
    fs.existsSync(path.join(manifest.source,record.source))).length,
  originalProjectFilesRetained,originalProjectChanges,nativeMethodsPreserved:methods.length,
  formats:formats.formats.length,plannedRoutes:matrix.routes.filter(route=>route.status==='planned').length,
  experimentalRoutes:matrix.routes.filter(route=>route.status==='experimental').length,availableRoutes:0,
  generatedProtocolEquivalent:true,configCopiesByteIdentical:true,
  realConversion:'not_executed',deviceValidation:'not_executed',records};
fs.mkdirSync(path.join(root,'tests/generated'),{recursive:true});
fs.writeFileSync(path.join(root,'tests/generated/migration-check-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,records:undefined},null,2));
