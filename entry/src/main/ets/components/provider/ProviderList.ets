/**
 * ProviderList —— 供应商列表（精致化）
 *
 * 带搜索框的供应商列表 + 空状态。搜索匹配名称或端点。
 */
import { Provider, inferBaseUrl } from '../../types/Provider';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../../types/Skin';
import { ProviderCard } from './ProviderCard';
import { IconSearch, IconShieldCheck } from '../Icons';

@Component
export struct ProviderList {
  @Prop providers: Provider[];
  @Prop currentId: string;
  /** 当前渠道显示名（多渠道管理）：空态文案随渠道动态化 */
  @Prop appName: string = '';
  @State query: string = '';
  // M5 换肤：空态强调元素（盾牌图标/浅底/主按钮）随皮肤强调色，默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;
  onSwitch: (p: Provider) => void = (p: Provider) => {};
  onEdit: (p: Provider) => void = (p: Provider) => {};
  onDelete: (p: Provider) => void = (p: Provider) => {};
  onDuplicate: (p: Provider) => void = (p: Provider) => {};
  onCreate: () => void = () => {};

  private matches(p: Provider): boolean {
    if (!this.query) {
      return true;
    }
    const q: string = this.query.toLowerCase();
    if (p.name.toLowerCase().indexOf(q) >= 0) {
      return true;
    }
    const url: string = inferBaseUrl(p.settingsConfigJson).toLowerCase();
    return url.indexOf(q) >= 0;
  }

  private filtered(): Provider[] {
    const out: Provider[] = [];
    for (const p of this.providers) {
      if (this.matches(p)) {
        out.push(p);
      }
    }
    return out;
  }

  @Builder
  SearchBar() {
    Row({ space: 10 }) {
      IconSearch({ size: 18, color: $r('app.color.text_tertiary') })
      TextInput({ placeholder: '搜索供应商…', text: this.query })
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .onChange((v: string) => {
          this.query = v;
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14 })
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius(12)
  }

  @Builder
  EmptyState() {
    Column({ space: 16 }) {
      Column() {
        Image($r('app.media.shield_check'))
          .width(56)
          .height(56)
          .fillColor(this.skinAccent)
      }
      .width(120)
      .height(120)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.skinAccentTint)
      .borderRadius(40)
      .shadow({ radius: 20, color: '#1A2563EB', offsetX: 0, offsetY: 4 })

      Text(this.query ? '没有匹配的供应商' : '尚未配置供应商')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
      Text(this.query ? '换个关键词试试' : '为 ' + (this.appName ? this.appName : '当前渠道') + ' 添加一个 API 供应商以开始')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      if (!this.query) {
        Button('添加供应商')
          .fontSize(14)
          .height(40)
          .fontColor('#FFFFFF')
          .backgroundColor(this.skinAccent)
          .borderRadius(20)
          .padding({ left: 24, right: 24 })
          .margin({ top: 8 })
          .id('btnEmptyAdd')
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => this.onCreate())
      }
    }
    .width('100%')
    .padding({ top: 72, bottom: 72 })
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column({ space: 14 }) {
      this.SearchBar()

      if (this.providers.length === 0) {
        this.EmptyState()
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.filtered(), (p: Provider) => {
              ProviderCard({
                provider: p,
                isCurrent: this.currentId === p.id,
                onSwitch: this.onSwitch,
                onEdit: this.onEdit,
                onDelete: this.onDelete,
                onDuplicate: this.onDuplicate,
              })
            }, (p: Provider) => p.id)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}
