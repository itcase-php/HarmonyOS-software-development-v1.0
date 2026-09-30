import { ErrorHandler } from '../common/ErrorHandler';
import { RegistryFormat } from '../models/RegistryTypes';
import { CategoryChoice } from '../models/InteractionModels';
import { FormatRegistry } from '../services/FormatRegistry';
import { RegistryUi } from '../common/RegistryUi';
import { UiFeedback } from '../common/UiFeedback';
import { PageHeader } from '../components/PageHeader';
import { FormatTag } from '../components/FormatTag';
import { StatusBadge } from '../components/StatusBadge';
import { FidelityText } from '../common/FidelityText';

@Entry
@Preview
@Component
struct FormatBrowser {
  @State query: string = '';
  @State category: string = 'all';
  @State expandedId: string = '';
  @State formats: RegistryFormat[] = FormatRegistry.listFormats();
  @State loading: boolean = false;
  @State loadFailed: boolean = false;
  private categories: CategoryChoice[] = [
    { id: 'all', label: $r('app.string.category_all') }, { id: 'pdf', label: $r('app.string.category_pdf') },
    { id: 'image', label: $r('app.string.category_image') }, { id: 'office', label: $r('app.string.category_office') },
    { id: 'text', label: $r('app.string.category_text') }, { id: 'audio', label: $r('app.string.category_audio') }
  ];

  aboutToAppear(): void { this.loadFormats(); }

  private async loadFormats(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    try {
      await RegistryUi.ensure(this.getUIContext());
      this.formats = FormatRegistry.listFormats(); this.loadFailed = false;
    } catch (error) { ErrorHandler.swallow('FormatBrowser.fallback', error); this.formats = []; this.loadFailed = true; }
    finally { this.loading = false; }
  }

  private categoryLabel(id: string): string {
    const choice = this.categories.find((item: CategoryChoice) => item.id === id);
    return choice ? FidelityText.read(this.getUIContext(), choice.label) : id;
  }

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
        PageHeader({ title: $r('app.string.browser_title'), subtitle: $r('app.string.browser_subtitle') })
        Search({ value: this.query, placeholder: FidelityText.read(this.getUIContext(), $r('app.string.browser_search')) })
          .accessibilityText($r('app.string.browser_search')).onChange((value: string) => { this.query = value; })
          .backgroundColor($r('app.color.palette_ffffff'))
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.categories, (choice: CategoryChoice) => {
              Button(choice.label).fontSize(13).accessibilityText(choice.label)
                .backgroundColor(this.category === choice.id ? $r('app.color.palette_007aff') : $r('app.color.palette_ffffff'))
                .fontColor(this.category === choice.id ? $r('app.color.palette_ffffff') : $r('app.color.palette_172b4d'))
                .onClick(() => { this.category = choice.id; })
            }, (choice: CategoryChoice) => choice.id)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        if (this.loading) { Text($r('app.string.registry_loading')) }
        if (this.loadFailed) {
          Text($r('app.string.registry_error')).fontColor($r('app.color.palette_c53030'))
          Button($r('app.string.registry_retry')).onClick(() => { this.loadFormats(); })
        }
        Text($r('app.string.browser_count', this.filtered().length, this.formats.length)).fontSize(14).fontColor($r('app.color.palette_526077'))
        ForEach(this.filtered(), (format: RegistryFormat) => {
          Column({ space: 10 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 10 }) {
                FormatTag({ formatId: format.id })
                Column({ space: 5 }) {
                  Text(format.displayName).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
                  Text($r('app.string.browser_operations_summary', this.categoryLabel(format.category),
                    format.operations.includes('import') ? FidelityText.read(this.getUIContext(), $r('app.string.browser_import')) : '',
                    format.operations.includes('export') ? FidelityText.read(this.getUIContext(), $r('app.string.browser_export')) : ''))
                    .fontSize(13).fontColor($r('app.color.palette_526077'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(this.expandedId === format.id ? $r('app.string.browser_collapse') : $r('app.string.browser_details'))
                  .fontSize(13).fontColor($r('app.color.palette_007aff'))
              }.width('100%')
            }.backgroundColor($r('app.color.palette_ffffff')).width('100%').padding(0)
              .accessibilityText($r('app.string.browser_format_details', format.displayName))
              .onClick(() => { this.expandedId = this.expandedId === format.id ? '' : format.id; })
            if (this.expandedId === format.id) {
              StatusBadge({ text: FidelityText.read(this.getUIContext(), $r('app.string.browser_planned')) })
              Text($r('app.string.browser_id', format.id)).fontSize(14).fontColor($r('app.color.palette_172b4d'))
              Text($r('app.string.browser_extensions', format.extensions.map((extension: string) => '.' + extension).join(', ')))
                .fontSize(14).fontColor($r('app.color.palette_172b4d'))
              Text($r('app.string.browser_mime', format.mimeTypes.join(', '))).fontSize(13).fontColor($r('app.color.palette_526077'))
              Text($r('app.string.browser_operations', format.operations.join(' / '))).fontSize(14).fontColor($r('app.color.palette_526077'))
              Button($r('app.string.browser_use')).fontSize(14).backgroundColor($r('app.color.palette_007aff'))
                .onClick(() => { UiFeedback.open(this.getUIContext(), 'pages/ConverterPage', { sourceFormatId: format.id }); })
            }
          }.alignItems(HorizontalAlign.Start).width('100%').padding(16).backgroundColor($r('app.color.palette_ffffff')).borderRadius(16)
        }, (format: RegistryFormat) => format.id)
        if (!this.loading && !this.loadFailed && this.filtered().length === 0) {
          Column({ space: 10 }) {
            Text('⌕').fontSize(40).fontColor($r('app.color.palette_526077'))
            Text($r('app.string.browser_empty')).fontSize(18).fontColor($r('app.color.palette_172b4d'))
            Button($r('app.string.browser_reset')).onClick(() => { this.query = ''; this.category = 'all'; })
          }.padding(32).width('100%').backgroundColor($r('app.color.palette_ffffff')).borderRadius(16)
        }
      }.padding(24).width('100%').constraintSize({ maxWidth: 720 }).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.palette_f2f5fa'))
  }
}
