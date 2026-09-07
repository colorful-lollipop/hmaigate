/**
 * Codex 预设供应商配置模板 —— 移植自 cc-switch src/config/codexProviderPresets.ts
 *
 * Codex 供应商由两部分构成：
 *   - auth:  写入 ~/.codex/auth.json（{ OPENAI_API_KEY }）
 *   - config: 写入 ~/.codex/config.toml（TOML 字符串）
 * 本移植将其合并为 settingsConfigJson = {"auth":{...},"config":"..."}。
 */
import { ProviderPreset } from '../types/Preset';

/** Codex auth.json 结构（对应 ~/.codex/auth.json） */
interface OpenAIAuth {
  OPENAI_API_KEY?: string;
}

/** Codex settingsConfig 结构：{ auth, config } */
interface CodexSettings {
  auth: OpenAIAuth;
  config: string;
}

/** 生成第三方供应商的 auth（对应 cc-switch generateThirdPartyAuth） */
function thirdPartyAuth(apiKey: string): OpenAIAuth {
  return { OPENAI_API_KEY: apiKey ? apiKey : '' };
}

/** TOML 字符串字面量（对应 cc-switch 中的 tomlString = JSON.stringify） */
function tomlString(value: string): string {
  return JSON.stringify(value);
}

/** 生成第三方供应商的 config.toml（对应 cc-switch generateThirdPartyConfig） */
export function generateThirdPartyConfig(
  providerName: string,
  baseUrl: string,
  modelName: string = 'gpt-5.5',
): string {
  return 'model_provider = "custom"\n' +
    'model = ' + tomlString(modelName) + '\n' +
    'model_reasoning_effort = "high"\n' +
    'disable_response_storage = true\n\n' +
    '[model_providers.custom]\n' +
    'name = ' + tomlString(providerName) + '\n' +
    'base_url = ' + tomlString(baseUrl) + '\n' +
    'wire_api = "responses"\n' +
    'requires_openai_auth = true';
}

/** 构造 Codex settingsConfig JSON */
function codex(providerName: string, baseUrl: string, modelName: string = 'gpt-5.5'): string {
  const cfg: CodexSettings = {
    auth: thirdPartyAuth(''),
    config: generateThirdPartyConfig(providerName, baseUrl, modelName),
  };
  return JSON.stringify(cfg);
}

/** 构造空 auth 的 Codex settingsConfig（用于官方预设） */
function codexEmpty(): string {
  const cfg: CodexSettings = { auth: {}, config: '' };
  return JSON.stringify(cfg);
}

export const codexProviderPresets: ProviderPreset[] = [
  {
    name: 'OpenAI Official',
    websiteUrl: 'https://chatgpt.com/codex',
    isOfficial: true,
    category: 'official',
    settingsConfigJson: codexEmpty(),
    theme: { icon: 'codex', backgroundColor: '#1F2937', textColor: '#FFFFFF' },
    icon: 'openai',
    iconColor: '#00A67E',
  },
  {
    name: 'Shengsuanyun',
    nameKey: 'providerForm.presets.shengsuanyun',
    websiteUrl: 'https://www.shengsuanyun.com',
    apiKeyUrl: 'https://www.shengsuanyun.com',
    settingsConfigJson: codex('shengsuanyun', 'https://router.shengsuanyun.com/api/v1', 'openai/gpt-5.5'),
    category: 'aggregator',
    isPartner: true,
    icon: 'shengsuanyun',
  },
  {
    name: 'PatewayAI',
    websiteUrl: 'https://pateway.ai',
    apiKeyUrl: 'https://pateway.ai/#/',
    settingsConfigJson: codex('patewayai', 'https://api.pateway.ai/v1', 'gpt-5.5'),
    category: 'third_party',
    endpointCandidates: ['https://api.pateway.ai/v1'],
    isPartner: true,
    icon: 'pateway',
  },
  {
    name: '火山Agentplan',
    websiteUrl: 'https://www.volcengine.com/product/ark',
    apiKeyUrl: 'https://www.volcengine.com/activity/codingplan',
    settingsConfigJson: codex('ark_agentplan', 'https://ark.cn-beijing.volces.com/api/coding/v3', 'ark-code-latest'),
    endpointCandidates: ['https://ark.cn-beijing.volces.com/api/coding/v3'],
    apiFormat: 'openai_chat',
    category: 'cn_official',
    isPartner: true,
    icon: 'huoshan',
    iconColor: '#3370FF',
  },
  {
    name: 'DouBaoSeed',
    websiteUrl: 'https://www.volcengine.com/product/doubao',
    apiKeyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D',
    settingsConfigJson: codex('doubaoseed', 'https://ark.cn-beijing.volces.com/api/v3', 'doubao-seed-2-1-pro-260628'),
    endpointCandidates: ['https://ark.cn-beijing.volces.com/api/v3'],
    apiFormat: 'openai_responses',
    category: 'cn_official',
    isPartner: true,
    icon: 'doubao',
    iconColor: '#3370FF',
  },
  {
    name: 'CCSub',
    websiteUrl: 'https://www.ccsub.net',
    apiKeyUrl: 'https://www.ccsub.net/register',
    settingsConfigJson: codex('ccsub', 'https://www.ccsub.net/v1', 'gpt-5.5'),
    category: 'aggregator',
    isPartner: true,
    icon: 'ccsub',
  },
];
