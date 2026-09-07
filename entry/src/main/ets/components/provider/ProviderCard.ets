/**
 * ProviderCard —— 单个供应商卡片（精致化）
 *
 * 展示名称、端点、分类；点击切换为当前供应商；提供编辑 / 删除操作。
 */
import { Provider, ProviderCategory, inferBaseUrl } from '../../types/Provider';
import { categoryLabel } from '../../types/Preset';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../../types/Skin';

function categoryColor(c?: ProviderCategory): string {
  switch (c) {
    case 'official':
      return '#D97757';
    case 'cn_official':
      return '#3370FF';
    case 'cloud_provider':
      return '#FF9900';
    case 'aggregator':
      return '#6E29F6';
    case 'third_party':
      return '#0FBA6E';
    case 'custom':
      return '#8A9099';
    default:
      return '#0A59F7';
  }
}

/** 分类底色的暗色变体（M5）：调亮一档，避免固定亮色在暗色卡片上刺眼 */
function categoryColorDark(c?: ProviderCategory): string {
  switch (c) {
    case 'official':
      return '#E8906F';
    case 'cn_official':
      return '#5B8CFF';
    case 'cloud_provider':
      return '#FFAD33';
    case 'aggregator':
      return '#8B5CF6';
    case 'third_party':
      return '#2FD08A';
    case 'custom':
      return '#9AA0A6';
    default:
      return '#3B82F6';
  }
}

function initials(name: string): string {
  if (!name) {
    return '?';
  }
  return name.trim().charAt(0).toUpperCase();
}

@Component
export struct ProviderCard {
  @Prop provider: Provider;
  @Prop isCurrent: boolean;
  onSwitch: (p: Provider) => void = (p: Provider) => {};
  onEdit: (p: Provider) => void = (p: Provider) => {};
  onDelete: (p: Provider) => void = (p: Provider) => {};
  onDuplicate: (p: Provider) => void = (p: Provider) => {};
  // M5：themeIsDark 由 ThemeController/EntryAbility 经 AppStorage 维护（暗色变体选择）；
  // skinAccent/skinAccentTint 为换肤强调色，默认值走 types/Skin 常量兜底
  @StorageLink('themeIsDark') themeIsDark: boolean = false;
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;
  // PC 鼠标 hover 态：边框高亮 + 阴影加深（.animation 平滑过渡）
  @State isHover: boolean = false;

  @Builder
  Avatar() {
    Column() {
      Text(initials(this.provider.name))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    // 品牌 iconColor 原样保留；分类底色在暗色下换用调亮变体
    .backgroundColor(this.provider.iconColor
      ? this.provider.iconColor
      : (this.themeIsDark ? categoryColorDark(this.provider.category) : categoryColor(this.provider.category)))
    .borderRadius(14)
    .shadow({ radius: 8, color: '#22000000', offsetX: 0, offsetY: 2 })
  }

  @Builder
  CurrentBadge() {
    Row({ space: 5 }) {
      Image($r('app.media.shield_check'))
        .width(14)
        .height(14)
        .fillColor('#FFFFFF')
        .objectFit(ImageFit.Contain)
      Text('使用中')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .height(28)
    .borderRadius(14)
    .backgroundColor($r('app.color.status_running'))
    .padding({ left: 10, right: 12 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  SwitchButton() {
    Text('切换')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.skinAccent)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.skinAccentTint)
      .padding({ left: 16, right: 16 })
      .textAlign(TextAlign.Center)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
  }

  @Builder
  EditButton() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.icon_edit'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.text_secondary'))
        .objectFit(ImageFit.Contain)
    }
    .width(36)
    .height(36)
    .backgroundColor($r('app.color.button_secondary'))
    .borderRadius(12)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onEdit(this.provider))
  }

  @Builder
  DeleteButton() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.icon_trash'))
        .width(18)
        .height(18)
        .fillColor($r('app.color.danger'))
        .objectFit(ImageFit.Contain)
    }
    .width(36)
    .height(36)
    .backgroundColor($r('app.color.button_secondary'))
    .borderRadius(12)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onDelete(this.provider))
  }

  build() {
    Row({ space: 14 }) {
      this.Avatar()

      // 名称 + 端点
      Column({ space: 5 }) {
        Row() {
          Text(this.provider.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.provider.category === 'official') {
            Text('官方')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.skinAccent)
              .backgroundColor(this.skinAccentTint)
              .borderRadius(5)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
        }
        .width('100%')

        Text(inferBaseUrl(this.provider.settingsConfigJson) || categoryLabel(this.provider.category) || '—')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 当前标识 / 切换按钮
      if (this.isCurrent) {
        this.CurrentBadge()
      } else {
        this.SwitchButton()
      }

      // 操作按钮
      Row({ space: 6 }) {
        this.EditButton()
        this.DeleteButton()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .border({
      width: this.isCurrent || this.isHover ? 1 : 0.5,
      color: this.isCurrent
        ? $r('app.color.status_running_border')
        : (this.isHover ? this.skinAccent : $r('app.color.border'))
    })
    .shadow(this.isCurrent
      ? { radius: 16, color: '#1410B981', offsetX: 0, offsetY: 4 }
      : (this.isHover
        ? { radius: 14, color: '#14000000', offsetX: 0, offsetY: 4 }
        : { radius: 10, color: '#0A000000', offsetX: 0, offsetY: 2 }))
    .animation({ duration: 150, curve: Curve.EaseOut })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .onHover((hovering: boolean) => {
      this.isHover = hovering;
    })
    .onClick(() => {
      if (!this.isCurrent) {
        this.onSwitch(this.provider);
      }
    })
  }
}
