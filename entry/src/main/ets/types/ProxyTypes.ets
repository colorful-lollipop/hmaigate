/**
 * 代理相关共享类型（单一数据源）
 *
 * 与 libentry.so 的 ProxyConfig/ProxyStatus/UpstreamConfig 同构。
 * ProxyConfig 仅含监听 host/port（上游代理等已移除的死字段不再保留）。
 */

/** 代理启动配置 */
export interface ProxyConfig {
  host: string;
  port: number;
}

/** 代理运行状态快照 */
export interface ProxyStatus {
  isRunning: boolean;
  host: string;
  port: number;
  totalRequests: number;
  blockedRequests: number;
  successRequests: number;
  failedRequests: number;
  lastError: string;
  securityEnabled: boolean; // 请求侧安全检测开关（由云端 securityPolicy.requestScanEnabled 控制）
  responseSecurityEnabled: boolean; // M4：响应侧安全检测开关（C++ getStatus 已提供）
}

/** 上游大模型厂商配置（转发目标；网关侧注入真实 Key） */
export interface UpstreamConfig {
  baseUrl: string;
  apiKey: string;
  apiKeyField: string; // 'ANTHROPIC_AUTH_TOKEN' | 'ANTHROPIC_API_KEY' | 'GEMINI_API_KEY'
  model: string;
}
