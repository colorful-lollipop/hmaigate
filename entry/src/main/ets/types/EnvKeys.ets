/**
 * EnvKeys —— 各 Agent 的 env 键名映射（types/ 层共享数据源）
 *
 * 原为 AddProviderDialog 内的局部助手 envKeysForApp，抽到 types/ 供表单层与
 * 编排层（GatewayController.providerToUpstream）共用：
 * claude 系用 ANTHROPIC_*，gemini 用 GOOGLE_GEMINI_BASE_URL / GEMINI_MODEL / GEMINI_API_KEY，
 * opencode 走 OpenAI 兼容 env 约定（OPENAI_*），codex 的 settingsConfig 是
 * {auth,config(TOML)} 形态而非 env，这里的键名是逻辑名（实际解析见
 * Provider.ets 的 getCodexApiKey / getCodexConfigText / tomlStringValue）。
 */
import { AppId } from './App';

/** 单个 Agent 在 settingsConfigJson 的 env 中使用的键名集合 */
export interface EnvKeySet {
  baseUrlKey: string;
  modelKey: string;
  apiKeyField: string;
}

/** 按 Agent 返回 env 键名；未知 Agent 走 claude 系兜底 */
export function envKeysForApp(app: AppId): EnvKeySet {
  if (app === 'gemini') {
    return { baseUrlKey: 'GOOGLE_GEMINI_BASE_URL', modelKey: 'GEMINI_MODEL', apiKeyField: 'GEMINI_API_KEY' };
  }
  if (app === 'opencode') {
    // OpenCode 预设统一用 OpenAI 兼容 env 形态：{"env":{"OPENAI_BASE_URL":...,"OPENAI_API_KEY":...,"OPENAI_MODEL":...}}
    return { baseUrlKey: 'OPENAI_BASE_URL', modelKey: 'OPENAI_MODEL', apiKeyField: 'OPENAI_API_KEY' };
  }
  if (app === 'codex') {
    // Codex 形态非 env（{"auth":{"OPENAI_API_KEY":...},"config":"<TOML>"}）；
    // baseUrl/model 的逻辑键名指向 config TOML 内的字段，解析不走 getEnvValue
    return { baseUrlKey: 'config.base_url', modelKey: 'config.model', apiKeyField: 'OPENAI_API_KEY' };
  }
  return { baseUrlKey: 'ANTHROPIC_BASE_URL', modelKey: 'ANTHROPIC_MODEL', apiKeyField: 'ANTHROPIC_AUTH_TOKEN' };
}
