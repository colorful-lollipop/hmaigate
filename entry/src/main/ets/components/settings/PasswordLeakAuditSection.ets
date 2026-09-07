/** 密码泄露提醒设置：异步扫描只提示，不阻断正常转发。 */
import { GatewayController } from '../../app/GatewayController';
import { PasswordLeakAlert, PasswordLeakAuditViewState } from '../../types/PasswordLeakAudit';
import { DEFAULT_ACCENT } from '../../types/Skin';
import { SectionTitle, ToggleRow } from '../common/SectionWidgets';

interface PasswordLeakAlertDisplay {
  alert: PasswordLeakAlert;
  timeText: string;
  typeText: string;
  locationText: string;
}

function formatAlertTime(timeMs: number): string {
  const date: Date = new Date(timeMs);
  const year: string = date.getFullYear().toString();
  const month: string = (date.getMonth() + 1).toString().padStart(2, '0');
  const day: string = date.getDate().toString().padStart(2, '0');
  const hour: string = date.getHours().toString().padStart(2, '0');
  const minute: string = date.getMinutes().toString().padStart(2, '0');
  return year + '-' + month + '-' + day + ' ' + hour + ':' + minute;
}

function secretTypeText(secretType: string): string {
  if (secretType === 'api_key') return 'API Key';
  if (secretType === 'private_key') return '私钥';
  if (secretType === 'password') return '密码';
  if (secretType === 'token') return 'Token';
  return '凭据';
}

function locationText(location: string): string {
  if (location === 'json_field') return 'JSON 字段';
  if (location === 'env_assignment') return '环境变量';
  if (location === 'known_pattern') return '已知格式';
  return '代码文本';
}

function toDisplay(alerts: PasswordLeakAlert[]): PasswordLeakAlertDisplay[] {
  const out: PasswordLeakAlertDisplay[] = [];
  for (const alert of alerts) {
    out.push({
      alert: alert,
      timeText: formatAlertTime(alert.timeMs),
      typeText: secretTypeText(alert.secretType),
      locationText: locationText(alert.location),
    });
  }
  return out;
}

@Component
export struct PasswordLeakAuditSection {
  @State auditEnabled: boolean = true;
  @State unreadCount: number = 0;
  @State todayCount: number = 0;
  @State lastAlertTimeText: string = '暂无';
  @State alerts: PasswordLeakAlertDisplay[] = [];
  @State busy: boolean = false;
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  aboutToAppear(): void {
    this.auditEnabled = GatewayController.getPasswordLeakAuditEnabled();
    this.refresh().then(() => {}, () => {});
  }

  private applyView(view: PasswordLeakAuditViewState): void {
    this.auditEnabled = view.enabled;
    this.unreadCount = view.unreadCount;
    this.todayCount = view.todayCount;
    this.lastAlertTimeText = view.lastAlertTimeMs > 0 ? formatAlertTime(view.lastAlertTimeMs) : '暂无';
    this.alerts = toDisplay(view.alerts);
  }

  private async refresh(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const view: PasswordLeakAuditViewState = await GatewayController.refreshPasswordLeakAudit();
    this.applyView(view);
    this.busy = false;
  }

  private async toggle(enabled: boolean): Promise<void> {
    this.auditEnabled = enabled;
    await GatewayController.setPasswordLeakAuditEnabled(enabled);
    const view: PasswordLeakAuditViewState = await GatewayController.refreshPasswordLeakAudit();
    this.applyView(view);
  }

  private async markRead(): Promise<void> {
    const view: PasswordLeakAuditViewState = await GatewayController.markPasswordLeakAlertsRead();
    this.applyView(view);
  }

  private async clear(): Promise<void> {
    const view: PasswordLeakAuditViewState = await GatewayController.clearPasswordLeakAlerts();
    this.applyView(view);
  }

  @Builder
  StatCell(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  AlertRow(item: PasswordLeakAlertDisplay) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(item.alert.severity === 'high' ? '高风险' : '中风险')
            .fontSize(12)
            .fontColor($r('app.color.danger'))
          Text(item.typeText)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Text(item.locationText)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Row({ space: 6 }) {
          Text(item.alert.protocol + ' / ' + item.alert.model)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(item.timeText)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(item.alert.status === 'new' ? '未读' : '已读')
        .fontSize(11)
        .fontColor(item.alert.status === 'new' ? this.skinAccent : $r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '密码泄露提醒' })
      Column({ space: 10 }) {
        ToggleRow({
          label: '扫描可能泄露的密码和密钥',
          isOn: this.auditEnabled,
          onToggle: (isOn: boolean) => {
            this.toggle(isOn).then(() => {}, () => {});
          }
        })
        Row({ space: 8 }) {
          this.StatCell(this.unreadCount.toString(), '未读')
          this.StatCell(this.todayCount.toString(), '今日发现')
          this.StatCell(this.lastAlertTimeText, '最近发现')
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        if (this.alerts.length === 0) {
          Text('暂无泄露提醒')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          Column() {
            ForEach(this.alerts, (item: PasswordLeakAlertDisplay) => {
              this.AlertRow(item)
              Divider().color($r('app.color.divider')).strokeWidth(0.5)
            }, (item: PasswordLeakAlertDisplay) => item.alert.id)
          }
          .width('100%')
          .height(320)
        }

        Row({ space: 8 }) {
          Button('刷新')
            .height(34)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.refresh().then(() => {}, () => {});
            })
          Button('标为已读')
            .height(34)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.markRead().then(() => {}, () => {});
            })
          Button('清空历史')
            .height(34)
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.clear().then(() => {}, () => {});
            })
        }
        .width('100%')
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
