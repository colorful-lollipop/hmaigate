/**
 * Provider 数据模型 —— 移植自 cc-switch src/types.ts
 *
 * 说明：cc-switch 的 Provider.settingsConfig 是 Record<string, any>，
 * 但表单层 (providerSchema) 实际以 JSON 字符串校验/编辑。
 * 本移植沿用“JSON 字符串”承载 settingsConfig，规避 ArkTS 对任意对象字面量
 * 与索引签名的限制，同时保留 cc-switch 的 JSON 编辑器交互语义。
 */

/** 供应商分类（对应 cc-switch ProviderCategory） */
export type ProviderCategory =
  | 'official'
  | 'cn_official'
  | 'cloud_provider'
  | 'aggregator'
  | 'third_party'
  | 'custom'
  | 'omo'
  | 'omo-slim';

/** Claude 认证字段名 */
export type ClaudeApiKeyField = 'ANTHROPIC_AUTH_TOKEN' | 'ANTHROPIC_API_KEY';

/**
 * 单个供应商（对应 cc-switch Provider）
 * settingsConfigJson: 对应 cc-switch Provider.settingsConfig 序列化后的 JSON 字符串，
 * 形如 {"env":{"ANTHROPIC_BASE_URL":"...","ANTHROPIC_AUTH_TOKEN":"..."}}
 */
export interface Provider {
  id: string;
  name: string;
  settingsConfigJson: string;
  websiteUrl?: string;
  category?: ProviderCategory;
  createdAt?: number;
  sortIndex?: number;
  notes?: string;
  isPartner?: boolean;
  /** 图标名称（如 'openai' / 'anthropic'） */
  icon?: string;
  /** 图标颜色 Hex */
  iconColor?: string;
  /** 是否加入故障转移队列 */
  inFailoverQueue?: boolean;
}

/** 单个应用的配置（对应 cc-switch AppConfig） */
export interface AppConfig {
  providers: Record<string, Provider>;
  current: string;
}

export function emptyAppConfig(): AppConfig {
  return { providers: {}, current: '' };
}

// ---------------------------------------------------------------------------
// settingsConfig JSON 辅助函数（对应 cc-switch 中对 settings.json env 的读写）
// ---------------------------------------------------------------------------

/** 安全解析 settingsConfigJson 为对象；失败返回空对象 */
export function parseSettingsObject(json: string): Record<string, Object> {
  if (!json) {
    return {};
  }
  try {
    const obj: ESObject = JSON.parse(json);
    if (typeof obj === 'object' && obj !== null) {
      return obj as Record<string, Object>;
    }
  } catch (e) {
    // ignore
  }
  return {} as Record<string, Object>;
}

/** 取 env 子表（Claude 形态）；不存在则返回空 map */
export function getEnvMap(json: string): Record<string, string> {
  const obj = parseSettingsObject(json);
  const envVal: ESObject = obj['env'];
  if (envVal !== undefined && envVal !== null && typeof envVal === 'object') {
    return envVal as Record<string, string>;
  }
  return {} as Record<string, string>;
}

/** 从 settingsConfigJson 的 env 中读取某个键值 */
export function getEnvValue(json: string, key: string): string {
  return getEnvMap(json)[key] ?? '';
}

/**
 * 向 settingsConfigJson 的 env 写入键值并返回新的 JSON 字符串。
 * 保留 env 之外的其他顶层字段。
 */
export function setEnvValue(json: string, key: string, value: string): string {
  const obj = parseSettingsObject(json);
  const envRaw: ESObject = obj['env'];
  const env: Record<string, string> =
    (envRaw !== undefined && envRaw !== null && typeof envRaw === 'object')
      ? envRaw as Record<string, string>
      : {};
  env[key] = value;
  obj['env'] = env;
  return JSON.stringify(obj);
}

/** 从 settingsConfigJson 推断 base url（用于表单回填 / 列表副标题 / 搜索匹配）。
 *  依次尝试：claude env → opencode OpenAI 兼容 env → codex config TOML 的 base_url。 */
export function inferBaseUrl(json: string): string {
  const env = getEnvMap(json);
  const anthropicUrl: string = env['ANTHROPIC_BASE_URL'] ?? '';
  if (anthropicUrl !== '') {
    return anthropicUrl;
  }
  const openaiUrl: string = env['OPENAI_BASE_URL'] ?? '';
  if (openaiUrl !== '') {
    return openaiUrl;
  }
  return tomlStringValue(getCodexConfigText(json), 'base_url');
}

/** 从 settingsConfigJson 推断主模型（用于表单回填） */
export function inferModel(json: string): string {
  const env = getEnvMap(json);
  return env['ANTHROPIC_MODEL'] ?? '';
}

/** 判断认证字段（cc-switch apiKeyField，默认 ANTHROPIC_AUTH_TOKEN） */
export function inferApiKeyField(json: string): ClaudeApiKeyField {
  const env = getEnvMap(json);
  if (env['ANTHROPIC_API_KEY'] !== undefined && env['ANTHROPIC_API_KEY'] !== '') {
    return 'ANTHROPIC_API_KEY';
  }
  return 'ANTHROPIC_AUTH_TOKEN';
}

// ---------------------------------------------------------------------------
// Codex 形态（{"auth":{"OPENAI_API_KEY":...},"config":"<TOML>"}）读取助手
// ---------------------------------------------------------------------------

/** 取 codex 形态 settingsConfigJson 的 auth.OPENAI_API_KEY；非 codex 形态/缺失返回空串 */
export function getCodexApiKey(json: string): string {
  try {
    const obj: ESObject = JSON.parse(json);
    const auth: ESObject = obj['auth'];
    if (auth !== undefined && auth !== null && typeof auth === 'object') {
      const k: ESObject = (auth as Record<string, string>)['OPENAI_API_KEY'];
      return typeof k === 'string' ? k as string : '';
    }
  } catch (e) {
    // ignore
  }
  return '';
}

/** 取 codex 形态 settingsConfigJson 的 config（TOML 原文）；缺失返回空串 */
export function getCodexConfigText(json: string): string {
  try {
    const obj: ESObject = JSON.parse(json);
    const cfg: ESObject = obj['config'];
    return typeof cfg === 'string' ? cfg as string : '';
  } catch (e) {
    return '';
  }
}

/**
 * 从 TOML 文本提取顶层字符串字段值（`key = "value"`）。
 * 手写逐行扫描：key 后必须紧跟空白 + '='，避免 `model` 误配 `model_provider`。
 */
export function tomlStringValue(toml: string, key: string): string {
  const lines: string[] = toml.split('\n');
  for (const raw of lines) {
    const line: string = raw.trim();
    if (!line.startsWith(key)) {
      continue;
    }
    let rest: string = line.substring(key.length).trimStart();
    if (!rest.startsWith('=')) {
      continue;
    }
    rest = rest.substring(1).trim();
    if (rest.startsWith('"')) {
      const end: number = rest.indexOf('"', 1);
      return end > 0 ? rest.substring(1, end) : '';
    }
    return rest;
  }
  return '';
}
