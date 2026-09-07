/**
 * EditProviderDialog —— 编辑供应商（精致化）
 *
 * 与 AddProviderDialog 共用 ProviderFormFields 表单（R3 抽取），保存时返回带原 id
 * 的 Provider。脚手架走 common/DialogShell（顺带补上与其他对话框一致的遮罩）。
 * env 键名经 types/EnvKeys 的 envKeysForApp(app) 获取（修复原 currentApp() 只认
 * claude/codex、gemini 分支永不可达的 bug，行为对齐 AddProviderDialog）。
 */
import { Provider } from '../../types/Provider';
import { DEFAULT_ACCENT } from '../../types/Skin';
import { DialogShell } from '../common/DialogShell';
import { ProviderFormFields, ProviderFormHandle, ProviderFormResult } from './ProviderFormFields';

@Component
export struct EditProviderDialog {
  @Prop provider: Provider;
  /** 当前 Agent（决定 env 键名与表单形态，与 AddProviderDialog 同一来源） */
  @Prop appId: string;
  // M5 换肤：强调色经 AppStorage 下发，默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;
  onSubmit: (p: Provider, originalId: string) => void = (p: Provider, originalId: string) => {};
  onDismiss: () => void = () => {};
  private formHandle: ProviderFormHandle = new ProviderFormHandle();

  private handleSave(): void {
    const result: ProviderFormResult | null = this.formHandle.collect();
    if (result === null) {
      return;
    }
    const updated: Provider = {
      id: this.provider.id,
      name: result.name,
      settingsConfigJson: result.settingsConfigJson,
      websiteUrl: result.websiteUrl,
      category: this.provider.category,
      icon: this.provider.icon,
      iconColor: this.provider.iconColor,
      isPartner: this.provider.isPartner,
    };
    this.onSubmit(updated, this.provider.id);
  }

  build() {
    DialogShell({
      title: '编辑供应商',
      cardWidth: 520,
      cardHeight: 640,
      showFooter: true,
      confirmColor: this.skinAccent,
      onDismiss: this.onDismiss,
      onConfirm: () => this.handleSave(),
    }) {
      ProviderFormFields({
        appId: this.appId,
        editMode: true,
        initName: this.provider.name,
        initWebsiteUrl: this.provider.websiteUrl ? this.provider.websiteUrl : '',
        initSettingsJson: this.provider.settingsConfigJson,
        handle: this.formHandle,
      })
    }
  }
}
