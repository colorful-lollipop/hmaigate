/**
 * libentry.so TypeScript类型定义
 */
import { ProxyConfig, ProxyStatus, UpstreamConfig } from './Types';

// Proxy Engine
export const startProxy: (config: ProxyConfig) => boolean;
export const stopProxy: () => void;
export const getProxyStatus: () => ProxyStatus;
export const setUpstream: (upstream: UpstreamConfig) => void;

// Router（M3：多协议智能路由；rulesJson 为 NativeRouteRule[] 的 JSON 串，
// 非法 JSON 返回 false 且不动旧表，空数组 "[]" = 关闭路由）
export const setRouteRules: (rulesJson: string) => boolean;

// Security Detector
// M4 起返回规则列表 JSON 字符串（元素形态见 Types.d.ts 的 NativeSecurityRule）
export const getSecurityRules: () => string;
export const setRuleEnabled: (ruleId: string, enabled: boolean) => void;
// M4：增删规则的用户自定义词条；configJson 形态
// {"addKeywords":[],"addPatterns":[],"removeKeywords":[],"removePatterns":[]}（四键均可选），
// 未知 ruleId 或非法 JSON 返回 false
export const updateRuleConfig: (ruleId: string, configJson: string) => boolean;
// 请求侧安全检测开关（getProxyStatus 的 securityEnabled 反映当前状态）
export const setSecurityEnabled: (enabled: boolean) => void;
// M4：响应侧安全检测开关（getProxyStatus 的 responseSecurityEnabled 反映当前状态）
export const setResponseSecurityEnabled: (enabled: boolean) => void;

// Plugin Manager（M2：动态库插件）
export const loadPlugins: (dir: string) => Promise<number>;
export const listPlugins: () => string;
export const setPluginEnabled: (id: string, enabled: boolean) => boolean;

// Password Leak Audit（异步审计、只返回脱敏元数据）
export const setPasswordLeakAuditEnabled: (enabled: boolean) => boolean;
export const getPasswordLeakAuditStatus: () => string;
export const getPasswordLeakAlerts: (offset: number, limit: number) => string;
export const markPasswordLeakAlertsRead: (idsJson: string) => number;
export const clearPasswordLeakAlerts: () => void;
