/**
 * PluginSection —— 设置面板「插件」分组（R3 从 ConfigPanel 拆出）
 *
 * M2 动态库插件：内置适配器 + filesDir/plugins 下加载的 .so；开关走
 * PluginService（NAPI）即时生效。加载失败的插件没有可调用的函数表，不渲染开关。
 */
import { PluginItem } from '../../types/PluginTypes';
import { DEFAULT_ACCENT } from '../../types/Skin';
import { PluginService } from '../../services/PluginService';
import { SectionTitle } from '../common/SectionWidgets';

@Component
export struct PluginSection {
  @State plugins: PluginItem[] = [];
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  aboutToAppear(): void {
    this.plugins = PluginService.listPlugins();
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '插件' })

      Column({ space: 4 }) {
        if (this.plugins.length === 0) {
          Text('未发现插件。可将插件 .so 放入应用插件目录（filesDir/plugins），重启应用后即可加载')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 6, bottom: 6 })
        }

        ForEach(this.plugins, (plugin: PluginItem) => {
          Column({ space: 4 }) {
            Row() {
              Column({ space: 2 }) {
                Text(`${plugin.name}  v${plugin.version}`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Text(plugin.source === 'builtin' ? `内置 · ${plugin.type}` : `文件 · ${plugin.type}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (plugin.error.length === 0) {
                Toggle({ type: ToggleType.Switch, isOn: plugin.enabled })
                  .selectedColor(this.skinAccent)
                  .switchPointColor(Color.White)
                  .size({ width: 48, height: 26 })
                  .onChange((isOn: boolean) => {
                    if (PluginService.setPluginEnabled(plugin.id, isOn)) {
                      plugin.enabled = isOn;
                    }
                  })
              }
            }
            .width('100%')

            if (plugin.error.length > 0) {
              Text(`加载失败：${plugin.error}`)
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (plugin: PluginItem) => plugin.id)
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
