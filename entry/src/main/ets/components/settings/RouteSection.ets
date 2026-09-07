/**
 * RouteSection —— 设置面板「智能路由」分组 + 规则编辑对话框（R3 从 ConfigPanel 拆出）
 *
 * 规则即时生效（CRUD 走 GatewayController，落库 + 热更新），不经壳的「保存」按钮。
 * RouteRuleDialog：添加/编辑单条规则，由壳挂载（对话框需覆盖整个面板），
 * 表单字段用 common/LabeledInput，协议/供应商选择器保留原实现。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Provider } from '../../types/Provider';
import {
  RouteRule, RouteProtocol, ROUTE_PROTOCOLS,
  defaultRouteRule, validateRouteRule
} from '../../types/RouteRule';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../../types/Skin';
import { GatewayController } from '../../app/GatewayController';
import { DialogShell } from '../common/DialogShell';
import { LabeledInput } from '../common/LabeledInput';
import { FieldLabel, SectionPersistHandle, SectionTitle } from '../common/SectionWidgets';
import { IconCheck, IconEdit, IconTrash } from '../Icons';

const DOMAIN = 0x0000;
const TAG = 'RouteSection';

@Component
export struct RouteSection {
  @State routeRules: RouteRule[] = [];
  @State providers: Provider[] = [];
  /** 壳传入的动作句柄，aboutToAppear 时装配 refresh（规则对话框关闭后重读列表） */
  handle: SectionPersistHandle = new SectionPersistHandle();
  /** 打开添加（rule 为 null）/ 编辑规则对话框（对话框由壳挂载，事件上浮） */
  onEditRule: (rule: RouteRule | null) => void = (rule: RouteRule | null) => {};
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  aboutToAppear(): void {
    this.refreshRouteRules();
    this.handle.refresh = () => {
      this.refreshRouteRules();
    };
  }

  /** 从 GatewayController 重读路由规则与供应商列表（供应商名用于规则行展示） */
  private refreshRouteRules(): void {
    this.routeRules = GatewayController.getRouteRules();
    this.providers = GatewayController.getProviders();
  }

  /** 规则行展示的供应商名；供应商已删时给出提示文案 */
  private providerNameFor(providerId: string): string {
    for (const p of this.providers) {
      if (p.id === providerId) {
        return p.name;
      }
    }
    return '供应商已删除';
  }

  /** 删除规则：经 GatewayController 落库并热更新 */
  private async handleDeleteRule(id: string): Promise<void> {
    await GatewayController.removeRouteRule(id);
    this.refreshRouteRules();
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '智能路由' })

      Column({ space: 4 }) {
        if (this.routeRules.length === 0) {
          Text('暂无路由规则。未配置规则时全部请求走当前供应商')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 6, bottom: 6 })
        }

        ForEach(this.routeRules, (rule: RouteRule) => {
          Row() {
            Column({ space: 2 }) {
              Text(rule.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text('model:' + (rule.modelPrefix ? rule.modelPrefix + '*' : '任意') +
                ' · 协议:' + rule.protocol +
                ' · 优先级:' + rule.priority.toString())
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              Text('→ ' + this.providerNameFor(rule.providerId))
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Stack() {
              IconEdit({ size: 16, color: $r('app.color.text_secondary') })
            }
            .width(32)
            .height(32)
            .onClick(() => this.onEditRule(rule))

            Stack() {
              IconTrash({ size: 16, color: $r('app.color.danger') })
            }
            .width(32)
            .height(32)
            .margin({ left: 4 })
            .onClick(() => {
              this.handleDeleteRule(rule.id).then(() => {
              }, () => {
              });
            })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (rule: RouteRule) => rule.id)

        Row() {
          Blank()
          Button('添加规则')
            .height(34)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor(this.skinAccent)
            .borderRadius(10)
            .padding({ left: 14, right: 14 })
            .onClick(() => this.onEditRule(null))
        }
        .width('100%')
        .padding({ top: 4 })
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

/** 添加/编辑路由规则对话框（遮罩 + 居中卡片，由壳挂载以覆盖整个面板） */
@Component
export struct RouteRuleDialog {
  /** 编辑目标；null = 新增 */
  target: RouteRule | null = null;
  /** 可选供应商（打开时由壳快照传入） */
  providers: Provider[] = [];
  onDismiss: () => void = () => {};
  @State editingRuleId: string = ''; // 空串 = 新增
  @State ruleName: string = '';
  @State rulePriority: string = '10';
  @State ruleModelPrefix: string = '';
  @State ruleProtocol: RouteProtocol = 'any';
  @State rulePathPrefix: string = '';
  @State ruleProviderId: string = '';
  @State ruleError: string = '';
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;

  aboutToAppear(): void {
    const r: RouteRule = this.target !== null ? this.target : defaultRouteRule();
    this.editingRuleId = r.id;
    this.ruleName = r.name;
    this.rulePriority = r.priority.toString();
    this.ruleModelPrefix = r.modelPrefix;
    this.ruleProtocol = r.protocol;
    this.rulePathPrefix = r.pathPrefix;
    this.ruleProviderId = r.providerId
      ? r.providerId
      : (this.providers.length > 0 ? this.providers[0].id : '');
    this.ruleError = '';
  }

  /** 保存规则：校验 → 经 GatewayController 落库并热更新（applyRouteRules）→ 关闭 */
  private async handleSaveRule(): Promise<void> {
    const rule: RouteRule = {
      id: this.editingRuleId,
      name: this.ruleName.trim(),
      priority: parseInt(this.rulePriority) || 0,
      modelPrefix: this.ruleModelPrefix.trim(),
      protocol: this.ruleProtocol,
      pathPrefix: this.rulePathPrefix.trim(),
      providerId: this.ruleProviderId,
    };
    const err: string = validateRouteRule(rule);
    if (err) {
      this.ruleError = err;
      return;
    }
    if (this.editingRuleId) {
      await GatewayController.updateRouteRule(rule);
    } else {
      await GatewayController.addRouteRule(rule);
    }
    hilog.info(DOMAIN, TAG, `route rule saved: ${rule.name}`);
    this.onDismiss();
  }

  build() {
    DialogShell({
      title: this.editingRuleId ? '编辑规则' : '添加规则',
      cardWidth: 460,
      cardHeight: 500,
      showFooter: true,
      confirmColor: this.skinAccent,
      onDismiss: this.onDismiss,
      onConfirm: () => {
        this.handleSaveRule().then(() => {
        }, () => {
        });
      },
    }) {
      Column({ space: 14 }) {
        LabeledInput({
          label: '名称', placeholder: '如：GLM 系走智谱', value: this.ruleName,
          onInput: (v: string) => this.ruleName = v
        })

        LabeledInput({
          label: '优先级（0-9999，大者优先）', placeholder: '10', value: this.rulePriority,
          inputType: InputType.Number,
          onInput: (v: string) => this.rulePriority = v
        })

        LabeledInput({
          label: '模型前缀（留空匹配任意模型）', placeholder: '如：glm', value: this.ruleModelPrefix,
          onInput: (v: string) => this.ruleModelPrefix = v
        })

        Column() {
          FieldLabel({ text: '协议' })
          Row({ space: 8 }) {
            ForEach(ROUTE_PROTOCOLS, (p: RouteProtocol) => {
              Text(p)
                .fontSize(13)
                .fontColor(this.ruleProtocol === p ? '#FFFFFF' : $r('app.color.text_secondary'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.ruleProtocol === p
                  ? this.skinAccent
                  : $r('app.color.button_secondary'))
                .borderRadius(8)
                .onClick(() => {
                  this.ruleProtocol = p;
                })
            }, (p: RouteProtocol) => p)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        LabeledInput({
          label: '路径前缀（留空匹配任意路径）', placeholder: '如：/v1/messages', value: this.rulePathPrefix,
          onInput: (v: string) => this.rulePathPrefix = v
        })

        Column() {
          FieldLabel({ text: '目标供应商' })
          if (this.providers.length === 0) {
            Text('暂无供应商，请先在主页添加')
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .width('100%')
          }
          ForEach(this.providers, (p: Provider) => {
            Row() {
              Text(p.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              if (this.ruleProviderId === p.id) {
                IconCheck({ size: 18, color: this.skinAccent })
              }
            }
            .width('100%')
            .height(40)
            .padding({ left: 12, right: 12 })
            .backgroundColor(this.ruleProviderId === p.id
              ? this.skinAccentTint
              : $r('app.color.input_bg'))
            .borderRadius(10)
            .onClick(() => {
              this.ruleProviderId = p.id;
            })
          }, (p: Provider) => p.id)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        if (this.ruleError) {
          Text(this.ruleError)
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })
    }
  }
}
