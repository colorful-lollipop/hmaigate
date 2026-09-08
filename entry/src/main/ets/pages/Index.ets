/**
 * 鸿蒙安全网关 —— 主页面（精致化）
 *
 * 纯展示层：只持有 @State 并把动作委派给 GatewayController。
 * 视觉风格面向鸿蒙 PC 2in1：大圆角、柔和阴影、克制的色彩层级、矢量图标替代 emoji。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalConfigApp, CHANNEL_APPS } from '../types/App';
import { Provider } from '../types/Provider';
import { ProxyStatus } from '../types/ProxyTypes';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../types/Skin';
import { GatewayController } from '../app/GatewayController';
import { ProviderList } from '../components/provider/ProviderList';
import { AddProviderDialog } from '../components/provider/AddProviderDialog';
import { EditProviderDialog } from '../components/provider/EditProviderDialog';
import { StatusBar } from '../components/StatusBar';
import { ConfigPanel } from '../components/ConfigPanel';
import { DialogShell } from '../components/common/DialogShell';
import { IconPlus } from '../components/Icons';

const DOMAIN = 0x0000;
const TAG = 'HmSecGateway';

function emptyProvider(): Provider {
  return { id: '', name: '', settingsConfigJson: '{}' };
}

/** StatCell 的 @Builder 参数：基本类型按值传递不随状态刷新，对象字面量按引用传递才能联动（ArkUI @Builder 参数规则） */
interface StatCellData {
  label: string;
  value: string;
}

@Entry
@Component
struct Index {
  @State providers: Provider[] = [];
  @State currentId: string = '';
  // 多渠道管理：当前活动渠道（渠道切换条选中态，切换走 GatewayController.setActiveApp）
  @State activeApp: LocalConfigApp = 'claude';
  @State showAdd: boolean = false;
  @State isEditing: boolean = false;
  @State editing: Provider = emptyProvider();
  @State hasConfirm: boolean = false;
  @State toDelete: Provider = emptyProvider();
  @State showSettings: boolean = false;
  @State proxyRunning: boolean = false;
  @State proxyHost: string = '127.0.0.1';
  @State proxyPort: number = 8080;
  @State totalRequests: number = 0;
  @State blockedRequests: number = 0;
  // 启停操作进行中标志：onChange 连发/程序化回写去抖（见 toggleProxy）
  private toggleBusy: boolean = false;
  // Hero 卡状态点呼吸动画相位（animateTo 递归驱动，pulseStep 内自停）
  @State pulseOn: boolean = false;
  private pulsing: boolean = false;
  // 自由窗口沉浸式：顶部三键区高度（由 EntryAbility 经 AppStorage 写入），页面顶部据此避让
  @StorageLink('decorTopInset') decorTopInset: number = 0;
  // M5 换肤：强调色经 AppStorage 下发（设计见 types/Skin.ets），默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;
  // 云端快照在后台拉取完成后递增；触发供应商与渠道显示立即重读。
  @StorageLink('cloudConfigEpoch') @Watch('onCloudConfigChanged') cloudConfigEpoch: number = 0;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'HmSecGateway appearing');
    this.init();
  }

  private async init(): Promise<void> {
    await GatewayController.init();
    this.refresh();
  }

  /** 把控制器视图数据拷入 @State（ArkUI 仅观察 @State 自身赋值） */
  private refresh(): void {
    this.providers = GatewayController.getProviders();
    this.currentId = GatewayController.getCurrentId();
    this.activeApp = GatewayController.getActiveApp();
    this.proxyHost = GatewayController.getProxyHost();
    this.proxyPort = GatewayController.getProxyPort();
    // 始终从 C++ 同步真实运行状态
    const st: ProxyStatus = GatewayController.getStatus();
    this.proxyRunning = st.isRunning;
    if (this.proxyRunning) {
      this.totalRequests = st.totalRequests;
      this.blockedRequests = st.blockedRequests;
      this.ensurePulse();
    } else {
      this.pulseOn = false;
    }
  }

  private onCloudConfigChanged(): void {
    this.refresh();
  }

  /** 状态点呼吸动画：递归 animateTo 往返，运行中持续、停止后自停（pulsing 防多重启动） */
  private ensurePulse(): void {
    if (this.pulsing) {
      return;
    }
    this.pulsing = true;
    this.pulseStep();
  }

  private pulseStep(): void {
    this.getUIContext().animateTo({
      duration: 1300,
      curve: Curve.EaseInOut,
      onFinish: () => {
        if (this.proxyRunning) {
          this.pulseStep();
        } else {
          this.pulsing = false;
        }
      }
    }, () => {
      this.pulseOn = !this.pulseOn;
    });
  }

  private async addProvider(p: Provider): Promise<void> {
    await GatewayController.addProvider(p);
    this.showAdd = false;
    this.refresh();
  }

  private async switchProvider(p: Provider): Promise<void> {
    await GatewayController.switchProvider(p);
    this.refresh();
  }

  private startEdit(p: Provider): void {
    this.editing = p;
    this.isEditing = true;
  }

  private async editSubmit(p: Provider, originalId: string): Promise<void> {
    await GatewayController.updateProvider(p, originalId);
    this.isEditing = false;
    this.editing = emptyProvider();
    this.refresh();
  }

  private askDelete(p: Provider): void {
    this.toDelete = p;
    this.hasConfirm = true;
  }

  private async confirmDelete(): Promise<void> {
    if (this.toDelete.id) {
      await GatewayController.removeProvider(this.toDelete.id);
    }
    this.hasConfirm = false;
    this.toDelete = emptyProvider();
    this.refresh();
  }

  private async toggleProxy(target?: boolean): Promise<void> {
    // Toggle 的 isOn 由 proxyRunning 驱动，而程序化回写（启动未完成时 UI 同步回
    // OFF）同样会触发 onChange；不去抖会造成重复启动/误停。忙等中的事件与"值
    // 等于当前端态"的程序化回写一律忽略。
    if (this.toggleBusy) {
      return;
    }
    if (target !== undefined && target === this.proxyRunning) {
      return;
    }
    this.toggleBusy = true;
    try {
      if (this.proxyRunning) {
        GatewayController.stopGateway();
        this.proxyRunning = false;
      } else {
        const ok: boolean = await GatewayController.startGateway(this.proxyHost, this.proxyPort);
        this.proxyRunning = ok;
      }
      this.refresh();
    } finally {
      this.toggleBusy = false;
    }
  }

  @Builder
  AppHeader() {
    Row({ space: 14 }) {
      // 应用图标
      Stack() {
        Image($r('app.media.foreground'))
          .width(28)
          .height(28)
      }
      .width(48)
      .height(48)
      .backgroundColor(this.skinAccentTint)
      .borderRadius(16)
      .border({ width: 1, color: this.skinAccentTint })
      .shadow({ radius: 16, color: '#1A2563EB', offsetX: 0, offsetY: 4 })

      Column({ space: 3 }) {
        Text('鸿蒙安全网关')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('本地 LLM API 安全代理')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))}
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 设置按钮
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.icon_settings'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.text_secondary'))
          .objectFit(ImageFit.Contain)
      }
      .width(44)
      .height(44)
      .backgroundColor($r('app.color.button_secondary'))
      .borderRadius(14)
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .onClick(() => this.showSettings = true)
    }
    .width('100%')
    .height(72)
    .padding({ left: 24, right: 20 })
    .backgroundColor($r('app.color.header_bg'))
  }

  @Builder
  StatusCard() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        // 左侧状态图标块：运行/停止换色圆底 + 右下角呼吸状态点
        Stack({ alignContent: Alignment.BottomEnd }) {
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.shield_check'))
              .width(26)
              .height(26)
              .fillColor(this.proxyRunning ? $r('app.color.status_running') : $r('app.color.status_stopped'))
              .objectFit(ImageFit.Contain)
          }
          .width(48)
          .height(48)
          .backgroundColor(this.proxyRunning
            ? $r('app.color.status_running_tint')
            : $r('app.color.status_stopped_tint'))
          .borderRadius(14)
          .margin({ right: 4, bottom: 4 })

          Stack() {
            if (this.proxyRunning) {
              // 呼吸环：pulseOn 相位由 animateTo 往返驱动
              Circle({ width: 16, height: 16 })
                .fill($r('app.color.status_running'))
                .opacity(this.pulseOn ? 0.0 : 0.32)
                .scale({ x: this.pulseOn ? 1.6 : 1.0, y: this.pulseOn ? 1.6 : 1.0 })
            }
            Circle({ width: 10, height: 10 })
              .fill(this.proxyRunning ? $r('app.color.status_running') : $r('app.color.status_stopped'))
              .border({ width: 2, color: $r('app.color.card_bg') })
          }
          .width(16)
          .height(16)
          // 呼吸环放大到 1.6 倍时会超出 16px 槽位，关掉 Stack 默认裁剪避免被切成圆角方块
          .clip(false)
        }
        .width(52)
        .height(52)
        .clip(false)

        Column({ space: 4 }) {
          Text(this.proxyRunning ? '安全代理运行中' : '安全代理未启动')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.proxyRunning
            ? '监听 ' + this.proxyHost + ':' + this.proxyPort.toString() + ' · 请求经安全检测转发'
            : this.proxyHost + ':' + this.proxyPort.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.proxyRunning })
          .selectedColor($r('app.color.status_running'))
          .switchPointColor(Color.White)
          .size({ width: 48, height: 26 })
          .onChange((on: boolean) => this.toggleProxy(on))
      }
      .width('100%')

      if (this.proxyRunning) {
        Row() {
          this.StatCell({ label: '已处理', value: this.totalRequests.toString() })
          this.StatCell({ label: '已拦截', value: this.blockedRequests.toString() })
          this.StatCell({ label: '供应商', value: this.providers.length.toString() })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .padding({ top: 14, bottom: 14 })
        .backgroundColor($r('app.color.section_bg'))
        .borderRadius(12)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 8 }))
          .animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    // 纯色卡面（商业质感靠阴影/描边/间距，不用渐变）；运行态只换 1px 半透明描边 + 柔和投影
    .backgroundColor($r('app.color.card_bg'))
    .border({
      width: this.proxyRunning ? 1 : 0.5,
      color: this.proxyRunning ? $r('app.color.status_running_border') : $r('app.color.border')
    })
    .shadow({
      radius: this.proxyRunning ? 20 : 12,
      color: this.proxyRunning ? '#1410B981' : '#0A000000',
      offsetX: 0,
      offsetY: this.proxyRunning ? 6 : 2
    })
  }

  /** 渠道切换条（多渠道管理）：药丸分段控件，风格对齐设置面板的主题模式分段器；选中态用皮肤色 */
  @Builder
  ChannelSwitcher() {
    Row() {
      Row({ space: 4 }) {
        ForEach(CHANNEL_APPS, (app: LocalConfigApp) => {
          Text(GatewayController.getChannelDisplayName(app))
            .fontSize(13)
            .fontWeight(this.activeApp === app ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.activeApp === app ? '#FFFFFF' : $r('app.color.text_secondary'))
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .backgroundColor(this.activeApp === app ? this.skinAccent : Color.Transparent)
            .borderRadius(16)
            .animation({ duration: 160, curve: Curve.EaseOut })
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              GatewayController.setActiveApp(app).then(() => {
                this.refresh();
              }, () => {
              });
            })
        }, (app: LocalConfigApp) => app)
      }
      .padding(4)
      .backgroundColor($r('app.color.section_bg'))
      .borderRadius(20)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  SectionHeader() {
    Row() {
      Row({ space: 8 }) {
        Text(GatewayController.getChannelDisplayName(this.activeApp) + ' 供应商')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.providers.length.toString())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.section_bg'))
          .borderRadius(8)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }

      Blank()

      Row({ space: 6 }) {
        IconPlus({ size: 14, color: this.skinAccent })
        Text('添加')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.skinAccent)
      }
      .height(32)
      .borderRadius(16)
      .backgroundColor(this.skinAccentTint)
      .padding({ left: 12, right: 12 })
      .id('btnAddProvider')
      .hoverEffect(HoverEffect.Highlight)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => this.showAdd = true)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  StatCell($$: StatCellData) {
    Column({ space: 4 }) {
      Text($$.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text($$.label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
  }

  build() {
    Stack() {
      Column({ space: 16 }) {
        this.AppHeader()

        Scroll() {
          Column({ space: 20 }) {
            this.StatusCard()
            this.ChannelSwitcher()
            this.SectionHeader()
            ProviderList({
              providers: this.providers,
              currentId: this.currentId,
              appName: GatewayController.getChannelDisplayName(this.activeApp),
              onSwitch: (p: Provider) => this.switchProvider(p),
              onEdit: (p: Provider) => this.startEdit(p),
              onDelete: (p: Provider) => this.askDelete(p),
              onDuplicate: (p: Provider) => {
                GatewayController.duplicateProvider(p.id).then(() => this.refresh());
              },
              onCreate: () => this.showAdd = true,
            })
          }
          .padding({ left: 20, right: 20, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_bg'))
      .padding({ top: this.decorTopInset })

      // 右下角托盘：运行态来自页面状态，启停/配置动作交回页面统一处理
      StatusBar({
        isRunning: this.proxyRunning,
        onToggle: () => this.toggleProxy(),
        onOpenSettings: () => { this.showSettings = true; },
      })

      // 添加供应商
      if (this.showAdd) {
        AddProviderDialog({
          appId: this.activeApp,
          onSubmit: (p: Provider) => this.addProvider(p),
          onDismiss: () => this.showAdd = false,
        })
      }

      // 编辑供应商
      if (this.isEditing) {
        EditProviderDialog({
          provider: this.editing,
          appId: this.activeApp,
          onSubmit: (p: Provider, originalId: string) => this.editSubmit(p, originalId),
          onDismiss: () => {
            this.isEditing = false;
            this.editing = emptyProvider();
          },
        })
      }

      // 删除确认（R3：脚手架走 DialogShell，按钮等宽拉伸 + 危险色确认）
      if (this.hasConfirm) {
        DialogShell({
          title: '删除供应商',
          showClose: false,
          cardWidth: 340,
          cardBg: $r('app.color.panel_bg'),
          showFooter: true,
          stretchButtons: true,
          confirmText: '删除',
          confirmColor: $r('app.color.danger'),
          onDismiss: () => {
            this.hasConfirm = false;
            this.toDelete = emptyProvider();
          },
          onConfirm: () => {
            this.confirmDelete().then(() => {
            }, () => {
            });
          },
        }) {
          Text('确定要删除「' + this.toDelete.name + '」吗？此操作不可撤销。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ left: 24, right: 24, bottom: 8 })
        }
      }

      // 设置面板
      if (this.showSettings) {
        ConfigPanel({
          onDismiss: () => this.showSettings = false,
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
