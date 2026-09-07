/**
 * AddProviderDialog —— 添加供应商（精致化）
 *
 * 两步：① 选择预设（含“自定义”） ② 填写表单。
 * 脚手架走 common/DialogShell（R3）；表单字段已抽为 ProviderFormFields（R3），
 * 本组件只保留预设选择步与保存编排。
 */
import { Provider } from '../../types/Provider';
import { ProviderPreset, categoryLabel } from '../../types/Preset';
import { isClaudeLikeApp } from '../../config/PresetRegistry';
import { AppId } from '../../types/App';
import { GatewayController } from '../../app/GatewayController';
import { DEFAULT_ACCENT, DEFAULT_ACCENT_TINT } from '../../types/Skin';
import { IconChevronRight, IconPlus } from '../Icons';
import { DialogShell } from '../common/DialogShell';
import { ProviderFormFields, ProviderFormHandle, ProviderFormResult } from './ProviderFormFields';

@Component
export struct AddProviderDialog {
  @Prop appId: string;
  // M5 换肤：强调色经 AppStorage 下发，默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  @StorageLink('skinAccentTint') skinAccentTint: string = DEFAULT_ACCENT_TINT;
  onSubmit: (p: Provider) => void = (p: Provider) => {};
  onDismiss: () => void = () => {};

  @State mode: number = 0; // 0 = 预设选择, 1 = 表单
  @State presets: ProviderPreset[] = [];
  // 预设选择结果，作为表单初始值传入 ProviderFormFields
  @State initName: string = '';
  @State initWebsiteUrl: string = '';
  @State initSettingsJson: string = '';
  @State initApiKeyField: string = '';
  private formHandle: ProviderFormHandle = new ProviderFormHandle();

  aboutToAppear(): void {
    this.presets = GatewayController.getProviderPresets(this.appId as AppId);
  }

  private pickPreset(preset: ProviderPreset): void {
    this.initSettingsJson = preset.settingsConfigJson;
    this.initName = preset.name;
    this.initWebsiteUrl = preset.websiteUrl;
    this.initApiKeyField = preset.apiKeyField ? preset.apiKeyField : '';
    this.mode = 1;
  }

  private pickCustom(): void {
    this.initSettingsJson = isClaudeLikeApp(this.appId as AppId) ? '{"env":{}}' : '{"auth":{},"config":""}';
    this.initName = '自定义供应商';
    this.initWebsiteUrl = '';
    this.initApiKeyField = '';
    this.mode = 1;
  }

  private handleSave(): void {
    const result: ProviderFormResult | null = this.formHandle.collect();
    if (result === null) {
      return;
    }
    const provider: Provider = {
      id: '',
      name: result.name,
      settingsConfigJson: result.settingsConfigJson,
      websiteUrl: result.websiteUrl,
    };
    this.onSubmit(provider);
  }

  @Builder
  PresetTile(preset: ProviderPreset) {
    Row() {
      Column() {
        Text(preset.name.charAt(0).toUpperCase())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(preset.iconColor ? preset.iconColor : this.skinAccent)
      .borderRadius(12)

      Column({ space: 3 }) {
        Text(preset.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((preset.isCloudPreset ? '云端预设 · ' : '') + categoryLabel(preset.category))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 12 })
      .layoutWeight(1)

      IconChevronRight({ size: 18, color: $r('app.color.text_tertiary') })
    }
    .width('90%')
    .height(64)
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
    .border({ width: 0.5, color: $r('app.color.border') })
    .shadow({ radius: 6, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .onClick(() => this.pickPreset(preset))
  }

  @Builder
  CustomEntry() {
    Row() {
      Stack() {
        IconPlus({ size: 20, color: this.skinAccent })
      }
      .width(36)
      .height(36)
      .backgroundColor(this.skinAccentTint)
      .borderRadius(12)

      Text('自定义供应商')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.skinAccent)
        .layoutWeight(1)
        .margin({ left: 12, right: 12 })

      IconChevronRight({ size: 18, color: this.skinAccent })
    }
    .width('90%')
    .height(64)
    .padding(12)
    .backgroundColor(this.skinAccentTint)
    .borderRadius(14)
    .border({ width: 1, color: this.skinAccentTint })
    .onClick(() => this.pickCustom())
  }

  @Builder
  PresetSelector() {
    Column({ space: 12 }) {
      this.CustomEntry()

      ForEach(this.presets, (preset: ProviderPreset) => {
        this.PresetTile(preset)
      }, (preset: ProviderPreset) => preset.name + preset.websiteUrl)
    }
    .width('100%')
    .padding(20)
  }

  build() {
    if (this.mode === 0) {
      // 预设选择步：自适应高度、无底部按钮
      DialogShell({
        title: '选择预设',
        cardWidth: 520,
        onDismiss: this.onDismiss,
      }) {
        this.PresetSelector()
      }
    } else {
      // 表单步：固定高度 + 返回钮 + 取消/保存
      DialogShell({
        title: '添加供应商',
        cardWidth: 520,
        cardHeight: 640,
        showBack: true,
        onBack: () => {
          this.mode = 0;
        },
        showFooter: true,
        confirmColor: this.skinAccent,
        onDismiss: this.onDismiss,
        onConfirm: () => this.handleSave(),
      }) {
        ProviderFormFields({
          appId: this.appId,
          initName: this.initName,
          initWebsiteUrl: this.initWebsiteUrl,
          initSettingsJson: this.initSettingsJson,
          initApiKeyField: this.initApiKeyField,
          handle: this.formHandle,
        })
      }
    }
  }
}
