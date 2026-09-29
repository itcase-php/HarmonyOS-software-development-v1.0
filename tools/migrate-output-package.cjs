'use strict';
// One-time migration. The original output package and exact source snapshots are retained.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const source = path.resolve(root, '../outputs/harmony-doc-manager-v1-design');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
function walk(dir) {
  return fs.readdirSync(dir,{withFileTypes:true}).flatMap(entry => entry.isDirectory()
    ? walk(path.join(dir,entry.name)) : [path.join(dir,entry.name)]);
}
function write(relative, data) {
  const target = path.resolve(root,relative);
  if (!target.startsWith(root+path.sep)) throw new Error('Target outside project');
  fs.mkdirSync(path.dirname(target),{recursive:true});
  if (fs.existsSync(target) && !fs.readFileSync(target).equals(Buffer.from(data)))
    throw new Error(`Existing target differs; preserve and merge manually: ${relative}`);
  fs.writeFileSync(target,data);
}
const sourceFiles = walk(source);
const records = [];
for (const file of sourceFiles) {
  const relative = path.relative(source,file).replaceAll('\\','/');
  const bytes = fs.readFileSync(file);
  write(`docs/migration-source/${relative}`,bytes);
  let target = relative, content = bytes;
  if (relative === 'README.md') target = 'docs/reference/DESIGN_README.md';
  if (relative === 'docs/VALIDATION.md') target = 'docs/VALIDATION-DESIGN.md';
  if (relative === 'contracts/converter.h') target = 'entry/src/main/cpp/core/converter.h';
  if (relative === 'contracts/native_bridge.d.ts') {
    target = 'entry/src/main/ets/models/NativeProtocol.ets';
    content = Buffer.from(bytes.toString('utf8')
      .replace('/** Design contract v1. Not a compiled/implemented HarmonyOS binding. */',
        '// Protocol v1 migrated into ArkTS. Implemented binding subset is documented in IMPLEMENTATION_STATUS.md.')
      .replace(/declare const nativeModule: NativeModule;\nexport default nativeModule;\s*$/,'')
    );
  }
  if (relative === 'tests/contract-header-check.cpp')
    content = Buffer.from(bytes.toString('utf8').replace('../contracts/converter.h','../entry/src/main/cpp/core/converter.h'));
  if (relative === 'tests/check-design.cjs')
    content = Buffer.from(bytes.toString('utf8')
      .replaceAll('contracts/native_bridge.d.ts','entry/src/main/ets/models/NativeProtocol.ets')
      .replaceAll('contracts/converter.h','entry/src/main/cpp/core/converter.h'));
  write(target,content);
  records.push({source:relative,target,sourceSha256:hash(bytes),targetSha256:hash(content),
    exactSourceSnapshot:`docs/migration-source/${relative}`,adapted:!bytes.equals(content)});
}
const attachment = 'C:/Users/TX/.codex/attachments/b2b62f60-7252-4610-912f-320962883b20/已粘贴的文本.txt';
const attachmentBytes = fs.readFileSync(attachment);
write('docs/reference/Stage目录说明-用户原文.txt',attachmentBytes);
write('docs/MIGRATION_MANIFEST.json',JSON.stringify({schemaVersion:1,source,root,
  originalOutputFilesUnchanged:true,sourceFiles:sourceFiles.length,records,
  attachment:{source:attachment,target:'docs/reference/Stage目录说明-用户原文.txt',sha256:hash(attachmentBytes)}},null,2)+'\n');
console.log(JSON.stringify({migratedFiles:records.length,exactSnapshots:records.length,sourceRetained:true}));
