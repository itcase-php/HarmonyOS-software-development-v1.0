import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { ErrorHandler } from '../common/ErrorHandler';
import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { FormatRegistry } from '../services/FormatRegistry';
import { RegistryUi } from '../common/RegistryUi';
import { registryMetadata } from '../generated/RegistryData';
import { UiFeedback } from '../common/UiFeedback';
import { StatusBadge } from '../components/StatusBadge';

interface CategoryInfo {
  id: string;
  color: ResourceColor;
}

const CATEGORY_INFOS: CategoryInfo[] = [
  { id: 'pdf', color: $r('app.color.palette_c53030') },
  { id: 'office', color: $r('app.color.palette_2563eb') },
  { id: 'image', color: $r('app.color.palette_7c3aed') },
  { id: 'text', color: $r('app.color.palette_0d9488') },
  { id: 'audio', color: $r('app.color.palette_d97706') },
];

function catLabel(catId: string): string {
  for (let i = 0; i < CATEGORY_INFOS.length; i++) {
    if (CATEGORY_INFOS[i].id === catId) {
      return LanguageManager.getString('category_' + catId);
    }
  }
  return catId;
}

function catColor(catId: string): ResourceColor {
  for (let i = 0; i < CATEGORY_INFOS.length; i++) {
    if (CATEGORY_INFOS[i].id === catId) {
      return CATEGORY_INFOS[i].color;
    }
  }
  return $r('app.color.palette_526077');
}

function intentLabel(value: string): string {
  if (value === 'layout_preserved') { return LanguageManager.getString('guide_layout'); }
  if (value === 'structured_rebuild') { return LanguageManager.getString('guide_structure'); }
  if (value === 'content_only') { return LanguageManager.getString('guide_content'); }
  return value;
}

function modeLabel(value: string): string {
  if (value === 'direct') { return LanguageManager.getString('guide_direct'); }
  if (value === 'relay') { return LanguageManager.getString('guide_relay'); }
  return value;
}

function statusColor(value: string): ResourceColor {
  if (value === 'available') { return $r('app.color.palette_167644'); }
  if (value === 'experimental') { return $r('app.color.palette_d97706'); }
  if (value === 'planned') { return $r('app.color.palette_526077'); }
  if (value === 'unavailable') { return $r('app.color.palette_c53030'); }
  return $r('app.color.palette_526077');
}

function statusText(value: string): string {
  if (value === 'available') { return LanguageManager.getString('status_available'); }
  if (value === 'experimental') { return LanguageManager.getString('status_experimental'); }
  if (value === 'planned') { return LanguageManager.getString('status_planned'); }
  if (value === 'unavailable') { return LanguageManager.getString('status_unavailable'); }
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
  statusC: ResourceColor;
}

interface RouteGroupData {
  sourceName: string;
  sourceCatLbl: string;
  sourceCatClr: ResourceColor;
  routeItems: RouteItemData[];
}

interface UnavailData {
  description: string;
  statusText: string;
  statusColor: ResourceColor;
}

// ── 子组件 ──

@Component
export struct FormatSummaryCard {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop displayName: string = '';
  @Prop formatId: string = '';
  @Prop catLbl: string = '';
  @Prop catClr: ResourceColor = '';
  @Prop extensions: string = '';
  @Prop operations: string = '';

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        StatusBadge({ text: this.catLbl, color: this.catClr })
        Text(this.displayName).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d'))
      }
      Text(this.tr('guide_format_meta', [this.formatId, this.extensions]))
        .fontSize(13).fontColor($r('app.color.palette_526077'))
      Text(this.tr('guide_operations', [this.operations]))
        .fontSize(13).fontColor($r('app.color.palette_526077'))
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)
  }
}

@Component
struct HelpRouteRow {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop targetName: string = '';
  @Prop modeLabel: string = '';
  @Prop intentLabel: string = '';
  @Prop statusText: string = '';
  @Prop statusColor: ResourceColor = '';

  build() {
    Row({ space: 10 }) {
      Text(this.targetName).fontSize(14).fontColor($r('app.color.palette_007aff'))
      StatusBadge({ text: this.modeLabel, color: $r('app.color.palette_526077') })
      StatusBadge({ text: this.intentLabel, color: $r('app.color.palette_526077') })
      StatusBadge({ text: this.statusText, color: this.statusColor })
    }
  }
}

@Component
struct UnavailRow {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop description: string = '';
  @Prop statusText: string = '';
  @Prop statusColor: ResourceColor = '';

  build() {
    Row({ space: 8 }) {
      Text(this.description).fontSize(14).fontColor($r('app.color.palette_c53030'))
      StatusBadge({ text: this.statusText, color: this.statusColor })
    }
  }
}

@Component
struct StepRow {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop step: string = '';
  @Prop text: string = '';

  build() {
    Row({ space: 12 }) {
      Text(this.step).fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_ffffff'))
        .width(24).height(24).textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.palette_007aff')).borderRadius(12)
      Text(this.text).fontSize(14).fontColor($r('app.color.palette_172b4d')).lineHeight(22)
    }.alignItems(VerticalAlign.Center).width('100%')
  }
}

@Component
struct RouteGroupCard {
  @StorageLink('appLanguage') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @Prop sourceName: string = '';
  @Prop sourceCatLbl: string = '';
  @Prop sourceCatClr: ResourceColor = '';
  @Prop routeItems: RouteItemData[] = [];

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        StatusBadge({ text: this.sourceCatLbl, color: this.sourceCatClr })
        Text(`${this.sourceName} →`).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
      }
      ForEach(this.routeItems, (item: RouteItemData) => {
        HelpRouteRow({
          targetName: item.targetName,
          modeLabel: item.mode,
          intentLabel: item.intent,
          statusText: item.statusT,
          statusColor: item.statusC
        })
      }, (item: RouteItemData) => `${item.id}-${this.language}`)
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)
  }
}

// ── 主页面 ──

@Entry
@Preview
@Component
struct FeatureGuide {
  @StorageLink('appLanguage') @Watch('populateGuide') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

  @State private formatCards: FormatCardData[] = [];
  @State private routeGroups: RouteGroupData[] = [];
  @State private unavailItems: UnavailData[] = [];
  @State private blockedList: string[] = [];
  @State private registryError: boolean = false;
  @State private registryLoading: boolean = false;

  aboutToAppear(): void {
    LanguageManager.bind(this.getUIContext().getHostContext());
    this.populateGuide();
    this.loadRegistry();
  }

  private async loadRegistry(): Promise<void> {
    if (this.registryLoading) { return; }
    this.registryLoading = true;
    try {
      await RegistryUi.ensure(this.getUIContext());
      this.populateGuide(); this.registryError = false;
    } catch (error) { ErrorHandler.swallow('FeatureGuide.fallback', error); this.registryError = true; }
    finally { this.registryLoading = false; }
  }

  private populateGuide(): void {
    const all: RegistryFormat[] = FormatRegistry.listFormats();
    all.sort((a: RegistryFormat, b: RegistryFormat) => catOrder(a.category) - catOrder(b.category));

    const cards: FormatCardData[] = [];
    for (let i = 0; i < all.length; i++) {
      const f: RegistryFormat = all[i];
      cards.push({
        id: f.id,
        displayName: LanguageManager.formatName(f.id, f.displayName),
        category: f.category,
        extensions: f.extensions.join(' .'),
        operations: f.operations.map((value: string) => LanguageManager.operation(value)).join(' / ')
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
              targetName = LanguageManager.formatName(all[k].id, all[k].displayName);
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
          sourceName: LanguageManager.formatName(fmt.id, fmt.displayName),
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
              fromNames.push(LanguageManager.formatName(all[k].id, all[k].displayName));
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
            toName = LanguageManager.formatName(all[k].id, all[k].displayName);
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
          Button(this.tr('back')).fontSize(14).type(ButtonType.Normal).backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
            .onClick(() => { UiFeedback.back(this.getUIContext()); })
          Text(this.tr('guide_title')).fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).layoutWeight(1)
        }.width('100%')

        // 概述
        if (this.registryLoading) { Text(this.tr($r('app.string.registry_loading'))) }
        if (this.registryError) {
          Text(this.tr($r('app.string.registry_error')))
          Button(this.tr($r('app.string.registry_retry'))).onClick(() => { this.loadRegistry(); })
        }
        Column({ space: 8 }) {
          Text(this.tr('guide_overview'))
            .fontSize(14).fontColor($r('app.color.palette_526077')).lineHeight(22)
        }
        .width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)

        // 一、支持的格式一览
        Text(this.tr('guide_formats')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).margin({ top: 8 })

        ForEach(this.formatCards, (card: FormatCardData) => {
          FormatSummaryCard({
            displayName: card.displayName,
            formatId: card.id,
            catLbl: catLabel(card.category),
            catClr: catColor(card.category),
            extensions: card.extensions,
            operations: card.operations
          })
        }, (card: FormatCardData) => `${card.id}-${this.language}`)

        // 二、可执行的转换路线
        Text(this.tr('guide_routes')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).margin({ top: 8 })

        Text(this.tr('guide_routes_notice'))
          .fontSize(14).fontColor($r('app.color.palette_526077')).lineHeight(22)

        ForEach(this.routeGroups, (group: RouteGroupData) => {
          RouteGroupCard({
            sourceName: group.sourceName,
            sourceCatLbl: group.sourceCatLbl,
            sourceCatClr: group.sourceCatClr,
            routeItems: group.routeItems
          })
        }, (group: RouteGroupData) => `rg-${group.sourceName}-${this.language}`)

        // 三、不兼容与不适合转换的格式
        Text(this.tr('guide_limits')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).margin({ top: 8 })

        // 3a. 封锁格式
        Column({ space: 10 }) {
          Text(this.tr('guide_blocked'))
            .fontSize(14).fontColor($r('app.color.palette_526077')).lineHeight(22)
          Column() {
            ForEach(this.blockedList, (blocked: string) => {
              StatusBadge({ text: `.${blocked}`, color: $r('app.color.palette_c53030') })
            }, (blocked: string) => blocked)
          }
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)

        // 3b. 不可用路线
        Column({ space: 10 }) {
          Text(this.tr('guide_unavailable'))
            .fontSize(14).fontColor($r('app.color.palette_526077')).lineHeight(22)
          Column() {
            ForEach(this.unavailItems, (item: UnavailData) => {
              UnavailRow({
                description: item.description,
                statusText: item.statusText,
                statusColor: item.statusColor
              })
            }, (_item: UnavailData, index: number) => `ua-${index}-${this.language}`)
          }
        }
        .alignItems(HorizontalAlign.Start).width('100%')
        .padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)

        // 四、操作方法
        Text(this.tr('guide_steps')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.palette_172b4d')).margin({ top: 8 })

        Column({ space: 10 }) {
          StepRow({ step: '1', text: this.tr('guide_step1') })
          StepRow({ step: '2', text: this.tr('guide_step2') })
          StepRow({ step: '3', text: this.tr('guide_step3') })
          StepRow({ step: '4', text: this.tr('guide_step4') })
          StepRow({ step: '5', text: this.tr('guide_step5') })
          StepRow({ step: '6', text: this.tr('guide_step6') })
        }
        .width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(12)

        // 底部
        Divider().height(1).color($r('app.color.palette_e5ecf5')).margin({ top: 8 })
        Text(this.tr('guide_footer'))
          .fontSize(12).fontColor($r('app.color.palette_a0aec0')).textAlign(TextAlign.Center).width('100%').padding({ bottom: 24 })
      }
      .width('100%').padding(24).constraintSize({ maxWidth: 720 })
    }
    .backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
