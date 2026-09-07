/**
 * AppearanceSection —— 设置面板「外观」分组（R3 从 ConfigPanel 拆出）
 *
 * 主题模式 + 皮肤，切换即时生效（ThemeController 持久化 + 系统 setColorMode /
 * AppStorage 换肤），不经壳的「保存」按钮。设计说明见 types/Skin.ets。
 */
import { SkinPack, DEFAULT_ACCENT } from '../../types/Skin';
import { ThemeController, THEME_MODES, ThemeModeItem } from '../../app/ThemeController';
import { FieldLabel, SectionTitle } from '../common/SectionWidgets';

@Component
export struct AppearanceSection {
  @State themeMode: string = 'system';
  @State skinId: string = 'default';
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  private skins: SkinPack[] = ThemeController.getSkins();

  aboutToAppear(): void {
    this.themeMode = ThemeController.getThemeMode();
    this.skinId = ThemeController.getSkinId();
  }

  /** 主题模式药丸分段控件（风格对齐智能路由的协议选择器），切换即时生效 */
  @Builder
  ThemeModePicker() {
    Row({ space: 8 }) {
      ForEach(THEME_MODES, (m: ThemeModeItem) => {
        Text(m.label)
          .fontSize(13)
          .fontColor(this.themeMode === m.value ? '#FFFFFF' : $r('app.color.text_secondary'))
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.themeMode === m.value ? this.skinAccent : $r('app.color.button_secondary'))
          .borderRadius(9)
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.themeMode = m.value;
            ThemeController.setThemeMode(m.value).then(() => {
            }, () => {
            });
          })
      }, (m: ThemeModeItem) => m.value)
    }
    .width('100%')
  }

  /** 皮肤色板选择（圆点预览 + 名称，选中态描边），切换即时生效 */
  @Builder
  SkinPicker() {
    Row({ space: 18 }) {
      ForEach(this.skins, (s: SkinPack) => {
        Column({ space: 6 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 26, height: 26 })
              .fill(s.accent)
            if (this.skinId === s.id) {
              Circle({ width: 34, height: 34 })
                .fill(Color.Transparent)
                .stroke(s.accent)
                .strokeWidth(2)
            }
          }
          .width(34)
          .height(34)
          Text(s.name)
            .fontSize(11)
            .fontColor(this.skinId === s.id ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        }
        .onClick(() => {
          this.skinId = s.id;
          ThemeController.setSkinId(s.id).then(() => {
          }, () => {
          });
        })
      }, (s: SkinPack) => s.id)
    }
    .width('100%')
    .padding({ top: 2, bottom: 4 })
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '外观' })

      Column({ space: 4 }) {
        Column() {
          FieldLabel({ text: '主题模式' })
          this.ThemeModePicker()
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 4, bottom: 10 })

        Divider().color($r('app.color.divider')).strokeWidth(0.5)

        Column() {
          FieldLabel({ text: '皮肤' })
          this.SkinPicker()
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 10, bottom: 4 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .border({ width: 0.5, color: $r('app.color.border') })
    }
    .width('100%')
  }
}
