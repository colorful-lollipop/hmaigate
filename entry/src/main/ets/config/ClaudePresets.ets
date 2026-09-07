/**
 * Claude 预设供应商配置模板（精简版）
 *
 * 按需只保留少量常用预设；自定义供应商为首选入口（在 AddProviderDialog 中提供）。
 * settingsConfig 预序列化为 settingsConfigJson（{"env":{...}}）。
 */
import { ProviderPreset } from '../types/Preset';

/** Claude settings.json 的 env 字段 */
interface ClaudeEnv {
  ANTHROPIC_BASE_URL?: string;
  ANTHROPIC_AUTH_TOKEN?: string;
  ANTHROPIC_API_KEY?: string;
  ANTHROPIC_MODEL?: string;
  ANTHROPIC_DEFAULT_HAIKU_MODEL?: string;
  ANTHROPIC_DEFAULT_SONNET_MODEL?: string;
  ANTHROPIC_DEFAULT_OPUS_MODEL?: string;
  API_TIMEOUT_MS?: string;
}

interface ClaudeSettings {
  env: ClaudeEnv;
}

function mk(env: ClaudeEnv): string {
  const cfg: ClaudeSettings = { env: env };
  return JSON.stringify(cfg);
}

export const claudeProviderPresets: ProviderPreset[] = [
  {
    name: 'Claude Official',
    websiteUrl: 'https://www.anthropic.com/claude-code',
    settingsConfigJson: mk({}),
    isOfficial: true,
    category: 'official',
    theme: { icon: 'claude', backgroundColor: '#D97757', textColor: '#FFFFFF' },
    icon: 'anthropic',
    iconColor: '#D4915D',
  },
  {
    name: 'Zhipu GLM',
    websiteUrl: 'https://open.bigmodel.cn',
    apiKeyUrl: 'https://www.bigmodel.cn/claude-code?ic=RRVJPB5SII',
    settingsConfigJson: mk({
      ANTHROPIC_BASE_URL: 'https://open.bigmodel.cn/api/anthropic',
      ANTHROPIC_AUTH_TOKEN: '',
      ANTHROPIC_MODEL: 'glm-5.1',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'glm-5.1',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'glm-5.1',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'glm-5.1',
    }),
    category: 'cn_official',
    icon: 'zhipu',
    iconColor: '#0F62FE',
  },
  {
    name: 'MiniMax',
    websiteUrl: 'https://platform.minimaxi.com',
    apiKeyUrl: 'https://platform.minimaxi.com/subscribe/coding-plan',
    settingsConfigJson: mk({
      ANTHROPIC_BASE_URL: 'https://api.minimaxi.com/anthropic',
      ANTHROPIC_AUTH_TOKEN: '',
      API_TIMEOUT_MS: '3000000',
      ANTHROPIC_MODEL: 'MiniMax-M2.7',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'MiniMax-M2.7',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'MiniMax-M2.7',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'MiniMax-M2.7',
    }),
    category: 'cn_official',
    icon: 'minimax',
    iconColor: '#FF6B6B',
  },
  {
    name: 'Kimi',
    websiteUrl: 'https://platform.kimi.com?aff=cc-switch',
    settingsConfigJson: mk({
      ANTHROPIC_BASE_URL: 'https://api.moonshot.cn/anthropic',
      ANTHROPIC_AUTH_TOKEN: '',
      ANTHROPIC_MODEL: 'kimi-k2.7-code',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'kimi-k2.7-code',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'kimi-k2.7-code',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'kimi-k2.7-code',
    }),
    category: 'cn_official',
    icon: 'kimi',
    iconColor: '#6366F1',
  },
  {
    name: 'DeepSeek',
    websiteUrl: 'https://platform.deepseek.com',
    settingsConfigJson: mk({
      ANTHROPIC_BASE_URL: 'https://api.deepseek.com/anthropic',
      ANTHROPIC_AUTH_TOKEN: '',
      ANTHROPIC_MODEL: 'deepseek-v4-pro',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'deepseek-v4-flash',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'deepseek-v4-pro',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'deepseek-v4-pro',
    }),
    category: 'cn_official',
    icon: 'deepseek',
    iconColor: '#1E88E5',
  },
  {
    name: 'OpenRouter',
    websiteUrl: 'https://openrouter.ai',
    apiKeyUrl: 'https://openrouter.ai/keys',
    settingsConfigJson: mk({
      ANTHROPIC_BASE_URL: 'https://openrouter.ai/api',
      ANTHROPIC_AUTH_TOKEN: '',
      ANTHROPIC_MODEL: 'anthropic/claude-sonnet-5',
      ANTHROPIC_DEFAULT_HAIKU_MODEL: 'anthropic/claude-haiku-4.5',
      ANTHROPIC_DEFAULT_SONNET_MODEL: 'anthropic/claude-sonnet-5',
      ANTHROPIC_DEFAULT_OPUS_MODEL: 'anthropic/claude-opus-4.8',
    }),
    category: 'aggregator',
    icon: 'openrouter',
    iconColor: '#6566F1',
  },
];
