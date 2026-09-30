'use strict';
// Preserve approved behaviour/configuration against the actual pre-audit Git tree.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const base = 'e58878fb0d4d19429748b892cfa3716691fa2343';
const names = execFileSync('git', ['ls-tree','-r','--name-only',base], {cwd:root, encoding:'utf8'}).trim().split('\n');
const explicit = new Set([
  'entry/src/main/ets/models/NativeProtocol.ets', 'entry/src/main/ets/models/SessionModels.ets',
  'entry/src/main/ets/models/FidelityReportSnapshot.ets',
  'entry/src/main/cpp/core/converter.h', 'entry/src/main/cpp/core/missing_converter.h',
  'entry/src/main/resources/base/profile/main_pages.json', 'entry/src/main/module.json5',
  'entry/src/main/ets/viewmodel/FidelityPolicy.ets', 'entry/src/main/ets/viewmodel/DemoFidelityReport.ets',
  'entry/src/main/ets/viewmodel/NativeFidelityReport.ets', 'entry/src/main/ets/components/QualitySelector.ets',
  'entry/src/main/ets/pages/ConverterPage.ets', 'build-profile.json5'
]);
const protectedFiles = names.filter(name => explicit.has(name) ||
  name.startsWith('shared/format-registry/') || name.startsWith('entry/src/main/resources/rawfile/format-registry/') ||
  name.startsWith('entry/src/main/cpp/engines/') || name.startsWith('entry/src/main/cpp/types/libentry/') ||
  name.startsWith('entry/src/main/ets/generated/') || name.startsWith('docs/migration-source/'));
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const records = protectedFiles.map(name => {
  const original = execFileSync('git', ['show',base+':'+name], {cwd:root, maxBuffer:10*1024*1024});
  const current = fs.readFileSync(path.join(root,name));
  assert.ok(original.equals(current), 'Approved reference changed: '+name);
  return {path:name, bytes:current.length, sha256:digest(current), byteIdentical:true};
});
const report = {scope:'byte_preservation_not_runtime_acceptance', date:'2026-09-30', result:'passed',
  baseCommit:base, checkedFiles:records.length, protectedBehaviour:'18 formats, 43 routes, fidelity interfaces, page routes, placeholders', records};
fs.writeFileSync(path.join(root,'tests/generated/native-readiness-preservation-report.json'), JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({result:report.result,checkedFiles:records.length}));
