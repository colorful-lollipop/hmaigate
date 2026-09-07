/**
 * AgentConfigSection —— 本地 Agent 配置接管。
 *
 * 关联文件仅在对应渠道运行网关时临时改为本地地址；停止、切换渠道、取消关联均会
 * 恢复原文。真实 API Key 始终留在 AIGate 的应用配置中。
 */
import { DEFAULT_ACCENT } from '../../types/Skin';
import { LocalConfigApp } from '../../types/App';
import { GatewayController } from '../../app/GatewayController';
import { SectionTitle } from '../common/SectionWidgets';

@Component
struct AgentConfigLinkRow {
  @Prop title: string = '';
  @Prop path: string = '';
  @Prop linked: boolean = false;
  onToggle?: () => void;
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  build() {
    Row({ space: 14 }) {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text(this.linked ? '已关联：运行时临时指向本地网关，停止后自动还原' : this.path)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.linked ? '取消关联' : '关联')
        .height(34)
        .fontSize(13)
        .fontColor(this.linked ? $r('app.color.text_secondary') : '#FFFFFF')
        .backgroundColor(this.linked ? $r('app.color.button_secondary') : this.skinAccent)
        .borderRadius(10)
        .padding({ left: 14, right: 14 })
        .hoverEffect(HoverEffect.Highlight)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          if (this.onToggle) {
            this.onToggle();
          }
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .border({ width: 0.5, color: $r('app.color.border') })
  }
}

@Component
export struct AgentConfigSection {
  @State claudeLinked: boolean = false;
  @State codexLinked: boolean = false;
  @State openCodeLinked: boolean = false;
  @State claudeTitle: string = 'Claude Code';
  @State codexTitle: string = 'Codex';
  @State openCodeTitle: string = 'OpenCode';
  @State claudePathHint: string = '~/.claude/settings.json';
  @State codexPathHint: string = '~/.codex/config.toml';
  @State openCodePathHint: string = '~/.config/opencode/opencode.json';

  aboutToAppear(): void {
    this.refresh();
  }

  private refresh(): void {
    this.claudeLinked = GatewayController.isLocalConfigLinked('claude');
    this.codexLinked = GatewayController.isLocalConfigLinked('codex');
    this.openCodeLinked = GatewayController.isLocalConfigLinked('opencode');
    this.claudeTitle = GatewayController.getChannelDisplayName('claude');
    this.codexTitle = GatewayController.getChannelDisplayName('codex');
    this.openCodeTitle = GatewayController.getChannelDisplayName('opencode');
    this.claudePathHint = GatewayController.getLocalConfigPathHint('claude');
    this.codexPathHint = GatewayController.getLocalConfigPathHint('codex');
    this.openCodePathHint = GatewayController.getLocalConfigPathHint('opencode');
  }

  private toggle(app: LocalConfigApp): void {
    if (GatewayController.isLocalConfigLinked(app)) {
      GatewayController.unlinkLocalConfig(app).then(() => {
        this.refresh();
      }, () => {
      });
    } else {
      GatewayController.linkLocalConfig(app).then(() => {
        this.refresh();
      }, () => {
      });
    }
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '本地 Agent 配置' })
      AgentConfigLinkRow({
        title: this.claudeTitle,
        path: this.claudePathHint,
        linked: this.claudeLinked,
        onToggle: () => this.toggle('claude')
      })
      AgentConfigLinkRow({
        title: this.codexTitle,
        path: this.codexPathHint,
        linked: this.codexLinked,
        onToggle: () => this.toggle('codex')
      })
      AgentConfigLinkRow({
        title: this.openCodeTitle,
        path: this.openCodePathHint,
        linked: this.openCodeLinked,
        onToggle: () => this.toggle('opencode')
      })
    }
    .width('100%')
  }
}
