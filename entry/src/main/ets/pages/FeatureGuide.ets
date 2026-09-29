import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { FormatRegistry } from '../services/FormatRegistry';
import { registryMetadata } from '../generated/RegistryData';
import { UiFeedback } from '../common/UiFeedback';
import { StatusBadge } from '../components/StatusBadge';

interface CategoryInfo {
  id: string;
  label: string;
  color: string;
}

const CATEGORY_INFOS: CategoryInfo[] = [
  { id: 'pdf', label: 'PDF', color: '#C53030' },
  { id: 'office', label: 'Office', color: '#2563EB' },
  { id: 'image', label: '图片', color: '#7C3AED' },
  { id: 'text', label: '文本', color: '#0D9488' },
  { id: 'audio', label: '音频', color: '#D97706' },
];

function catLabel(catId: string): string {
  for (let i = 0; i < CATEGORY_INFOS.length; i++) {
    if (CATEGORY_INFOS[i].id === catId) {
      return CATEGORY_INFOS[i].label;
    }
  }
  return catId;
}

function catColor(catId: string): string {
  for (let i = 0; i < CATEGORY_INFOS.length; i++) {
    if (CATEGORY_INFOS[i].id === catId) {
      return CATEGORY_INFOS[i].color;
    }
  }
  return '#526077';
}

function intentLabel(value: string): string {
  if (value === 'layout_preserved') { return '保留布局'; }
  if (value === 'structured_rebuild') { return '结构化重建'; }
  if (value === 'content_only') { return '仅内容'; }
  return value;
}

function modeLabel(value: string): string {
  if (value === 'direct') { return '直转'; }
  if (value === 'relay') { return '中转'; }
  return value;
}

function statusColor(value: string): string {
  if (value === 'available') { return '#167644'; }
  if (value === 'experimental') { return '#D97706'; }
  if (value === 'planned') { return '#526077'; }
  if (value === 'unavailable') { return '#C53030'; }
  return '#526077';
}

function statusText(value: string): string {
  if (value === 'available') { return '可用'; }
  if (value === 'experimental') { return '实验性'; }
  if (value === 'planned') { return '规划中'; }
  if (value === 'unavailable') { return '不可用'; }
  return value;
}

function catOrder(cat: string): number {
  if (cat === 'pdf') { return 0; }
  if (cat === 'office') { return 1; }
  if (cat === 'image') { return 2; }
  if (cat === 'text') { return 3; }
  if (cat === 'audio') { return 4; }
  return 99;
}

// ── 纯数据接口（非组件） ──

interface FormatCardData {
  id: string;
  displayName: string;
  category: string;
  extensions: string;
  operations: string;
}

interface RouteItemData {
  id: string;
  targetName: string;
  mode: string;
  intent: string;
  statusT: string;
  statusC: string;
}

interface RouteGroupData {
  sourceName: string;
  sourceCatLbl: string;
  sourceCatClr: string;
  routeItems: RouteItemData[];
}

interface UnavailData {
  description: string;
  statusText: string;
  statusColor: string;
}

// ── 子组件 ──

@Component
export struct FormatSummaryCard {
  @Prop displayName: string = '';
  @Prop formatId: string = '';
  @Prop catLbl: string = '';
  @Prop catClr: string = '';
  @Prop extensions: string = '';
  @Prop operations: string = '';

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        StatusBadge({ text: this.catLbl, color: this.catClr })
        Text(this.displayName).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#172B4D')
      }
      Text(`ID: ${this.formatId}  ·  扩展名: .${this.extensions}`)
        .fontSize(13).fontColor('#526077')
      Text(`操作: ${this.operations}`)
        .fontSize(13).fontColor('#526077')
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding(16).backgroundColor('#FFFFFF').borderRadius(12)
  }
}

@Component
struct HelpRouteRow {
  @Prop targetName: string = '';
  @Prop modeLabel: string = '';
  @Prop intentLabel: string = '';
  @Prop statusText: string = '';
  @Prop statusColor: string = '';

  build() {
    Row({ space: 10 }) {
      Text(this.targetName).fontSize(14).fontColor('#007AFF')
      StatusBadge({ text: this.modeLabel, color: '#526077' })
      StatusBadge({ text: this.intentLabel, color: '#526077' })
      StatusBadge({ text: this.statusText, color: this.statusColor })
    }
  }
}

@Component
struct UnavailRow {
  @Prop description: string = '';
  @Prop statusText: string = '';
  @Prop statusColor: string = '';

  build() {
    Row({ space: 8 }) {
      Text(this.description).fontSize(14).fontColor('#C53030')
      StatusBadge({ text: this.statusText, color: this.statusColor })
    }
  }
}

@Component
struct StepRow {
  @Prop step: string = '';
  @Prop text: string = '';

  build() {
    Row({ space: 12 }) {
      Text(this.step).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .width(24).height(24).textAlign(TextAlign.Center)
        .backgroundColor('#007AFF').borderRadius(12)
      Text(this.text).fontSize(14).fontColor('#172B4D').lineHeight(22)
    }.alignItems(VerticalAlign.Center).width('100%')
  }
}

@Component
struct RouteGroupCard {
  @Prop sourceName: string = '';
  @Prop sourceCatLbl: string = '';
  @Prop sourceCatClr: string = '';
  @Prop routeItems: RouteItemData[] = [];

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        StatusBadge({ text: this.sourceCatLbl, color: this.sourceCatClr })
        Text(`${this.sourceName} →`).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#172B4D')
      }
      ForEach(this.routeItems, (item: RouteItemData) => {
        HelpRouteRow({
          targetName: item.targetName,
          modeLabel: item.mode,
          intentLabel: item.intent,
          statusText: item.statusT,
          statusColor: item.statusC
        })
      }, (item: RouteItemData) => item.id)
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding(16).backgroundColor('#FFFFFF').borderRadius(12)
  }
}

// ── 主页面 ──

@Entry
@Preview
@Component
struct FeatureGuide {
  @State private formatCards: FormatCardData[] = [];
  @State private routeGroups: RouteGroupData[] = [];
  @State private unavailItems: UnavailData[] = [];
  @State private blockedList: string[] = [];

  aboutToAppear(): void {
    const all: RegistryFormat[] = FormatRegistry.listFormats();
    all.sort((a: RegistryFormat, b: RegistryFormat) => catOrder(a.category) - catOrder(b.category));

    const cards: FormatCardData[] = [];
    for (let i = 0; i < all.length; i++) {
      const f: RegistryFormat = all[i];
      cards.push({
        id: f.id,
        displayName: f.displayName,
        category: f.category,
        extensions: f.extensions.join(' .'),
        operations: f.operations.join(' / ')
      });
    }
    this.formatCards = cards;

    const routes: ConversionRouteDefinition[] = FormatRegistry.listPlannedRoutes();

    const groups: RouteGroupData[] = [];
    for (let i = 0; i < all.length; i++) {
      const fmt: RegistryFormat = all[i];
      const items: RouteItemData[] = [];
      for (let j = 0; j < routes.length; j++) {
        const r: ConversionRouteDefinition = routes[j];
        if (r.from.includes(fmt.id) && r.status !== 'unavailable') {
          let targetName: string = r.to;
          for (let k = 0; k < all.length; k++) {
            if (all[k].id === r.to) {
              targetName = all[k].displayName;
              break;
            }
          }
          items.push({
            id: r.id,
            targetName: targetName,
            mode: modeLabel(r.pathMode),
            intent: intentLabel(r.intent),
            statusT: statusText(r.status),
            statusC: statusColor(r.status)
          });
        }
      }
      if (items.length > 0) {
        groups.push({
          sourceName: fmt.displayName,
          sourceCatLbl: catLabel(fmt.category),
          sourceCatClr: catColor(fmt.category),
          routeItems: items
        });
      }
    }
    this.routeGroups = groups;

    const unavails: UnavailData[] = [];
    for (let i = 0; i < routes.length; i++) {
      const r: ConversionRouteDefinition = routes[i];
      if (r.status === 'unavailable' || r.status === 'planned') {
        const fromNames: string[] = [];
        for (let j = 0; j < r.from.length; j++) {
          const id: string = r.from[j];
          let found: boolean = false;
          for (let k = 0; k < all.length; k++) {
            if (all[k].id === id) {
              fromNames.push(all[k].displayName);
              found = true;
              break;
            }
          }
          if (!found) {
            fromNames.push(id);
          }
        }
        let toName: string = r.to;
        for (let k = 0; k < all.length; k++) {
          if (all[k].id === r.to) {
            toName = all[k].displayName;
            break;
          }
        }
        unavails.push({
          description: `${fromNames.join(', ')} → ${toName}`,
          statusText: statusText(r.status),
          statusColor: statusColor(r.status)
        });
      }
    }
    this.unavailItems = unavails;

    this.blockedList = registryMetadata.blockedFormats;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        // 顶部导航
        Row({ space: 12 }) {
          Button('‹ 返回').fontSize(14).type(ButtonType.Normal).backgroundColor('#E5ECF5').fontColor('#172B4D')
            .onClick(() => { UiFeedback.back(this.getUIContext()); })
          Text('功能说明').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#172B4D').layoutWeight(1)
        }.width('100%')

        // 概述
        Column({ space: 8 }) {
          Text('文档转换工具箱支持多种格式的互相转换，包括 PDF、Office 文档、图片、文本和音频文件。')
            .fontSize(14).fontColor('#526077').lineHeight(22)
        }
        .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12)

        // 一、支持的格式一览
        Text('一、支持的格式一览').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#172B4D').margin({ top: 8 })

        ForEach(this.formatCards, (card: FormatCardData) => {
          FormatSummaryCard({
            displayName: card.displayName,
            formatId: card.id,
            catLbl: catLabel(card.category),
            catClr: catColor(card.category),
            extensions: card.extensions,
            operations: card.operations
          })
        }, (card: FormatCardData) => card.id)

        // 二、可执行的转换路线
        Text('二、可执行的转换路线').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#172B4D').margin({ top: 8 })

        Text('以下为已规划的转换路线，按源格式分组展示目标格式与转换方式。')
          .fontSize(14).fontColor('#526077').lineHeight(22)

        ForEach(this.routeGroups, (group: RouteGroupData) => {
          RouteGroupCard({
            sourceName: group.sourceName,
            sourceCatLbl: group.sourceCatLbl,
            sourceCatClr: group.sourceCatClr,
            routeItems: group.routeItems
          })
        }, (group: RouteGroupData) => `rg-${group.sourceName}`)

        // 三、不兼容与不适合转换的格式
        Text('三、不兼容与不适合转换的格式').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#172B4D').margin({ top: 8 })

        // 3a. 封锁格式
        Column({ space: 10 }) {
          Text('因版权或技术原因，以下格式被封锁，不可作为输入：')
            .fontSize(14).fontColor('#526077').lineHeight(22)
          Column() {
            ForEach(this.blockedList, (blocked: string) => {
              StatusBadge({ text: `.${blocked}`, color: '#C53030' })
            }, (blocked: string) => blocked)
          }
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .padding(16).backgroundColor('#FFFFFF').borderRadius(12)

        // 3b. 不可用路线
        Column({ space: 10 }) {
          Text('以下转换路线当前不可用（规划中或实验性），不建议用于生产环境：')
            .fontSize(14).fontColor('#526077').lineHeight(22)
          Column() {
            ForEach(this.unavailItems, (item: UnavailData) => {
              UnavailRow({
                description: item.description,
                statusText: item.statusText,
                statusColor: item.statusColor
              })
            }, (_item: UnavailData, index: number) => `ua-${index}`)
          }
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .padding(16).backgroundColor('#FFFFFF').borderRadius(12)

        // 四、操作方法
        Text('四、操作方法').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#172B4D').margin({ top: 8 })

        Column({ space: 10 }) {
          StepRow({ step: '1', text: '在首页点击"转换执行器"进入转换页面。' })
          StepRow({ step: '2', text: '选择源格式（如 PDF）和目标格式（如 Word）。' })
          StepRow({ step: '3', text: '输入文件名（须包含扩展名，如 report.pdf）。' })
          StepRow({ step: '4', text: '确认转换路线，点击"开始演示"执行转换。' })
          StepRow({ step: '5', text: '转换完成后可在"任务记录"页面查看历史。' })
          StepRow({ step: '6', text: '也可先在"格式浏览器"中浏览格式详情。' })
        }
        .width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(12)

        // 底部
        Divider().height(1).color('#E5ECF5').margin({ top: 8 })
        Text('文档转换工具箱 v1.0.0-design  ·  数据来源: FormatRegistry')
          .fontSize(12).fontColor('#A0AEC0').textAlign(TextAlign.Center).width('100%').padding({ bottom: 24 })
      }
      .width('100%').padding(24).constraintSize({ maxWidth: 720 })
    }
    .backgroundColor('#F2F5FA')
  }
}
