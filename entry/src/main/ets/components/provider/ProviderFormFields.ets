/**
 * ProviderFormFields —— 添加/编辑供应商对话框的公共表单（R3 抽取）
 *
 * 收敛 AddProviderDialog / EditProviderDialog 里近乎逐字重复的 ~90 行表单逻辑
 * （9 个 @State、buildSettingsJson、高级 JSON 编辑块；codex 形态读取复用
 * types/Provider 的 getCodexApiKey / getCodexConfigText）。
 * 表单状态自持，父组件（对话框）经 ProviderFormHandle.collect 在保存时收集结果。
 *
 * 键名一律经 types/EnvKeys 的 envKeysForApp(app) 获取（M1 数据源）——这顺带修了
 * 原 EditProviderDialog 的真 bug：其 currentApp() 只返回 claude/codex，gemini 分支
 * 永不可达，且手写 GOOGLE_GEMINI_* 键名绕过了 envKeysForApp。编辑场景行为现与
 * AddProviderDialog 对齐（claude 系保留 ANTHROPIC_API_KEY 优先探测）。
 */
import { getEnvValue, setEnvValue, getCodexApiKey, getCodexConfigText } from '../../types/Provider';
import { AppId } from '../../types/App';
import { EnvKeySet, envKeysForApp } from '../../types/EnvKeys';
import { isClaudeLikeApp } from '../../config/PresetRegistry';
import { buildCodexJson } from '../../types/Json';
import { DEFAULT_ACCENT } from '../../types/Skin';
import { LabeledInput } from '../common/LabeledInput';

/** 表单收集结果；id/category 等其余 Provider 字段由调用方按场景补齐 */
export interface ProviderFormResult {
  name: string;
  websiteUrl: string;
  settingsConfigJson: string;
}

/** 父组件持有的收集句柄，由本组件 aboutToAppear 装配（同 SectionPersistHandle 模式） */
export class ProviderFormHandle {
  /** 收集当前表单；名称为空返回 null（与原 handleSave 的早退语义一致） */
  collect: () => ProviderFormResult | null = () => null;
}

@Component
export struct ProviderFormFields {
  @Prop appId: string = 'claude';
  /** 编辑场景：true = 从 initSettingsJson 回填 apiKey 并探测 claude 系认证字段 */
  @Prop editMode: boolean = false;
  /** 初始值（编辑场景回填既有供应商；添加场景由预设选择写入） */
  @Prop initName: string = '';
  @Prop initWebsiteUrl: string = '';
  @Prop initSettingsJson: string = '';
  /** 预设指定的 apiKeyField；空串 = 取 envKeysForApp 默认 */
  @Prop initApiKeyField: string = '';
  handle: ProviderFormHandle = new ProviderFormHandle();
  // M5 换肤：强调色经 AppStorage 下发，默认值走 types/Skin 常量兜底
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  @State name: string = '';
  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State websiteUrl: string = '';
  @State apiKeyField: string = 'ANTHROPIC_AUTH_TOKEN';
  @State settingsJson: string = '';
  @State advancedEdited: boolean = false;
  @State showAdvanced: boolean = false;
  @State claudeLike: boolean = true;

  aboutToAppear(): void {
    const app: AppId = this.appId as AppId;
    const keys: EnvKeySet = envKeysForApp(app);
    this.claudeLike = isClaudeLikeApp(app);
    this.apiKeyField = this.initApiKeyField.length > 0 ? this.initApiKeyField : keys.apiKeyField;
    this.name = this.initName;
    this.websiteUrl = this.initWebsiteUrl;
    this.settingsJson = this.initSettingsJson;
    if (this.claudeLike) {
      // 从既有 JSON 回填 Base URL / 模型（添加预设与编辑共有）
      this.baseUrl = getEnvValue(this.settingsJson, keys.baseUrlKey);
      this.model = getEnvValue(this.settingsJson, keys.modelKey);
    }
    if (this.editMode) {
      if (this.claudeLike) {
        // claude 系保留既有行为：env 里显式配置了 ANTHROPIC_API_KEY 时以它为认证字段
        if (app === 'claude' && getEnvValue(this.settingsJson, 'ANTHROPIC_API_KEY') !== '') {
          this.apiKeyField = 'ANTHROPIC_API_KEY';
        }
        this.apiKey = getEnvValue(this.settingsJson, this.apiKeyField);
      } else {
        this.apiKey = getCodexApiKey(this.settingsJson);
      }
    }
    this.handle.collect = () => this.collect();
  }

  /** 收集表单；名称为空返回 null */
  private collect(): ProviderFormResult | null {
    const trimmed: string = this.name.trim();
    if (trimmed.length === 0) {
      return null;
    }
    return {
      name: trimmed,
      websiteUrl: this.websiteUrl,
      settingsConfigJson: this.buildSettingsJson(),
    };
  }

  /** 高级编辑器动过则以文本为准；否则按结构化字段回写 JSON（保留其余 env 键） */
  private buildSettingsJson(): string {
    if (this.advancedEdited) {
      return this.settingsJson;
    }
    if (!this.claudeLike) {
      return buildCodexJson(this.apiKey, getCodexConfigText(this.settingsJson));
    }
    const keys: EnvKeySet = envKeysForApp(this.appId as AppId);
    let json: string = this.settingsJson;
    json = setEnvValue(json, keys.baseUrlKey, this.baseUrl);
    json = setEnvValue(json, keys.modelKey, this.model);
    json = setEnvValue(json, this.apiKeyField, this.apiKey);
    return json;
  }

  build() {
    Column({ space: 16 }) {
      LabeledInput({
        label: '名称', placeholder: '供应商名称', value: this.name,
        onInput: (v: string) => this.name = v
      })

      if (this.claudeLike) {
        LabeledInput({
          label: 'Base URL', placeholder: 'https://api.example.com', value: this.baseUrl,
          onInput: (v: string) => this.baseUrl = v
        })

        LabeledInput({
          label: 'API Key (' + this.apiKeyField + ')', placeholder: 'sk-...', value: this.apiKey,
          onInput: (v: string) => this.apiKey = v
        })

        LabeledInput({
          label: '模型', placeholder: 'claude-sonnet-5', value: this.model,
          onInput: (v: string) => this.model = v
        })
      } else {
        LabeledInput({
          label: 'API Key (OPENAI_API_KEY)', placeholder: 'sk-...', value: this.apiKey,
          onInput: (v: string) => {
            this.apiKey = v;
            this.settingsJson = buildCodexJson(v, getCodexConfigText(this.settingsJson));
            this.advancedEdited = true;
          }
        })
      }

      LabeledInput({
        label: '官网', placeholder: 'https://', value: this.websiteUrl,
        onInput: (v: string) => this.websiteUrl = v
      })

      Row() {
        Text('高级配置 (JSON)')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.showAdvanced })
          .selectedColor(this.skinAccent)
          .switchPointColor(Color.White)
          .size({ width: 48, height: 26 })
          .onChange((on: boolean) => this.showAdvanced = on)
      }
      .width('100%')

      if (this.showAdvanced) {
        TextArea({ text: this.settingsJson })
          .width('100%')
          .height(160)
          .fontSize(12)
          .fontFamily('monospace')
          .backgroundColor($r('app.color.input_bg'))
          .borderRadius(10)
          .onChange((v: string) => {
            this.settingsJson = v;
            this.advancedEdited = true;
          })
      }
    }
    .width('100%')
    .padding(20)
  }
}
