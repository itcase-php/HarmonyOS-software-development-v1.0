'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'entry/src/main/ets');
const ts = require(process.env.HDM_TYPESCRIPT_PATH ||
  'D:/DevEco Studio2026/DevEco Studio/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const definitions = new Map(), cases = [];
for (const name of ['NativeProtocol', 'RegistryTypes', 'SessionModels']) {
  const file = path.join(source, 'models', name + '.ets');
  const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
  for (const node of ast.statements) {
    if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) definitions.set(node.name.text, node);
  }
}
function members(name) {
  const node = definitions.get(name); assert.ok(node, 'Unknown DTO ' + name);
  return (node.heritageClauses || []).flatMap(clause => clause.types.flatMap(base => members(base.expression.text)))
    .concat(Array.from(node.members || []));
}
// Derive fields from the schema, never from the copy implementation: a newly added
// required or optional field fails these tests until its ownership copy is updated.
function sample(type, mode) {
  if (ts.isParenthesizedTypeNode(type)) return sample(type.type, mode);
  if (ts.isArrayTypeNode(type)) return [sample(type.elementType, mode)];
  if (ts.isUnionTypeNode(type)) return sample(type.types[0], mode);
  if (ts.isLiteralTypeNode(type)) {
    if (ts.isStringLiteral(type.literal)) return type.literal.text;
    if (ts.isNumericLiteral(type.literal)) return Number(type.literal.text);
    return type.literal.kind === ts.SyntaxKind.TrueKeyword;
  }
  if (type.kind === ts.SyntaxKind.StringKeyword) return 'field-value';
  if (type.kind === ts.SyntaxKind.NumberKeyword) return 37;
  if (type.kind === ts.SyntaxKind.BooleanKeyword) return true;
  if (ts.isTypeReferenceNode(type)) {
    const definition = definitions.get(type.typeName.text); assert.ok(definition, type.getText());
    return ts.isTypeAliasDeclaration(definition) ? sample(definition.type, mode) : dto(definition.name.text, mode);
  }
  throw new Error('Add fixture support for schema type ' + type.getText());
}
function dto(name, mode) {
  const value = {};
  for (const member of members(name)) {
    assert.ok(ts.isPropertySignature(member), 'Only data DTOs belong in this test');
    if (member.questionToken && mode === 'absent') continue;
    value[member.name.text] = member.questionToken && mode === 'undefined' ? undefined : sample(member.type, mode);
  }
  return value;
}
function owned(input, copy, at = 'root') {
  if (!input || typeof input !== 'object') return;
  assert.notEqual(copy, input, 'Shared mutable reference at ' + at);
  assert.deepEqual(Object.keys(copy).sort(), Object.keys(input).sort(), 'Field omission at ' + at);
  for (const key of Object.keys(input)) owned(input[key], copy[key], at + '.' + key);
}
function mutate(value) {
  if (!value || typeof value !== 'object') return;
  for (const key of Object.keys(value)) {
    if (value[key] && typeof value[key] === 'object') mutate(value[key]);
    else value[key] = 'changed';
  }
  if (Array.isArray(value)) value.push('added');
}
async function test(name, fn) { await fn(); cases.push({name, result:'passed'}); }
async function main() {
  const h = host();
  for (const className of ['SessionSnapshot', 'ConversionSnapshot', 'RegistrySnapshotCopy']) {
    const api = h.load('./models/' + className)[className];
    for (const method of Object.getOwnPropertyNames(api).filter(name => name.startsWith('copy'))) {
      const typeName = method.slice(4);
      await test(className + '.' + method + ' covers schema fields, optional presence and nested ownership', () => {
        for (const mode of ['present', 'absent', 'undefined']) {
          const input = dto(typeName, mode), before = structuredClone(input), copy = api[method](input);
          assert.deepEqual(structuredClone(copy), before); owned(input, copy);
          mutate(copy); assert.deepEqual(input, before);
        }
      });
    }
  }
  await test('Registry preserves full catalogue order, aliases, categories and copy isolation', () => {
    const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
    const expected = JSON.parse(fs.readFileSync(path.join(root, 'shared/format-registry/formats.json'), 'utf8')).formats;
    const matrix = JSON.parse(fs.readFileSync(path.join(root, 'shared/format-registry/conversion-matrix.json'), 'utf8')).routes;
    assert.equal(expected.length, 18); assert.equal(matrix.length, 43);
    assert.deepEqual(structuredClone(registry.listFormats()), expected);
    for (const format of expected) {
      for (const name of [format.id, ...format.extensions]) {
        assert.deepEqual(structuredClone(registry.getFormat(' .' + name.toUpperCase() + ' ')), format);
      }
      const fetched = registry.getFormat(format.id); mutate(fetched);
      assert.deepEqual(structuredClone(registry.getFormat(format.id)), format);
    }
    for (const category of ['pdf', 'office', 'text', 'image', 'audio', 'unknown']) {
      assert.deepEqual(structuredClone(registry.getFormatsByCategory(category)), expected.filter(f => f.category === category));
    }
    const metadata = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/format-registry/manifest.json'), 'utf8'));
    for (const alias of metadata.migrationAliases) assert.equal(registry.normalizeFormat(alias.from), alias.to);
    assert.equal(registry.getFormat('unknown'), undefined);
    const ids = ['wav', 'jpg', 'pdf', 'pdf', 'unknown'];
    assert.deepEqual(Array.from(registry.getFormatsByIds(ids), f => f.id), expected.filter(f => ['wav','jpeg','pdf'].includes(f.id)).map(f => f.id));
    assert.deepEqual(structuredClone(registry.listPlannedRoutes()), matrix);
  });
  await test('Warm ID and planner lookup copy only selected formats and never copy the full list', () => {
    const registry = h.load('./services/FormatRegistry').FormatRegistry.shared(); registry.getFormat('pdf');
    const copier = h.load('./models/RegistrySnapshotCopy').RegistrySnapshotCopy;
    const original = copier.copyRegistryFormat; let copies = 0;
    copier.copyRegistryFormat = value => { copies++; return original(value); };
    const list = registry.listFormats; registry.listFormats = () => { throw new Error('Full-list query used'); };
    try {
      assert.equal(registry.getFormat('pdf').id, 'pdf'); assert.equal(copies, 1);
      copies = 0; const targets = h.planner.targets('jpeg');
      assert.equal(copies, targets.length); assert.ok(targets.length > 0);
      assert.equal(h.planner.validateFileName('input.JPG', 'jpeg'), 'input.JPG');
    } finally { registry.listFormats = list; copier.copyRegistryFormat = original; }
  });
  await test('Cold category loading copies once; verified install atomically rebuilds the lookup revision', async () => {
    const {FormatRegistryService} = h.load('./services/FormatRegistry'); const registry = new FormatRegistryService();
    const copier = h.load('./models/RegistrySnapshotCopy').RegistrySnapshotCopy, original = copier.copyRegistryFormat; let count = 0;
    copier.copyRegistryFormat = value => { count++; return original(value); };
    try {
      const images = registry.listFormats('image'); assert.equal(count, images.length);
      assert.equal(registry.formatCategories.size, 1); assert.equal(registry.getFormat('jpg').id, 'jpeg');
      const before = registry.lookupRevision; await registry.initialize(h.resources);
      assert.equal(registry.getFormat('jpg').id, 'jpeg'); assert.equal(registry.lookupRevision, before + 1);
      assert.equal(registry.formatsByCategory.get('image').length, images.length);
      await assert.rejects(registry.verifyBundledResources({getRawFileContent: async () => new Uint8Array([1])}), e => e.code === 'CONFIG_INVALID');
      assert.equal(registry.lookupRevision, before + 1); assert.equal(registry.listFormats().length, 18);
    } finally { copier.copyRegistryFormat = original; }
  });
  await test('History eviction scans backwards without slice/reverse and protects the oldest active item', () => {
    const store = h.store, {DemoTask} = h.load('./models/InteractionModels');
    for (let i = 0; i < 100; ++i) { const task = new DemoTask(); task.id = 't' + i; task.status = 'completed'; store.tasks.unshift(task); }
    store.tasks[99].status = 'paused'; store.tasks.slice = store.tasks.reverse = () => { throw new Error('History was copied'); };
    store.ensureCapacity(); assert.equal(store.tasks.length, 99);
    assert.ok(store.tasks.some(t => t.id === 't0')); assert.ok(!store.tasks.some(t => t.id === 't1'));
    store.shutdown();
  });
  await test('Production ownership snapshots no longer serialize and compatibility APIs remain', () => {
    function files(dir) { return fs.readdirSync(dir, {withFileTypes:true}).flatMap(entry => entry.isDirectory() ? files(path.join(dir, entry.name)) : [path.join(dir,entry.name)]); }
    for (const file of files(source).filter(file => file.endsWith('.ets'))) {
      assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /JSON\.parse\(JSON\.stringify\(/, file);
    }
    for (const [name, subdir] of [['FormatRegistry','services'],['NativeBridge','services'],['NativeTaskRunner','services'],['TaskStore','viewmodel']]) {
      assert.match(fs.readFileSync(path.join(source,subdir,name+'.ets'),'utf8'), /@deprecated[\s\S]*?static shared\(/);
    }
    assert.match(fs.readFileSync(path.join(source,'services/FileAuthorizationService.ets'),'utf8'), /@deprecated[\s\S]*?private static current\(/);
  });
  h.store.shutdown();
  const report = {scope:'real_ArkTS_logic_with_host_SDK_adapters', result:'passed', testedCases:cases.length, cases,
    schemaCoverage:'derived_from_type_declarations_including_optional_fields', deviceExecution:'not_executed'};
  fs.writeFileSync(path.join(root,'tests/generated/copy-safety-check-report.json'), JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({result:report.result,testedCases:report.testedCases}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
