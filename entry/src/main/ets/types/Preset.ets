/**
 * 预设供应商模板 —— 移植自 cc-switch src/config/claudeProviderPresets.ts (ProviderPreset)
 *
 * 与 cc-switch 一致：每个预设本质就是一段 settingsConfig（Claude 为 settings.json 的 env）。
 * 本移植直接以 settingsConfigJson（JSON 字符串）承载，presetToProvider 直接复用。
 */
import { Provider, ProviderCategory, ClaudeApiKeyField } from './Provider';

/** 模板变量定义（对应 cc-switch TemplateValueConfig） */
export interface TemplateValueConfig {
  label: string;
  placeholder: string;
  defaultValue?: string;
  editorValue: string;
}

/** 预设视觉主题（对应 cc-switch PresetTheme） */
export interface PresetTheme {
  icon?: string;
  backgroundColor?: string;
  textColor?: string;
  /** 暗色变体（M5）：固定十六进制底色在暗色下可能刺眼，消费方按当前亮暗态二选一 */
  backgroundColorDark?: string;
  textColorDark?: string;
}

/**
 * 按当前亮暗态取预设底色（暗色变体缺失时回退亮色值）。
 * 说明：当前供应商卡片头像走 categoryColor/iconColor（ProviderCard 自管暗色变体），
 * PresetTheme 供后续预设卡片 UI 消费；isDark 来自 AppStorage 的 themeIsDark。
 */
export function presetThemeBackground(theme: PresetTheme | undefined, isDark: boolean): string | undefined {
  if (theme === undefined) {
    return undefined;
  }
  if (isDark && theme.backgroundColorDark !== undefined) {
    return theme.backgroundColorDark;
  }
  return theme.backgroundColor;
}

/** API 格式（Claude 供应商使用） */
export type ApiFormat = 'anthropic' | 'openai_chat' | 'openai_responses' | 'gemini_native';

/** 预设供应商模板（对应 cc-switch ProviderPreset） */
export interface ProviderPreset {
  name: string;
  nameKey?: string;
  websiteUrl: string;
  apiKeyUrl?: string;
  /** 该预设对应的配置 JSON（Claude 形态：{env:{...}}；Codex 形态：{auth,config}） */
  settingsConfigJson: string;
  isOfficial?: boolean;
  isPartner?: boolean;
  primePartner?: boolean;
  partnerPromotionKey?: string;
  category?: ProviderCategory;
  apiKeyField?: ClaudeApiKeyField;
  templateValues?: Record<string, TemplateValueConfig>;
  endpointCandidates?: string[];
  theme?: PresetTheme;
  icon?: string;
  iconColor?: string;
  apiFormat?: ApiFormat;
  providerType?: string;
  requiresOAuth?: boolean;
  modelsUrl?: string;
  hidden?: boolean;
  /** 云端下发的预设；仅作为添加供应商时的表单初始值，不是供应商实例。 */
  isCloudPreset?: boolean;
}

/** 分类展示名 */
export function categoryLabel(c?: ProviderCategory): string {
  switch (c) {
    case 'official':
      return '官方';
    case 'cn_official':
      return '国产官方';
    case 'cloud_provider':
      return '云服务商';
    case 'aggregator':
      return '聚合站';
    case 'third_party':
      return '第三方';
    case 'custom':
      return '自定义';
    case 'omo':
      return 'OMO';
    case 'omo-slim':
      return 'OMO Slim';
    default:
      return '';
  }
}

/** 由预设生成一个新的 Provider（id 留空，由 Store 补全） */
export function presetToProvider(preset: ProviderPreset): Provider {
  return {
    id: '',
    name: preset.name,
    settingsConfigJson: preset.settingsConfigJson,
    websiteUrl: preset.websiteUrl,
    category: preset.category,
    isPartner: preset.isPartner ?? preset.primePartner,
    icon: preset.icon,
    iconColor: preset.iconColor,
  };
}
