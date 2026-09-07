/**
 * OpenCode 预设供应商配置模板（多渠道管理新增）
 *
 * OpenCode 渠道统一走 OpenAI 兼容 env 形态：
 *   settingsConfigJson = {"env":{"OPENAI_BASE_URL":...,"OPENAI_API_KEY":...,"OPENAI_MODEL":...}}
 * 键名约定见 types/EnvKeys.ets 的 envKeysForApp('opencode')。
 *
 * 端点纪律：只允许复用仓库现有预设文件（ClaudePresets/CodexPresets/GeminiPresets）
 * 里已出现的真实端点，禁止编造 URL。以下端点全部来自 CodexPresets / ClaudePresets
 * 的 OpenAI 兼容端点（/v1 系与聚合站）。
 */
import { ProviderPreset } from '../types/Preset';

/** OpenCode env 字段（OpenAI 兼容约定） */
interface OpenCodeEnv {
  OPENAI_BASE_URL?: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
}

/** OpenCode settingsConfig 结构：{ env } */
interface OpenCodeSettings {
  env: OpenCodeEnv;
}

function mk(env: OpenCodeEnv): string {
  const cfg: OpenCodeSettings = { env: env };
  return JSON.stringify(cfg);
}

export const openCodeProviderPresets: ProviderPreset[] = [
  {
    name: 'Shengsuanyun',
    nameKey: 'providerForm.presets.shengsuanyun',
    websiteUrl: 'https://www.shengsuanyun.com',
    apiKeyUrl: 'https://www.shengsuanyun.com',
    // 端点复用 CodexPresets 的 Shengsuanyun OpenAI 兼容端点
    settingsConfigJson: mk({
      OPENAI_BASE_URL: 'https://router.shengsuanyun.com/api/v1',
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'openai/gpt-5.5',
    }),
    category: 'aggregator',
    isPartner: true,
    icon: 'shengsuanyun',
  },
  {
    name: 'PatewayAI',
    websiteUrl: 'https://pateway.ai',
    apiKeyUrl: 'https://pateway.ai/#/',
    // 端点复用 CodexPresets 的 PatewayAI 端点
    settingsConfigJson: mk({
      OPENAI_BASE_URL: 'https://api.pateway.ai/v1',
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'gpt-5.5',
    }),
    category: 'third_party',
    endpointCandidates: ['https://api.pateway.ai/v1'],
    isPartner: true,
    icon: 'pateway',
  },
  {
    name: 'DouBaoSeed',
    websiteUrl: 'https://www.volcengine.com/product/doubao',
    apiKeyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D',
    // 端点复用 CodexPresets 的火山方舟 OpenAI 兼容端点
    settingsConfigJson: mk({
      OPENAI_BASE_URL: 'https://ark.cn-beijing.volces.com/api/v3',
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'doubao-seed-2-1-pro-260628',
    }),
    endpointCandidates: ['https://ark.cn-beijing.volces.com/api/v3'],
    category: 'cn_official',
    isPartner: true,
    icon: 'doubao',
    iconColor: '#3370FF',
  },
  {
    name: 'CCSub',
    websiteUrl: 'https://www.ccsub.net',
    apiKeyUrl: 'https://www.ccsub.net/register',
    // 端点复用 CodexPresets 的 CCSub 端点
    settingsConfigJson: mk({
      OPENAI_BASE_URL: 'https://www.ccsub.net/v1',
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'gpt-5.5',
    }),
    category: 'aggregator',
    isPartner: true,
    icon: 'ccsub',
  },
  {
    name: 'OpenRouter',
    websiteUrl: 'https://openrouter.ai',
    apiKeyUrl: 'https://openrouter.ai/keys',
    // 端点复用 ClaudePresets 的 OpenRouter 端点
    settingsConfigJson: mk({
      OPENAI_BASE_URL: 'https://openrouter.ai/api',
      OPENAI_API_KEY: '',
      OPENAI_MODEL: 'anthropic/claude-sonnet-5',
    }),
    category: 'aggregator',
    icon: 'openrouter',
    iconColor: '#6566F1',
  },
];
