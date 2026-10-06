/* Dependency-free design checks; does NOT execute engines, ArkTS, NAPI, or devices. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
const formats = read('shared/format-registry/formats.json');
const matrix = read('shared/format-registry/conversion-matrix.json');
const debugPolicy = read('shared/format-registry/debug-routes.json');
assert.deepEqual(debugPolicy, {schemaVersion:1, routeIds:['jpeg-pdf']});
const formatSchema = read('shared/format-registry/schema/formats.schema.json');
const matrixSchema = read('shared/format-registry/schema/conversion-matrix.schema.json');

// Validates only the explicitly used schema vocabulary; production must use a
// reviewed full JSON Schema validator and cryptographic config-pack validation.
function validateSchema(schema, value, location = '$', depth = 0) {
  assert.ok(depth < 64, `${location}: excessive nesting`);
  if (schema.const !== undefined) assert.deepEqual(value, schema.const, location);
  if (schema.enum) assert.ok(schema.enum.includes(value), `${location}: enum`);
  if (schema.type) {
    const valid = schema.type === 'object' ? value !== null && typeof value === 'object' && !Array.isArray(value)
      : schema.type === 'array' ? Array.isArray(value)
      : schema.type === 'integer' ? Number.isSafeInteger(value)
      : schema.type === 'number' ? typeof value === 'number' && Number.isFinite(value)
      : typeof value === schema.type;
    assert.ok(valid, `${location}: ${schema.type}`);
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined) assert.ok(value >= schema.minimum, location);
    if (schema.maximum !== undefined) assert.ok(value <= schema.maximum, location);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined) assert.ok(value.length >= schema.minLength, location);
    if (schema.maxLength !== undefined) assert.ok(value.length <= schema.maxLength, location);
    if (schema.pattern) assert.match(value, new RegExp(schema.pattern), location);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined) assert.ok(value.length >= schema.minItems, location);
    if (schema.maxItems !== undefined) assert.ok(value.length <= schema.maxItems, location);
    if (schema.uniqueItems) assert.equal(new Set(value.map(x => JSON.stringify(x))).size, value.length, location);
    if (schema.items) value.forEach((x, i) => validateSchema(schema.items, x, `${location}[${i}]`, depth + 1));
  }
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    for (const key of schema.required || []) assert.ok(Object.hasOwn(value, key), `${location}: missing ${key}`);
    for (const [key, x] of Object.entries(value)) {
      if (schema.properties && schema.properties[key]) validateSchema(schema.properties[key], x, `${location}.${key}`, depth + 1);
      else if (schema.additionalProperties === false) assert.fail(`${location}: unexpected ${key}`);
    }
  }
  const matches = sub => { try { validateSchema(sub, value, location, depth + 1); return true; } catch { return false; } };
  if (schema.oneOf) assert.equal(schema.oneOf.filter(matches).length, 1, `${location}: oneOf`);
  if (schema.anyOf) assert.ok(schema.anyOf.some(matches), `${location}: anyOf`);
  if (schema.not) assert.ok(!matches(schema.not), `${location}: not`);
}
function validateGraph(f, m) {
  validateSchema(formatSchema, f);
  validateSchema(matrixSchema, m);
  assert.equal(f.status, 'planned', 'this delivery is a design, not release metadata');
  assert.equal(f.configVersion, m.configVersion);
  const ids = new Map(f.formats.map(x => [x.id, x]));
  assert.equal(ids.size, f.formats.length, 'duplicate format ID');
  const suffixes = f.formats.flatMap(x => x.extensions);
  assert.equal(new Set(suffixes).size, suffixes.length, 'duplicate suffix');
  for (const b of f.blockedFormats) assert.ok(!ids.has(b) && !suffixes.includes(b), 'blocked format registered');
  const routes = new Map(m.routes.map(x => [x.id, x]));
  assert.equal(routes.size, m.routes.length, 'duplicate route ID');
  const tiers = { extreme: 0, standard: 1, compatible: 2 };
  for (const r of m.routes) {
    assert.equal(r.status, debugPolicy.routeIds.includes(r.id) ? 'experimental' : 'planned',
      'only approved Debug routes may be experimental; no release availability');
    for (const s of r.from) assert.ok(ids.has(s) && ids.get(s).operations.includes('import'), 'source import');
    assert.ok(ids.has(r.to) && ids.get(r.to).operations.includes('export'), 'target export');
    assert.ok(r.inputConstraints.minInputs <= r.inputConstraints.maxInputs);
    assert.ok(f.optionsProfileIds.includes(r.optionsProfileId));
    assert.ok(f.validationProfileIds.includes(r.validationProfileId));
    assert.ok(r.steps.length <= m.maxRouteSteps);
    assert.equal(r.pathMode === 'direct', r.steps.length === 1, 'direct/relay mismatch');
    assert.equal(r.steps[r.steps.length - 1].outputFormatId, r.to, 'final format mismatch');
    for (const source of r.from) assert.ok(r.steps[0].inputFormatIds.includes(source), 'first step source');
    for (let i = 0; i < r.steps.length; i++) {
      const step = r.steps[i];
      assert.ok(step.engineIds.includes(step.executorEngineId), 'missing executor');
      assert.ok(ids.has(step.outputFormatId), 'step output missing');
      for (const source of step.inputFormatIds) assert.ok(ids.has(source), 'step input missing');
      for (const engine of step.engineIds) assert.ok(f.engineIds.includes(engine) && r.engineIds.includes(engine), 'unknown engine');
      if (i > 0) assert.ok(step.inputFormatIds.includes(r.steps[i - 1].outputFormatId), 'relay type mismatch');
    }
    for (const id of r.fallbackRouteIds) {
      const alt = routes.get(id);
      assert.ok(alt, 'missing fallback');
      assert.equal(alt.operation, r.operation);
      assert.equal(alt.to, r.to);
      assert.equal(alt.intent, r.intent, 'fallback changes intent');
      assert.deepEqual([...alt.from].sort(), [...r.from].sort(), 'fallback changes source set');
      if (tiers[alt.fidelityTier] > tiers[r.fidelityTier]) assert.ok(alt.requiresUserApproval, 'silent fidelity loss');
    }
  }
  const visiting = new Set(), done = new Set();
  function visit(id) {
    assert.ok(!visiting.has(id), 'fallback cycle');
    if (done.has(id)) return;
    visiting.add(id);
    for (const next of routes.get(id).fallbackRouteIds) visit(next);
    visiting.delete(id); done.add(id);
  }
  for (const id of routes.keys()) visit(id);
  for (const a of f.migrationAliases) assert.ok(ids.has(a.to) && !ids.has(a.from), 'invalid alias');
}
validateGraph(formats, matrix);
const clone = x => JSON.parse(JSON.stringify(x));
const mutations = [
  ['duplicate format', (f) => f.formats.push(clone(f.formats[0]))],
  ['blocked suffix', (f) => f.formats[0].extensions.push(f.blockedFormats[0])],
  ['unknown target', (f, m) => { m.routes[0].to = 'unregistered'; }],
  ['fallback cycle', (f, m) => { m.routes[0].fallbackRouteIds = [m.routes[0].id]; }],
  ['silent downgrade', (f, m) => { m.routes.find(r => r.id === 'png-pdf-compatible').requiresUserApproval = false; }],
  ['invalid metadata option', (f) => { f.formats[6].defaultOptions[0].booleanValue = true; }],
  ['false available', (f, m) => { m.routes[0].status = 'available'; }],
  ['unapproved experimental', (f, m) => { m.routes[1].status = 'experimental'; }],
  ['protection enabled', (f) => { f.securityPolicy.allowDrm = true; }],
  ['relay broken', (f, m) => { m.routes.find(r => r.pathMode === 'relay').steps[1].inputFormatIds = ['png']; }],
  ['nonfinite budget', (f) => { f.resourceProfiles.default.maxNativeBytes = Infinity; }]
];
for (const [name, mutate] of mutations) {
  const f = clone(formats), m = clone(matrix); mutate(f, m);
  assert.throws(() => validateGraph(f, m), undefined, `negative design check: ${name}`);
}
const ets = fs.readFileSync(path.join(root, 'entry/src/main/ets/models/NativeProtocol.ets'), 'utf8');
const cpp = fs.readFileSync(path.join(root, 'entry/src/main/cpp/core/converter.h'), 'utf8');
assert.ok(!/\b(any|unknown)\b/.test(ets.replace(/\/\/[^\n]*/g, '').replace(/'unknown'/g, '')));
assert.match(ets, /offlineOnly: boolean/);
assert.match(ets, /outputs: Artifact\[\]/);
assert.match(ets, /inputs: PreparedInput\[\]/);
const cppCodes = [...cpp.matchAll(/return "([A-Z_]+)";/g)].map(x => x[1]).filter(x => x !== 'OK');
for (const code of new Set(cppCodes)) assert.ok(ets.includes(`'${code}'`), `missing TS error ${code}`);
const tsErrorDefinition = ets.match(/export type ErrorCode = ([\s\S]*?);/)[1];
const tsCodes = [...tsErrorDefinition.matchAll(/'([A-Z_]+)'/g)].map(x => x[1]);
assert.deepEqual([...new Set(cppCodes)].sort(), [...new Set(tsCodes)].sort(), 'error-code sets differ');
function cppStructBody(name) {
  const declaration = cpp.match(new RegExp(`struct ${name} \\{`));
  assert.ok(declaration, `missing C++ struct ${name}`);
  const start = declaration.index + declaration[0].length;
  let nesting = 1;
  for (let i = start; i < cpp.length; i++) {
    if (cpp[i] === '{') nesting++;
    if (cpp[i] === '}' && --nesting === 0) return cpp.slice(start, i);
  }
  assert.fail(`unclosed struct ${name}`);
}
for (const name of ['PreparedInput','ResourceBudget','PlanStep','ApprovedPlan','ConvertRequest',
  'Metric','FidelityReport','ConversionWarning','Artifact','Validation','EngineStamp','ConvertResult',
  'ProgressEvent','RouteCapability','CapabilityMatrix','CapabilityRequest','ProbeRequest','InputProbe',
  'SessionInit','WorkspaceGrant','PdfOptions','ImageOptions','OfficeOptions','AudioOptions','OcrOptions','ConvertOptions']) {
  const tsBlock = ets.match(new RegExp(`export interface ${name} \\{([\\s\\S]*?)\\}`))[1].replace(/\/\/[^\n]*/g, '');
  const cppBlock = cppStructBody(name);
  for (const field of [...tsBlock.matchAll(/\b([A-Za-z][A-Za-z0-9]*)\??\s*:/g)].map(x=>x[1]))
    assert.match(cppBlock, new RegExp(`\\b${field}\\b`), `${name}.${field} missing in C++`);
}
const doc = fs.readFileSync(path.join(root, 'V1.0初步功能开发方案.md'), 'utf8');
const fixed = [
  '1.ArkTS 层：页面、组件、模型、格式注册、转换规划、任务管理、NativeBridge',
  '2.C++ 层：NAPI 入口、转换器接口、错误码、IR 结构、资源限制、保真校验、PDF/Office/Media/Image/OCR 引擎占位',
  '3.共享配置：formats.json、conversion-matrix.json',
  '4.文档：架构、转换矩阵、AI 编程规则、隐私、错误码、保真策略、上架检查清单',
  '5.测试：格式矩阵和 DRM 类格式阻断测试'
];
let pos = -1;
for (const text of fixed) { const next = doc.indexOf(text); assert.ok(next > pos, 'fixed module order'); pos = next; }
// Preserve every existing 18-edge direction, with the explicit jpg->jpeg migration.
const baselinePairs = [ ['pdf','png'], ['pdf','jpeg'], ['jpeg','pdf'], ['png','pdf'],
  ['docx','pdf'], ['pptx','pdf'], ['pdf','docx'], ['pdf','pptx'], ['pdf','txt'],
  ['pdf','md'], ['pdf','xlsx'], ['mp3','wav'], ['wav','mp3'], ['flac','mp3'],
  ['aac','mp3'], ['m4a','mp3'], ['ogg','mp3'], ['opus','mp3'] ];
for (const [from, to] of baselinePairs) assert.ok(matrix.routes.some(r => r.from.includes(from) && r.to === to), 'baseline direction lost');
const pairCases = [];
for (const source of formats.formats) for (const target of formats.formats) {
  const candidates = matrix.routes.filter(r => r.from.includes(source.id) && r.to === target.id);
  pairCases.push({source:source.id,target:target.id,routeIds:candidates.map(r=>r.id),
    expectedPlannerOutcome:candidates.length ? 'planned_not_available' : 'unsupported_format',
    requiresRealRuntimeEvidence:true});
}
const routeCases = matrix.routes.map(r => ({routeId:r.id,operation:r.operation,sourceIds:r.from,target:r.to,
  fixtureId:`${r.id}-basic`,fixtureState:'required_not_supplied',expectedOutputFormat:r.to,
  validationProfile:r.validationProfileId,requiredCategories:['basic','complex_supported_subset','corrupted','cancel','resource_limit'],
  requiredIndependentValidation:true,releaseState:'not_executed'}));
const protectionCases = [...formats.blockedFormats.map(format=>({fixtureId:`blocked-${format}`,reason:'DRM_BLOCKED'})),
  {fixtureId:'drm-renamed-as-mp3',reason:'DRM_BLOCKED'},
  {fixtureId:'encrypted-pdf-no-password',reason:'ENCRYPTED_BLOCKED'},
  {fixtureId:'encrypted-pdf-with-password',reason:'ENCRYPTED_BLOCKED'},
  {fixtureId:'encrypted-ooxml',reason:'ENCRYPTED_BLOCKED'},
  {fixtureId:'signed-pdf',reason:'SIGNATURE_BLOCKED'},
  {fixtureId:'signed-ooxml',reason:'SIGNATURE_BLOCKED'},
  {fixtureId:'protection-unknown',reason:'PROTECTION_UNKNOWN'}]
  .map(x=>({...x,fixtureState:'required_not_supplied',expectedError:'PERMISSION_DENIED',
    assertions:{engineCalled:false,outputCount:0,temporaryFilesAfterCleanup:0,sensitiveLogFields:0,originalHashUnchanged:true},
    releaseState:'not_executed'}));
const generated = path.join(root, 'tests', 'generated');
fs.mkdirSync(generated, {recursive:true});
fs.writeFileSync(path.join(generated,'matrix-cases.json'),JSON.stringify({schemaVersion:1,pairCases,routeCases,protectionCases},null,2)+'\n');
const report = {scope:'design_only_see_migration_build_report',designChecks:'passed',formats:formats.formats.length,routes:matrix.routes.length,
  formatPairCases:pairCases.length,routeCases:routeCases.length,protectionCases:protectionCases.length,
  rejectedMalformedDesigns:mutations.length,generatedCaseExecution:'not_executed',
  harmonyOsBuild:'not_executed',realConversion:'not_executed',deviceValidation:'not_executed'};
fs.writeFileSync(path.join(generated,'design-check-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
