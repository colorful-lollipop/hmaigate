/**
 * 安全检测相关共享类型（单一数据源）
 */

/** 单条安全规则的可展示状态 */
export interface SecurityRule {
  id: string;
  name: string;
  enabled: boolean;
  hitCount: number;          // M4：规则命中次数（来自 C++ 规则列表 JSON，缺省 0）
  customKeywords: string[];  // M4：用户自定义关键词（缺省空数组）
  customPatterns: string[];  // M4：用户自定义正则（缺省空数组）
}

/**
 * M4：单条规则的用户自定义词条（持久化在 SettingsRepository.ruleCustomJson，
 * 形态 {ruleId: {"keywords":[...],"patterns":[...]}}；C++ 是运行时真相，这里是重启回放源）
 */
export interface RuleCustomEntry {
  keywords: string[];
  patterns: string[];
}
