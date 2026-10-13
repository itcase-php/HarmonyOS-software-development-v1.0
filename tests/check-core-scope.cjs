'use strict';
// Execute the real registry/planner/bridge with explicit host-only platform models.
const assert = require('node:assert/strict');
const {host} = require('./check-interactions.cjs');
const h = host({debugBuild:true});
const registry = h.load('./services/FormatRegistry').FormatRegistry.shared();
assert.deepEqual(registry.listPlannedRoutes().map(r=>r.id).sort(),
  ['docx-pdf','jpeg-pdf','png-pdf','pptx-pdf']);
assert.deepEqual(registry.listFormats().map(f=>f.id).sort(), ['docx','jpeg','pdf','png','pptx']);
for (const format of registry.listFormats()) assert.deepEqual(Array.from(format.operations), format.id==='pdf'?['export']:['import']);
const planner = new (h.load('./viewmodel/ConversionPlanner').ConversionPlannerService)(registry);
assert.equal(planner.routes('pdf','docx').length,0);
assert.equal(planner.routes('mp3','wav').length,0);
assert.equal(planner.routes('docx','pdf').length,1);
console.log('Four routes selectable; reverse/media routes disabled; definitions retained.');
