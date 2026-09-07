/**
 * CloudConfigSection —— 云端已发布配置的设备连接与手动同步。
 *
 * 密钥只写 preferences，不回显、不写日志。同步完成后 GatewayController 会热更新
 * 供应商预设、渠道显示名与安全策略；用户已创建的供应商保持本地管理。
 */
import { CloudConnectionStatus, CloudSyncResult } from '../../types/CloudConfig';
import { DEFAULT_ACCENT } from '../../types/Skin';
import { GatewayController } from '../../app/GatewayController';
import { FieldLabel, SectionTitle } from '../common/SectionWidgets';

@Component
export struct CloudConfigSection {
  @State apiBaseUrl: string = '';
  @State deviceKey: string = '';
  @State statusText: string = '尚未配置云端设备连接';
  @State syncing: boolean = false;
  @State hasDeviceKey: boolean = false;
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  aboutToAppear(): void {
    this.refreshStatus();
  }

  private refreshStatus(): void {
    const status: CloudConnectionStatus = GatewayController.getCloudConnectionStatus();
    this.apiBaseUrl = status.apiBaseUrl;
    this.deviceKey = '';
    this.hasDeviceKey = status.hasDeviceKey;
    if (status.lastError.length > 0) {
      this.statusText = status.lastError;
    } else if (status.configVersion > 0) {
      this.statusText = '已同步配置版本 ' + status.configVersion.toString();
    } else if (status.hasDeviceKey) {
      this.statusText = '设备已连接，等待首次同步';
    } else {
      this.statusText = '尚未配置云端设备连接';
    }
  }

  private async saveAndSync(): Promise<void> {
    this.syncing = true;
    const result: CloudSyncResult = await GatewayController.configureAndSyncCloud(this.apiBaseUrl, this.deviceKey);
    this.statusText = result.message;
    this.syncing = false;
    this.refreshStatus();
  }

  private async syncNow(): Promise<void> {
    this.syncing = true;
    const result: CloudSyncResult = await GatewayController.syncCloudConfig(true);
    this.statusText = result.message;
    this.syncing = false;
    this.refreshStatus();
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '云端配置' })

      Column({ space: 10 }) {
        Column({ space: 0 }) {
          FieldLabel({ text: '云端 API 地址' })
          TextInput({ placeholder: 'http://config.example.com/api/v1', text: this.apiBaseUrl })
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius(10)
            .onChange((value: string) => this.apiBaseUrl = value)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 0 }) {
          FieldLabel({ text: this.hasDeviceKey ? '设备密钥（已配置，留空保持不变）' : '设备密钥' })
          TextInput({ placeholder: 'agdk_...', text: this.deviceKey })
            .type(InputType.Password)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius(10)
            .onChange((value: string) => this.deviceKey = value)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Row({ space: 10 }) {
          Text(this.statusText)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Button('同步')
            .height(36)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.button_secondary'))
            .borderRadius(10)
            .padding({ left: 14, right: 14 })
            .enabled(!this.syncing && this.hasDeviceKey)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.syncNow().then(() => {
              }, () => {
              });
            })

          Button(this.syncing ? '同步中' : '保存并同步')
            .height(36)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor(this.skinAccent)
            .borderRadius(10)
            .padding({ left: 14, right: 14 })
            .enabled(!this.syncing)
            .hoverEffect(HoverEffect.Highlight)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.saveAndSync().then(() => {
              }, () => {
              });
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
