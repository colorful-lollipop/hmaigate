/**
 * 安全服务 —— 安全规则的展示/开关/自定义配置（薄封装 libentry.so）。
 * 类型定义见 types/SecurityTypes。请求体检测由 C++ 转发器在转发路径上直接调用，
 * ArkTS 侧无需再暴露 detectRequest。
 */
import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { SecurityRule } from '../types/SecurityTypes';
import { parseStringArray } from '../types/Json';

const DOMAIN = 0x0000;
const TAG = 'SecurityService';

export class SecurityService {
  private static rules: Map<string, SecurityRule> = new Map();

  /** 初始化默认规则的展示名（与 C++ SecurityDetector 注册的 ruleId 对应） */
  private static initializeRules(): void {
    SecurityService.rules.set('password_leak',
      { id: 'password_leak', name: '密码泄露检测', enabled: true, hitCount: 0, customKeywords: [], customPatterns: [] });
    SecurityService.rules.set('malicious_tool_use',
      { id: 'malicious_tool_use', name: '恶意工具调用检测', enabled: true, hitCount: 0, customKeywords: [], customPatterns: [] });
    SecurityService.rules.set('prompt_injection',
      { id: 'prompt_injection', name: '提示注入检测', enabled: true, hitCount: 0, customKeywords: [], customPatterns: [] });
  }

  /**
   * 解析 M4 规则详情 JSON（每条含 id/name/enabled/hitCount/customKeywords/customPatterns）。
   * 展示名优先取 native 返回值，缺省回退本地映射表。
   */
  private static parseRulesJson(raw: string): SecurityRule[] {
    const out: SecurityRule[] = [];
    const arr: ESObject = JSON.parse(raw);
    if (!Array.isArray(arr)) {
      return out;
    }
    const items: ESObject[] = arr as ESObject[];
    for (let i = 0; i < items.length; i++) {
      const item: ESObject = items[i];
      if (typeof item !== 'object' || item === null) {
        continue;
      }
      const id: ESObject = item['id'];
      if (typeof id !== 'string') {
        continue;
      }
      const ruleId: string = id as string;
      const local: SecurityRule | undefined = SecurityService.rules.get(ruleId);
      const name: ESObject = item['name'];
      const enabled: ESObject = item['enabled'];
      const hitCount: ESObject = item['hitCount'];
      out.push({
        id: ruleId,
        name: typeof name === 'string' && (name as string).length > 0
          ? name as string
          : (local !== undefined ? local.name : ruleId),
        enabled: typeof enabled === 'boolean'
          ? enabled as boolean
          : (local !== undefined ? local.enabled : true),
        hitCount: typeof hitCount === 'number' ? hitCount as number : 0,
        customKeywords: parseStringArray(item['customKeywords']),
        customPatterns: parseStringArray(item['customPatterns']),
      });
    }
    return out;
  }

  /**
   * 获取安全规则列表（按 native 注册的 ruleId 过滤）。
   * M4 起 C++ 返回规则详情 JSON 串（含 hitCount/customKeywords/customPatterns）。
   */
  static getRules(): SecurityRule[] {
    if (SecurityService.rules.size === 0) {
      SecurityService.initializeRules();
    }
    try {
      return SecurityService.parseRulesJson(libentry.getSecurityRules());
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get rules: ${JSON.stringify(error)}`);
      return Array.from(SecurityService.rules.values());
    }
  }

  /** 启用/禁用某条规则 */
  static setRuleEnabled(ruleId: string, enabled: boolean): void {
    try {
      libentry.setRuleEnabled(ruleId, enabled);
      const rule = SecurityService.rules.get(ruleId);
      if (rule) {
        rule.enabled = enabled;
        SecurityService.rules.set(ruleId, rule);
      }
      hilog.info(DOMAIN, TAG, `Rule ${ruleId} ${enabled ? 'enabled' : 'disabled'}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set rule enabled: ${JSON.stringify(error)}`);
    }
  }

  /**
   * M4：更新规则自定义配置。configJson 形态
   * {"addKeywords":[...],"addPatterns":[...],"removeKeywords":[...],"removePatterns":[...]}（键均可选）。
   * 返回 false 表示 native 拒绝（未知 ruleId / 非法 JSON）。
   */
  static updateRuleConfig(ruleId: string, configJson: string): boolean {
    try {
      const ok: boolean = libentry.updateRuleConfig(ruleId, configJson);
      hilog.info(DOMAIN, TAG, `updateRuleConfig ${ruleId}: ${ok}`);
      return ok;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update rule config: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /** M4：响应侧安全检测开关（即时生效） */
  static setResponseSecurityEnabled(enabled: boolean): void {
    try {
      libentry.setResponseSecurityEnabled(enabled);
      hilog.info(DOMAIN, TAG, `response security ${enabled ? 'enabled' : 'disabled'}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set response security: ${JSON.stringify(error)}`);
    }
  }

  /** 请求侧安全检测开关（云端 securityPolicy.requestScanEnabled 可运行中热更新）。 */
  static setSecurityEnabled(enabled: boolean): void {
    try {
      libentry.setSecurityEnabled(enabled);
      hilog.info(DOMAIN, TAG, `request security ${enabled ? 'enabled' : 'disabled'}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set request security: ${JSON.stringify(error)}`);
    }
  }
}
