'use strict';
// Aggregate completed runs; this inspector does not execute tests or install a HAP.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/^\uFEFF/, '');
const json = name => JSON.parse(read(name));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hostReports = ['interaction','fidelity','refactor','hypium-host','audit','input-management','architecture','copy-safety']
  .map(name => 'tests/generated/' + name + '-check-report.json');
const hostChecks = hostReports.map(name => {
  const report = json(name); assert.equal(report.result, 'passed', name);
  assert.ok(report.testedCases > 0); return {report:name, passed:report.testedCases};
});
const cppLog = 'tests/generated/native-readiness-cpp-tests.log';
assert.match(read(cppLog), /100% tests passed.*out of 13/);
const prototypeLog = 'tests/generated/jpeg-pdf-prototype-ctest.log';
assert.match(read(prototypeLog), /100% tests passed.*out of 4/);
const prototype = json('tests/generated/jpeg-pdf-prototype-integration.json');
assert.equal(prototype.result, 'passed'); assert.equal(prototype.testedCases, 15);
assert.equal(prototype.applicationIntegrated, false); assert.equal(prototype.realRoutesAvailable, 0);
for (const name of ['rgb','gray_300dpi','large_multichunk']) {
  const item = prototype.cases.find(value => value.case === name);
  assert.ok(item && item.embeddedJpegIdentical, 'Prototype payload evidence absent: '+name);
}
const buildLogs = ['step1','step2','step3','final-app','final-test'].map(name =>
  'tests/generated/native-readiness-' + name + '-build.log');
for (const name of buildLogs) assert.match(read(name), /BUILD SUCCESSFUL/, name);
const preservation = json('tests/generated/native-readiness-preservation-report.json');
assert.equal(preservation.result, 'passed');
const packageInspection = json('tests/generated/hap-package-report.json');
assert.equal(packageInspection.result, 'passed'); assert.equal(packageInspection.rawfileMatchesSource, true);
const exclusion = json('tests/generated/native-readiness-package-exclusion.json');
assert.equal(exclusion.result, 'passed'); assert.equal(exclusion.hostTestsPackaged, false);
const nativeBuilds = ['arm64-v8a','x86_64'].map(abi => {
  const prefix = 'entry/.cxx/default/default/debug/' + abi + '/';
  const commands = json(prefix + 'compile_commands.json');
  for (const item of commands) assert.match(item.command, /-O0.*-std=gnu\+\+17.*-Wall -Wextra -Wpedantic/);
  assert.match(read(prefix+'CMakeCache.txt'), /HDM_BUILD_HOST_TESTS:BOOL=OFF/);
  return {abi, target:'OHOS', mode:'debug', optimisation:'SDK -O0', cxxStandard:17, hostTests:false};
});
const artifacts = ['default/entry-default-unsigned.hap','ohosTest/entry-ohosTest-unsigned.hap'].map(name => {
  const file = 'entry/build/default/outputs/' + name, bytes = fs.readFileSync(path.join(root,file));
  return {path:file, bytes:bytes.length, sha256:sha(bytes), signing:'unsigned'};
});
assert.equal(artifacts[0].sha256, packageInspection.hapSha256);
function sources(dir) {
  return fs.readdirSync(path.join(root,dir), {withFileTypes:true}).flatMap(entry => {
    const name = dir + '/' + entry.name;
    return entry.isDirectory() ? sources(name) : /\.(ets|cpp|h|txt|cmake)$/.test(name) ? [name] : [];
  });
}
const sourceHashes = ['entry/src/main/ets','entry/src/main/cpp','prototypes/jpeg-pdf'].flatMap(sources).map(name =>
  ({path:name, sha256:sha(fs.readFileSync(path.join(root,name)))}));
const report = {scope:'compatible_optimisations_host_build_package_not_device_acceptance', date:'2026-09-30', result:'passed',
  baseCommit:preservation.baseCommit, sddStatus:'compatible_and_isolated_prototype_verified_native_integration_pending_review',
  formats:18, plannedRoutes:43, availableRoutes:0, totalArkTSHostChecks:hostChecks.reduce((sum,item) => sum + item.passed, 0),
  hostChecks, cppTests:{passed:13, framework:'CTest', compiler:'GCC 8.1 C++17 host', log:cppLog,
    mockNapi:'production bridge linked to host model, not system NAPI'},
  isolatedPrototype:{approvedByUser:true, applicationIntegrated:false, cTestPassed:4, integrationPassed:prototype.testedCases,
    independentParser:'pypdf strict', renderer:'Poppler pdftoppm',
    dependency:'libjpeg-turbo 3.1.4.1 official release pinned SHA256 ecae8008e2cc9ade2f2c1bb9d5e6d4fb73e7c433866a056bd82980741571a022',
    log:prototypeLog, report:'tests/generated/jpeg-pdf-prototype-integration.json',
    examples:['output/pdf/isolated-rgb.pdf','output/pdf/isolated-gray_300dpi.pdf','output/pdf/isolated-large_multichunk.pdf']},
  buildLogs, nativeBuilds, artifacts, packageInspection:'tests/generated/hap-package-report.json',
  packageExclusion:'tests/generated/native-readiness-package-exclusion.json',
  preservation:'tests/generated/native-readiness-preservation-report.json', byteIdenticalProtectedFiles:preservation.checkedFiles,
  sourceHashes, builtinEditorCheck:'unavailable; used actual Hvigor', releaseBuild:'not_executed',
  connectedDevices:0, deviceHypium:'not_executed', previewer:'not_executed', realConversion:'not_executed',
  pendingReview:['production Native session/workspace/probe/execute integration','full text/structure fidelity and production evidence'],
  missingSpecification:'M-02 attachment ends at problem location; user confirmed no further text',
  warnings:['SDK crypto system capability','SDK unused gcc-toolchain argument','test template duplicate color','unsigned HAP']};
assert.equal(report.totalArkTSHostChecks, 205);
fs.writeFileSync(path.join(root,'tests/generated/native-readiness-validation-report.json'), JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({result:report.result, arkTSChecks:report.totalArkTSHostChecks, cppChecks:13, protectedFiles:preservation.checkedFiles}));
