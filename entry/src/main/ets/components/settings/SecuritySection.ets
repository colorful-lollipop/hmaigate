/**
 * SecuritySection —— 设置面板「安全设置」分组 + 规则自定义对话框（R3 从 ConfigPanel 拆出）
 *
 * 分组本体：安全检测开关（本地态，壳「保存」时经 handle 持久化）、响应侧检测开关
 * （即时生效，走 GatewayController.setResponseSecurityEnabled）、规则列表（开关走
 * SecurityService NAPI 即时生效）。
 * CustomRuleDialog：管理某条规则的自定义关键词/正则，词条增删即时生效（走
 * GatewayController 的 M4 词条入口），由壳挂载（对话框需覆盖整个面板）。
 */
import { SecurityRule, RuleCustomEntry } from '../../types/SecurityTypes';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../../types/Skin';
import { SecurityService } from '../../services/SecurityService';
import { GatewayController } from '../../app/GatewayController';
import { DialogShell } from '../common/DialogShell';
import { FieldLabel, SectionPersistHandle, SectionTitle, ToggleRow } from '../common/SectionWidgets';
import { IconClose } from '../Icons';

@Component
export struct SecuritySection {
  @State securityEnabled: boolean = true;
  @State securityRules: SecurityRule[] = [];
  @State responseSecurityEnabled: boolean = true;
  /** 壳传入的动作句柄，aboutToAppear 时装配 save/reset/refresh */
  handle: SectionPersistHandle = new SectionPersistHandle();
  /** 打开规则自定义对话框（对话框由壳挂载，事件上浮） */
  onOpenCustom: (rule: SecurityRule) => void = (rule: SecurityRule) => {};
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;

  aboutToAppear(): void {
    this.securityEnabled = GatewayController.getSecurityEnabled();
    this.refreshSecurity();
    this.handle.save = async () => {
      await GatewayController.setSecurityEnabled(this.securityEnabled);
    };
    this.handle.reset = () => {
      this.securityEnabled = true;
    };
    this.handle.refresh = () => {
      this.refreshSecurity();
    };
  }

  /** 从 GatewayController 重读安全规则列表与响应检测开关（M4） */
  private refreshSecurity(): void {
    this.securityRules = GatewayController.getSecurityRules();
    this.responseSecurityEnabled = GatewayController.getResponseSecurityEnabled();
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '安全设置' })

      Column({ space: 4 }) {
        ToggleRow({
          label: '启用安全检测', isOn: this.securityEnabled, onToggle: (isOn: boolean) => {
            this.securityEnabled = isOn;
          }
        })

        Divider().color($r('app.color.divider')).strokeWidth(0.5)

        // M4：响应侧检测即时生效（持久化 + 下发 C++），不经底部「保存」按钮
        ToggleRow({
          label: '响应安全检测', isOn: this.responseSecurityEnabled, onToggle: (isOn: boolean) => {
            this.responseSecurityEnabled = isOn;
            GatewayController.setResponseSecurityEnabled(isOn).then(() => {
            }, () => {
            });
          }
        })

        Divider().color($r('app.color.divider')).strokeWidth(0.5)

        // 安全规则列表（M4：含命中计数 + 自定义词条入口）
        ForEach(this.securityRules, (rule: SecurityRule) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(rule.name)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              if (rule.hitCount > 0) {
                Text('已拦截 ' + rule.hitCount.toString() + ' 次')
                  .fontSize(11)
                  .fontColor($r('app.color.danger'))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('自定义')
              .fontSize(12)
              .fontColor(this.skinAccent)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(this.skinAccentTint)
              .borderRadius(8)
              .onClick(() => this.onOpenCustom(rule))

            Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
              .selectedColor(this.skinAccent)
              .switchPointColor(Color.White)
              .size({ width: 48, height: 26 })
              .onChange((isOn: boolean) => {
                SecurityService.setRuleEnabled(rule.id, isOn);
                this.refreshSecurity();
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (rule: SecurityRule) => rule.id)
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

/** 规则自定义对话框（M4）：管理某条规则的自定义关键词/正则，改动即时生效 */
@Component
export struct CustomRuleDialog {
  @Prop ruleId: string = '';
  @Prop ruleName: string = '';
  onDismiss: () => void = () => {};
  @State customKeywords: string[] = [];
  @State customPatterns: string[] = [];
  @State customInput: string = '';
  @State customInputIsPattern: boolean = false;
  @State customError: string = '';
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  aboutToAppear(): void {
    this.refreshCustomLists();
  }

  /** 重读当前编辑规则的自定义词条（持久化回放源为准） */
  private refreshCustomLists(): void {
    const entry: RuleCustomEntry = GatewayController.getRuleCustomEntry(this.ruleId);
    this.customKeywords = entry.keywords;
    this.customPatterns = entry.patterns;
  }

  /** 添加自定义词条：经 GatewayController 下发 C++ 并持久化，成功后刷新列表 */
  private async handleAddCustom(): Promise<void> {
    const value: string = this.customInput.trim();
    if (value.length === 0) {
      this.customError = '请输入内容';
      return;
    }
    const err: string = this.customInputIsPattern
      ? await GatewayController.addRulePattern(this.ruleId, value)
      : await GatewayController.addRuleKeyword(this.ruleId, value);
    if (err.length > 0) {
      this.customError = err;
      return;
    }
    this.customInput = '';
    this.customError = '';
    this.refreshCustomLists();
  }

  /** 删除自定义词条：经 GatewayController 下发 C++ 并持久化 */
  private async handleRemoveCustom(isPattern: boolean, value: string): Promise<void> {
    const err: string = isPattern
      ? await GatewayController.removeRulePattern(this.ruleId, value)
      : await GatewayController.removeRuleKeyword(this.ruleId, value);
    if (err.length > 0) {
      this.customError = err;
      return;
    }
    this.customError = '';
    this.refreshCustomLists();
  }

  /** 自定义词条行（关键词/正则共用）：内容 + 删除按钮 */
  @Builder
  CustomTokenRow(isPattern: boolean, value: string) {
    Row() {
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Stack() {
        IconClose({ size: 14, color: $r('app.color.danger') })
      }
      .width(28)
      .height(28)
      .onClick(() => {
        this.handleRemoveCustom(isPattern, value).then(() => {
        }, () => {
        });
      })
    }
    .width('100%')
    .height(36)
    .padding({ left: 12, right: 6 })
    .backgroundColor($r('app.color.input_bg'))
    .borderRadius(8)
  }

  build() {
    DialogShell({
      title: '自定义规则 · ' + this.ruleName,
      cardWidth: 460,
      cardHeight: 460,
      showFooter: true,
      showCancel: false,
      confirmText: '完成', // 词条增删即时生效，无需保存
      confirmColor: this.skinAccent,
      onDismiss: this.onDismiss,
      onConfirm: this.onDismiss,
    }) {
      Column({ space: 14 }) {
        // 关键词列表
        Column({ space: 6 }) {
          FieldLabel({ text: '自定义关键词' })
          if (this.customKeywords.length === 0) {
            Text('暂无自定义关键词')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          ForEach(this.customKeywords, (kw: string) => {
            this.CustomTokenRow(false, kw)
          }, (kw: string) => kw)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // 正则列表
        Column({ space: 6 }) {
          FieldLabel({ text: '自定义正则' })
          if (this.customPatterns.length === 0) {
            Text('暂无自定义正则')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          ForEach(this.customPatterns, (p: string) => {
            this.CustomTokenRow(true, p)
          }, (p: string) => p)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // 添加区（类型选择 + 输入框）
        Column({ space: 8 }) {
          FieldLabel({ text: '添加词条' })
          Row({ space: 8 }) {
            Text('关键词')
              .fontSize(13)
              .fontColor(!this.customInputIsPattern ? '#FFFFFF' : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(!this.customInputIsPattern
                ? this.skinAccent
                : $r('app.color.button_secondary'))
              .borderRadius(8)
              .onClick(() => {
                this.customInputIsPattern = false;
              })
            Text('正则')
              .fontSize(13)
              .fontColor(this.customInputIsPattern ? '#FFFFFF' : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.customInputIsPattern
                ? this.skinAccent
                : $r('app.color.button_secondary'))
              .borderRadius(8)
              .onClick(() => {
                this.customInputIsPattern = true;
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({
              placeholder: this.customInputIsPattern ? '如：(?i)token\\s*[:=]' : '如：内部密码',
              text: this.customInput
            })
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .backgroundColor($r('app.color.input_bg'))
              .borderRadius(10)
              .onChange((v: string) => this.customInput = v)
            Button('添加')
              .height(40)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(this.skinAccent)
              .borderRadius(10)
              .padding({ left: 18, right: 18 })
              .onClick(() => {
                this.handleAddCustom().then(() => {
                }, () => {
                });
              })
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        if (this.customError) {
          Text(this.customError)
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
