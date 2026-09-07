/**
 * libentry.so类型定义
 */
export interface ProxyConfig {
  host: string;
  port: number;
}

export interface ProxyStatus {
  isRunning: boolean;
  host: string;
  port: number;
  totalRequests: number;
  blockedRequests: number;
  successRequests: number;
  failedRequests: number;
  lastError: string;
  securityEnabled: boolean;          // 请求侧安全检测开关状态
  responseSecurityEnabled: boolean;  // M4：响应侧安全检测开关状态
}

/** 上游大模型厂商配置（转发目标） */
export interface UpstreamConfig {
  baseUrl: string;
  apiKey: string;
  apiKeyField: string;
  model: string;
}

/** M2 动态库插件条目（listPlugins 返回的 JSON 数组元素形态） */
export interface NativePluginItem {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  type: string;    // 'security' | 'transform' | 'other'
  enabled: boolean;
  source: string;  // 'builtin' | 'file'
  error: string;   // 空串 = 加载成功
}

/** M3 路由规则（setRouteRules 入参 JSON 数组的元素形态） */
export interface NativeRouteRule {
  id: string;
  name: string;
  priority: number;      // 数值大者优先；同优先级按数组顺序
  modelPrefix: string;   // "" = 不限模型（请求 model 前缀匹配）
  protocol: string;      // 'any' | 'anthropic' | 'openai' | 'gemini'
  pathPrefix: string;    // "" = 不限路径（请求 uri 前缀匹配）
  upstream: UpstreamConfig;
}

/** M4 安全规则条目（getSecurityRules 返回的 JSON 数组元素形态） */
export interface NativeSecurityRule {
  id: string;
  name: string;
  enabled: boolean;
  hitCount: number;          // 规则命中次数（运行期累计）
  customKeywords: string[];  // 用户自定义关键词（updateRuleConfig 增删）
  customPatterns: string[];  // 用户自定义正则
}

/** Password Leak Audit 状态（getPasswordLeakAuditStatus 返回的 JSON 形态） */
export interface NativePasswordLeakAuditStatus {
  enabled: boolean;
  unreadCount: number;
  todayCount: number;
  lastAlertTimeMs: number;
  droppedTasks: number;
  truncatedTasks: number;
  failedTasks: number;
}

/** Password Leak Audit 告警；不含请求正文、命中内容或密钥片段。 */
export interface NativePasswordLeakAlert {
  id: string;
  timeMs: number;
  severity: string;
  secretType: string;
  location: string;
  protocol: string;
  model: string;
  status: string;
}
