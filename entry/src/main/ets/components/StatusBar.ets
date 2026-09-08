/**
 * 系统托盘状态栏组件（精致化）
 * 在右下角常驻显示 AIGate 的运行状态
 */
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEFAULT_ACCENT } from '../types/Skin';
import { IconSettings, IconCheck } from './Icons';

const DOMAIN = 0x0000;
const TAG = 'StatusBar';

/**
 * 状态栏组件
 * isRunning 由宿主页面（Index）单向传入；启停与打开配置经回调交回页面处理
 * （视图不直接触碰 service，数据流见 AGENTS.md）。
 */
@Component
export struct StatusBar {
  @Prop isRunning: boolean = false;
  @State showMenu: boolean = false;
  onToggle: () => void = () => {};
  onOpenSettings: () => void = () => {};
  // M5 换肤：胶囊上的「AI」字样用强调色（状态指示灯保持语义色不变），默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 菜单（展开时显示在托盘上方）
      if (this.showMenu) {
        Column({ space: 4 }) {
          // 启动 / 停止代理
          Row({ space: 10 }) {
            Stack() {
              IconCheck({ size: 18, color: $r('app.color.text_secondary') })
            }
            .width(28)
            .height(28)
            Text(this.isRunning ? '停止代理' : '启动代理')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
          }
          .width('100%')
          .height(42)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.showMenu = false;
            this.onToggle();
          })

          Divider()
            .color($r('app.color.divider'))
            .strokeWidth(0.5)
            .margin({ left: 8, right: 8 })

          // 打开配置
          Row({ space: 10 }) {
            Stack() {
              IconSettings({ size: 72, color: $r('app.color.text_secondary') })
            }
            .width(28)
            .height(28)
            Text('打开配置')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
          }
          .width('100%')
          .height(42)
          .padding({ left: 12, right: 12 })
          .borderRadius(8)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.showMenu = false;
            this.onOpenSettings();
          })
        }
        .width(180)
        .padding(6)
        .backgroundColor($r('app.color.menu_bg'))
        .borderRadius(14)
        .shadow({
          radius: 20,
          color: '#1A000000',
          offsetX: 0,
          offsetY: 6
        })
        .margin({ right: 16, bottom: 78 })
        .alignItems(HorizontalAlign.Start)
      }

      // 托盘胶囊
      Row({ space: 8 }) {
        // 状态指示点
        Stack() {
          Circle({ width: 8, height: 8 })
            .fill(this.isRunning ? $r('app.color.status_running') : $r('app.color.status_stopped'))
          if (this.isRunning) {
            Circle({ width: 14, height: 14 })
              .fill($r('app.color.status_running'))
              .opacity(0.2)
          }
        }
        .width(14)
        .height(14)

        // 图标文字
        Text('AI')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.skinAccent)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.status_bar_bg'))
      .borderRadius(20)
      .border({ width: 0.5, color: $r('app.color.border') })
      .shadow({
        radius: 16,
        color: '#14000000',
        offsetX: 0,
        offsetY: 4
      })
      .margin({ right: 20, bottom: 20 })
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.showMenu = !this.showMenu;
      })
    }
    .width('100%')
    .height('100%')
    // 关键：让空白区域透传点击，只有胶囊本身拦截事件
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
