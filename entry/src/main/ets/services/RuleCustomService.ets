/**
 * RuleCustomService —— M4 安全规则自定义词条的编排（R3 从 GatewayController 下沉）
 *
 * 职责：规则自定义关键词/正则的增删、ruleCustomJson 的解析/序列化与启动回放。
 * C++ 安全引擎是运行时真相（SecurityService.updateRuleConfig 即时下发）；
 * SettingsRepository.ruleCustomJson 只是进程重启后的回放源——先下发 C++，
 * 成功后才改持久化。GatewayController 保留同名公开入口做转发，UI 调用点不变。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RuleCustomEntry } from '../types/SecurityTypes';
import { jsonStr, strArrayJson, parseStringArray } from '../types/Json';
import { SettingsRepository } from '../repository/SettingsRepository';
import { SecurityService } from './SecurityService';

const DOMAIN = 0x0000;
const TAG = 'RuleCustomService';

export class RuleCustomService {
  /**
   * M4：启动回放 —— 把 ruleCustomJson 里持久化的自定义词条逐规则以 add 语义
   * 回放到 C++ 安全引擎，并下发响应检测开关。
   */
  static applyRuleConfigs(): void {
    SecurityService.setSecurityEnabled(SettingsRepository.getSecurityEnabled());
    SecurityService.setResponseSecurityEnabled(SettingsRepository.getResponseSecurityEnabled());
    const map: Map<string, RuleCustomEntry> = RuleCustomService.parseRuleCustomMap();
    map.forEach((entry: RuleCustomEntry, ruleId: string) => {
      const configJson: string = '{"addKeywords":' + strArrayJson(entry.keywords) +
        ',"addPatterns":' + strArrayJson(entry.patterns) + '}';
      SecurityService.updateRuleConfig(ruleId, configJson);
    });
  }

  /** 读取某规则的自定义词条（供自定义对话框展示；数据来自持久化回放源） */
  static getRuleCustomEntry(ruleId: string): RuleCustomEntry {
    const entry: RuleCustomEntry | undefined = RuleCustomService.parseRuleCustomMap().get(ruleId);
    if (entry !== undefined) {
      return entry;
    }
    return { keywords: [], patterns: [] };
  }

  /** 添加自定义关键词；返回空串 = 成功，否则为错误提示文案 */
  static async addKeyword(ruleId: string, word: string): Promise<string> {
    return RuleCustomService.addCustomToken(ruleId, word, false);
  }

  /** 添加自定义正则；返回空串 = 成功 */
  static async addPattern(ruleId: string, pattern: string): Promise<string> {
    return RuleCustomService.addCustomToken(ruleId, pattern, true);
  }

  /** 删除自定义关键词；返回空串 = 成功 */
  static async removeKeyword(ruleId: string, word: string): Promise<string> {
    return RuleCustomService.removeCustomToken(ruleId, word, false);
  }

  /** 删除自定义正则；返回空串 = 成功 */
  static async removePattern(ruleId: string, pattern: string): Promise<string> {
    return RuleCustomService.removeCustomToken(ruleId, pattern, true);
  }

  /**
   * 用一套已校验的云端词条替换本地回放源，并立即更新原生检测器。先移除旧值，
   * 再添加新值，确保云端下线词条不会在运行中残留。
   */
  static async replaceRuleCustomJson(nextJson: string): Promise<boolean> {
    const current: Map<string, RuleCustomEntry> = RuleCustomService.parseRuleCustomMap();
    const next: Map<string, RuleCustomEntry> = RuleCustomService.parseRuleCustomJson(nextJson);
    const ruleIds: Map<string, boolean> = new Map<string, boolean>();
    current.forEach((entry: RuleCustomEntry, ruleId: string) => ruleIds.set(ruleId, true));
    next.forEach((entry: RuleCustomEntry, ruleId: string) => ruleIds.set(ruleId, true));
    let applied: boolean = true;
    ruleIds.forEach((present: boolean, ruleId: string) => {
      if (!applied) {
        return;
      }
      const oldEntry: RuleCustomEntry | undefined = current.get(ruleId);
      const newEntry: RuleCustomEntry | undefined = next.get(ruleId);
      const oldKeywords: string[] = oldEntry !== undefined ? oldEntry.keywords : [];
      const oldPatterns: string[] = oldEntry !== undefined ? oldEntry.patterns : [];
      const newKeywords: string[] = newEntry !== undefined ? newEntry.keywords : [];
      const newPatterns: string[] = newEntry !== undefined ? newEntry.patterns : [];
      const removeJson: string = '{"removeKeywords":' + strArrayJson(oldKeywords) +
        ',"removePatterns":' + strArrayJson(oldPatterns) + '}';
      const addJson: string = '{"addKeywords":' + strArrayJson(newKeywords) +
        ',"addPatterns":' + strArrayJson(newPatterns) + '}';
      if ((oldKeywords.length > 0 || oldPatterns.length > 0) &&
        !SecurityService.updateRuleConfig(ruleId, removeJson)) {
        applied = false;
        return;
      }
      if ((newKeywords.length > 0 || newPatterns.length > 0) &&
        !SecurityService.updateRuleConfig(ruleId, addJson)) {
        applied = false;
      }
    });
    if (!applied) {
      return false;
    }
    await SettingsRepository.setRuleCustomJson(RuleCustomService.ruleCustomMapToJson(next));
    return true;
  }

  /** 增词条公共路径：先下发 C++（运行时真相），成功后才更新 ruleCustomJson 持久化（重启回放源） */
  private static async addCustomToken(ruleId: string, token: string, isPattern: boolean): Promise<string> {
    const t: string = token.trim();
    if (t.length === 0) {
      return '内容不能为空';
    }
    const map: Map<string, RuleCustomEntry> = RuleCustomService.parseRuleCustomMap();
    let entry: RuleCustomEntry | undefined = map.get(ruleId);
    if (entry === undefined) {
      entry = { keywords: [], patterns: [] };
    }
    const list: string[] = isPattern ? entry.patterns : entry.keywords;
    if (list.indexOf(t) >= 0) {
      return isPattern ? '该正则已存在' : '该关键词已存在';
    }
    const field: string = isPattern ? 'addPatterns' : 'addKeywords';
    const ok: boolean = SecurityService.updateRuleConfig(ruleId, '{"' + field + '":[' + jsonStr(t) + ']}');
    if (!ok) {
      return '下发到安全引擎失败';
    }
    list.push(t);
    map.set(ruleId, entry);
    await SettingsRepository.setRuleCustomJson(RuleCustomService.ruleCustomMapToJson(map));
    return '';
  }

  /** 删词条公共路径：同样先下发 C++，成功后才改持久化 */
  private static async removeCustomToken(ruleId: string, token: string, isPattern: boolean): Promise<string> {
    const map: Map<string, RuleCustomEntry> = RuleCustomService.parseRuleCustomMap();
    const entry: RuleCustomEntry | undefined = map.get(ruleId);
    if (entry === undefined) {
      return '该规则没有自定义词条';
    }
    const list: string[] = isPattern ? entry.patterns : entry.keywords;
    if (list.indexOf(token) < 0) {
      return '词条不存在';
    }
    const field: string = isPattern ? 'removePatterns' : 'removeKeywords';
    const ok: boolean = SecurityService.updateRuleConfig(ruleId, '{"' + field + '":[' + jsonStr(token) + ']}');
    if (!ok) {
      return '下发到安全引擎失败';
    }
    const kept: string[] = [];
    for (const item of list) {
      if (item !== token) {
        kept.push(item);
      }
    }
    if (isPattern) {
      entry.patterns = kept;
    } else {
      entry.keywords = kept;
    }
    await SettingsRepository.setRuleCustomJson(RuleCustomService.ruleCustomMapToJson(map));
    return '';
  }

  /** 解析 ruleCustomJson 为 Map（宽容兜底：非法 JSON / 字段缺失一律回退空） */
  private static parseRuleCustomMap(): Map<string, RuleCustomEntry> {
    const raw: string = SettingsRepository.getRuleCustomJson();
    return RuleCustomService.parseRuleCustomJson(raw);
  }

  /** 与 preferences 读取共用的宽容解析器，供云端完整替换前预校验。 */
  private static parseRuleCustomJson(raw: string): Map<string, RuleCustomEntry> {
    const map: Map<string, RuleCustomEntry> = new Map();
    if (raw.length === 0) {
      return map;
    }
    try {
      const obj: ESObject = JSON.parse(raw);
      if (typeof obj !== 'object' || obj === null) {
        return map;
      }
      const ruleIds: string[] = Object.keys(obj as object);
      for (const ruleId of ruleIds) {
        const item: ESObject = obj[ruleId];
        if (typeof item !== 'object' || item === null) {
          continue;
        }
        map.set(ruleId, {
          keywords: parseStringArray(item['keywords']),
          patterns: parseStringArray(item['patterns']),
        });
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `ruleCustomJson parse failed: ${JSON.stringify(e)}`);
    }
    return map;
  }

  /** Map → ruleCustomJson（字符串拼接骨架 + 字符串字段逐个 jsonStr 转义） */
  private static ruleCustomMapToJson(map: Map<string, RuleCustomEntry>): string {
    const parts: string[] = [];
    map.forEach((entry: RuleCustomEntry, ruleId: string) => {
      parts.push(jsonStr(ruleId) + ':{"keywords":' + strArrayJson(entry.keywords) +
        ',"patterns":' + strArrayJson(entry.patterns) + '}');
    });
    return '{' + parts.join(',') + '}';
  }
}
