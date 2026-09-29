'use strict';
// Rebuild reviewable document views from the single master design.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const master = fs.readFileSync(path.join(root, 'V1.0初步功能开发方案.md'), 'utf8');
const out = path.join(root, 'docs');
fs.mkdirSync(out, {recursive:true});
function section(start, end) {
  const a = master.indexOf(start), b = end ? master.indexOf(end, a + start.length) : master.length;
  if (a < 0 || b < a) throw new Error(`Missing section ${start}`);
  return master.slice(a,b).trim();
}
const docs = {
  'ARCHITECTURE.md': ['架构与分层设计', section('### 整体架构图与分层数据流','## 3.共享配置') + '\n\n' + section('## 单文件完整转换时序与流程','## 4.文档')],
  'CONVERSION_MATRIX.md': ['转换矩阵：用户版与开发版', section('### 转换矩阵文档：用户版与开发版','### AI 编程规则')],
  'AI_CODING_RULES.md': ['AI 编程规则', section('### AI 编程规则','### 隐私设计')],
  'PRIVACY.md': ['隐私设计与政策全文草案', section('### 隐私设计','### 错误码文档')],
  'ERROR_CODES.md': ['错误码：开发与用户版', section('### 错误码文档','### 保真策略文档')],
  'FIDELITY_POLICY.md': ['保真策略', section('### 保真策略文档','### 上架检查清单')],
  'RELEASE_CHECKLIST.md': ['上架检查清单', section('### 上架检查清单','## 5.测试')]
};
for (const [file,[title,body]] of Object.entries(docs)) {
  fs.writeFileSync(path.join(out,file),`# ${title}\n\n来源：本交付包主方案，2026-09-28。设计稿，非已实现/已验收声明。本文由 tools/assemble-docs.cjs 生成，修改主方案后重新生成。\n\n${body}\n`);
}
const matrix = JSON.parse(fs.readFileSync(path.join(root,'shared/format-registry/conversion-matrix.json'),'utf8'));
const lines = ['','## 配置中的全部43条设计路线','',
  '| routeId | 输入 | 输出 | 操作 | 形态/意图 | 等级/引擎 | 阶段/状态 |',
  '| --- | --- | --- | --- | --- | --- | --- |'];
for (const r of matrix.routes) lines.push(`| ${r.id} | ${r.from.join('/')} | ${r.to} | ${r.operation} | ${r.pathMode}/${r.intent} | ${r.fidelityTier}/${r.engineIds.join('+')} | M${r.phase}/${r.status} |`);
lines.push('','这些是设计目标。正式开发版需逐route补齐inputSubset、具体engine版本/ABI/codec、已知限制、fixture与验收证据；当前全部planned。','');
fs.appendFileSync(path.join(out,'CONVERSION_MATRIX.md'),lines.join('\n'));
console.log(JSON.stringify({generatedDocuments:Object.keys(docs),routes:matrix.routes.length}));
