/**
 * ConfigPanel —— 网关设置面板壳（R3 拆分后）
 *
 * 只保留标题栏 + 滚动容器 + 分组挂载 + 底部按钮行；各分组（代理/外观/安全/
 * 智能路由/插件/Claude 集成/关于）已拆到 components/settings/ 下，自带 @State
 * 与 handler。壳与分组的协作走 SectionPersistHandle（保存/重置/刷新）与事件回调
 * （打开对话框）：对话框需覆盖整个面板，故由壳统一挂载（RuleDialog/CustomRuleDialog）。
 * 数据流通道不变：持久化仍走 SettingsRepository，NAPI 仍走各 Service/GatewayController。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Provider } from '../types/Provider';
import { SecurityRule } from '../types/SecurityTypes';
import { RouteRule } from '../types/RouteRule';
import { DEFAULT_ACCENT } from '../types/Skin';
import { GatewayController } from '../app/GatewayController';
import { SectionPersistHandle } from './common/SectionWidgets';
import { ProxySection } from './settings/ProxySection';
import { AppearanceSection } from './settings/AppearanceSection';
import { SecuritySection, CustomRuleDialog } from './settings/SecuritySection';
import { PasswordLeakAuditSection } from './settings/PasswordLeakAuditSection';
import { RouteSection, RouteRuleDialog } from './settings/RouteSection';
import { PluginSection } from './settings/PluginSection';
import { AgentConfigSection } from './settings/AgentConfigSection';
import { CloudConfigSection } from './settings/CloudConfigSection';
import { AboutSection } from './settings/AboutSection';

const DOMAIN = 0x0000;
const TAG = 'ConfigPanel';

@Component
export struct ConfigPanel {
  // M5 换肤：强调色经 AppStorage 换肤（见 types/Skin.ets）
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  // 分组动作句柄（分组 aboutToAppear 装配 save/reset/refresh）
  private proxyHandle: SectionPersistHandle = new SectionPersistHandle();
  private securityHandle: SectionPersistHandle = new SectionPersistHandle();
  private routeHandle: SectionPersistHandle = new SectionPersistHandle();
  // 对话框挂载态（对话框覆盖整个面板，故由壳持有）
  @State showRuleDialog: boolean = false;
  @State showCustomDialog: boolean = false;
  private ruleDialogTarget: RouteRule | null = null;
  private ruleDialogProviders: Provider[] = [];
  private customRuleId: string = '';
  private customRuleName: string = '';

  onDismiss?: () => void;

  /** 打开添加（rule 为 null）/ 编辑路由规则对话框，快照当前供应商列表传入 */
  private openRuleDialog(rule: RouteRule | null): void {
    this.ruleDialogTarget = rule;
    this.ruleDialogProviders = GatewayController.getProviders();
    this.showRuleDialog = true;
  }

  /** 打开规则自定义对话框 */
  private openCustomDialog(rule: SecurityRule): void {
    this.customRuleId = rule.id;
    this.customRuleName = rule.name;
    this.showCustomDialog = true;
  }

  /** 保存：代理分组（地址/端口/自动启动）+ 安全分组（检测开关）分别持久化 */
  private async handleSave(): Promise<void> {
    await this.proxyHandle.save();
    await this.securityHandle.save();
    hilog.info(DOMAIN, TAG, 'Configuration saved');
    if (this.onDismiss) {
      this.onDismiss();
    }
  }

  private handleReset(): void {
    this.proxyHandle.reset();
    this.securityHandle.reset();
    hilog.info(DOMAIN, TAG, 'Configuration reset (local)');
  }

  @Builder
  CloseButton() {
    Stack({ alignContent: Alignment.Center }) {
      Image($r('app.media.icon_close'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_secondary'))
        .objectFit(ImageFit.Contain)
    }
    .width(44)
    .height(44)
    .backgroundColor($r('app.color.button_secondary'))
    .borderRadius(14)
    .align(Alignment.Center)
    .hoverEffect(HoverEffect.Highlight)
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .onClick(() => {
      if (this.onDismiss) {
        this.onDismiss();
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        // 标题栏
        Row() {
          Text('网关设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          this.CloseButton()
        }
        .width('100%')
        .padding({ left: 24, right: 16, top: 18, bottom: 14 })

        // 配置内容
        Scroll() {
          Column({ space: 28 }) {
            ProxySection({ handle: this.proxyHandle })
            AppearanceSection()
            CloudConfigSection()
            SecuritySection({
              handle: this.securityHandle,
              onOpenCustom: (rule: SecurityRule) => this.openCustomDialog(rule)
            })
            PasswordLeakAuditSection()
            RouteSection({
              handle: this.routeHandle,
              onEditRule: (rule: RouteRule | null) => this.openRuleDialog(rule)
            })
            PluginSection()
            AgentConfigSection()
            AboutSection()
          }
          .padding(24)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 底部按钮
        Row({ space: 12 }) {
          Button('重置')
            .width(100)
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.handleReset())

          Blank()

          Button('取消')
            .width(100)
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              if (this.onDismiss) {
                this.onDismiss();
              }
            })

          Button('保存')
            .width(100)
            .height(40)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.skinAccent)
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.handleSave().then(() => {
              }, () => {
              });
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 24, top: 12 })
      }
      .width(600)
      .height(520)
      .backgroundColor($r('app.color.panel_bg'))
      .borderRadius(20)
      .shadow({
        radius: 32,
        color: '#33000000',
        offsetX: 0,
        offsetY: 10
      })
      // 与 DialogShell 一致的入场/退场转场（淡入 + 轻微缩放）
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
        .animation({ duration: 200, curve: Curve.EaseOut }))

      // 路由规则 添加/编辑 对话框（覆盖在面板之上）
      if (this.showRuleDialog) {
        RouteRuleDialog({
          target: this.ruleDialogTarget,
          providers: this.ruleDialogProviders,
          onDismiss: () => {
            this.showRuleDialog = false;
            this.routeHandle.refresh();
          }
        })
      }

      // 安全规则 自定义词条 对话框（M4，覆盖在面板之上）
      if (this.showCustomDialog) {
        CustomRuleDialog({
          ruleId: this.customRuleId,
          ruleName: this.customRuleName,
          onDismiss: () => {
            this.showCustomDialog = false;
            this.securityHandle.refresh();
          }
        })
      }
    }
  }
}
