import { RegistryFormat } from '../models/RegistryTypes';
import { CategoryChoice } from '../models/InteractionModels';
import { FormatRegistry } from '../services/FormatRegistry';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { FormatTag } from '../components/FormatTag';
import { StatusBadge } from '../components/StatusBadge';

@Entry
@Preview
@Component
struct FormatBrowser {
  @State query: string = '';
  @State category: string = 'all';
  @State expandedId: string = '';
  private formats: RegistryFormat[] = FormatRegistry.listFormats();
  private categories: CategoryChoice[] = [
    { id: 'all', label: '全部' }, { id: 'pdf', label: 'PDF' }, { id: 'image', label: '图片' },
    { id: 'office', label: 'Office' }, { id: 'text', label: '文本' }, { id: 'audio', label: '音频' }
  ];

  private filtered(): RegistryFormat[] {
    const keyword = this.query.trim().toLowerCase();
    return this.formats.filter((format: RegistryFormat) =>
      (this.category === 'all' || format.category === this.category) &&
      (keyword.length === 0 || format.displayName.toLowerCase().includes(keyword) ||
        format.id.includes(keyword) || format.extensions.some((extension: string) => extension.includes(keyword))));
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PageHeader({ title: '格式浏览器', subtitle: '查看全部格式定义与规划能力，点击卡片展开详情' })
        Search({ value: this.query, placeholder: '搜索名称、ID 或扩展名' })
          .onChange((value: string) => { this.query = value; })
          .backgroundColor('#FFFFFF')
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.categories, (choice: CategoryChoice) => {
              Button(choice.label).fontSize(13)
                .backgroundColor(this.category === choice.id ? '#007AFF' : '#FFFFFF')
                .fontColor(this.category === choice.id ? '#FFFFFF' : '#172B4D')
                .onClick(() => { this.category = choice.id; })
            }, (choice: CategoryChoice) => choice.id)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        Text(`找到 ${this.filtered().length} / ${this.formats.length} 个格式`).fontSize(14).fontColor('#526077')
        ForEach(this.filtered(), (format: RegistryFormat) => {
          Column({ space: 10 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                FormatTag({ formatId: format.id })
                Column({ space: 5 }) {
                  Text(format.displayName).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#172B4D')
                  Text(`${format.category} · ${format.operations.includes('import') ? '规划导入' : ''} ${format.operations.includes('export') ? '规划导出' : ''}`)
                    .fontSize(13).fontColor('#526077')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(this.expandedId === format.id ? '收起' : '详情').fontSize(13).fontColor('#007AFF')
              }.width('100%')
            }.backgroundColor('#FFFFFF').width('100%').padding(0)
              .onClick(() => { this.expandedId = this.expandedId === format.id ? '' : format.id; })
            if (this.expandedId === format.id) {
              StatusBadge({ text: '规划定义 · 不代表引擎已可用' })
              Text(`ID：${format.id}`).fontSize(14).fontColor('#172B4D')
              Text(`扩展名：${format.extensions.map((extension: string) => '.' + extension).join('、')}`)
                .fontSize(14).fontColor('#172B4D')
              Text(`MIME：${format.mimeTypes.join('、')}`).fontSize(13).fontColor('#526077')
              Text(`操作：${format.operations.join(' / ')}`).fontSize(14).fontColor('#526077')
              Button('使用此格式演示').fontSize(14).backgroundColor('#007AFF')
                .onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage', { sourceFormatId: format.id }); })
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(16)
        }, (format: RegistryFormat) => format.id)
        if (this.filtered().length === 0) {
          Column({ space: 10 }) {
            Text('⌕').fontSize(40).fontColor('#526077')
            Text('没有匹配的格式').fontSize(18).fontColor('#172B4D')
            Button('重置筛选').onClick(() => { this.query = ''; this.category = 'all'; })
          }.padding(32).width('100%').backgroundColor('#FFFFFF').borderRadius(16)
        }
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor('#F2F5FA')
  }
}
