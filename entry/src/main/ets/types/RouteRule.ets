/**
 * RouteRule 数据模型 —— M3 智能路由规则
 *
 * 匹配语义（C++ 侧实现）：modelPrefix 空串 = 任意模型；protocol 限定请求协议；
 * pathPrefix 空串 = 任意路径。priority 大者优先，同优先级按数组顺序。
 * 空规则数组 = 关闭路由，全部请求回退默认上游（当前供应商）。
 *
 * ArkTS 层规则只存 providerId 引用（不含密钥，密钥不出 preferences）；
 * 推送给 C++ 前由 GatewayController.applyRouteRules 把 providerId 解析成
 * Provider 并展开为含 baseUrl/apiKey/apiKeyField/model 的 upstream 对象。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { jsonStr } from './Json';

const DOMAIN = 0x0000;
const TAG = 'RouteRule';

/** 路由协议限定（any = 不区分协议） */
export type RouteProtocol = 'any' | 'anthropic' | 'openai' | 'gemini';

/** 全部可选协议（供表单渲染，顺序即展示顺序） */
export const ROUTE_PROTOCOLS: RouteProtocol[] = ['any', 'anthropic', 'openai', 'gemini'];

/** priority 合法范围（大者优先） */
export const PRIORITY_MIN: number = 0;
export const PRIORITY_MAX: number = 9999;

/** 单条路由规则 */
export interface RouteRule {
  id: string;
  name: string;
  priority: number;
  modelPrefix: string;   // 模型名前缀，空串 = 任意
  protocol: RouteProtocol;
  pathPrefix: string;    // 请求路径前缀，空串 = 任意
  providerId: string;    // 引用 Provider.id，规则本体不含密钥
}

/** 默认值工厂（新增表单初值） */
export function defaultRouteRule(): RouteRule {
  return {
    id: '',
    name: '',
    priority: 10,
    modelPrefix: '',
    protocol: 'any',
    pathPrefix: '',
    providerId: '',
  };
}

/** 生成规则 id（与 ProviderRepository.genId 同款形态） */
export function genRouteRuleId(): string {
  return 'r_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 1000000).toString(36);
}

/** 表单校验；返回错误文案，空串 = 合法 */
export function validateRouteRule(rule: RouteRule): string {
  if (!rule.name.trim()) {
    return '请填写规则名称';
  }
  if (!Number.isInteger(rule.priority) || rule.priority < PRIORITY_MIN || rule.priority > PRIORITY_MAX) {
    return `优先级须为 ${PRIORITY_MIN}-${PRIORITY_MAX} 的整数`;
  }
  if (!rule.providerId) {
    return '请选择目标供应商';
  }
  return '';
}

/**
 * 解析持久化的 routeRulesJson 为规则数组。
 * 顶层非数组 / 非法条目一律跳过（非法条目送默认值再逐字段覆盖），不抛异常。
 */
export function parseRouteRules(json: string): RouteRule[] {
  const rules: RouteRule[] = [];
  if (!json) {
    return rules;
  }
  try {
    const arr: ESObject = JSON.parse(json);
    if (!Array.isArray(arr)) {
      return rules;
    }
    const list: ESObject[] = arr as ESObject[];
    for (let i = 0; i < list.length; i++) {
      const raw: ESObject = list[i];
      if (typeof raw !== 'object' || raw === null) {
        continue;
      }
      const rule: RouteRule = defaultRouteRule();
      const id: ESObject = raw['id'];
      if (typeof id === 'string') {
        rule.id = id as string;
      }
      const name: ESObject = raw['name'];
      if (typeof name === 'string') {
        rule.name = name as string;
      }
      const priority: ESObject = raw['priority'];
      if (typeof priority === 'number') {
        rule.priority = priority as number;
      }
      const modelPrefix: ESObject = raw['modelPrefix'];
      if (typeof modelPrefix === 'string') {
        rule.modelPrefix = modelPrefix as string;
      }
      const protocol: ESObject = raw['protocol'];
      if (typeof protocol === 'string' && ROUTE_PROTOCOLS.indexOf(protocol as RouteProtocol) >= 0) {
        rule.protocol = protocol as RouteProtocol;
      }
      const pathPrefix: ESObject = raw['pathPrefix'];
      if (typeof pathPrefix === 'string') {
        rule.pathPrefix = pathPrefix as string;
      }
      const providerId: ESObject = raw['providerId'];
      if (typeof providerId === 'string') {
        rule.providerId = providerId as string;
      }
      rules.push(rule);
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, `parseRouteRules failed: ${JSON.stringify(e)}`);
  }
  return rules;
}

/**
 * 序列化规则数组为持久化 JSON（ArkTS 层形态，含 providerId 引用）。
 * 严格模式不许 JSON.stringify 对象字面量：这里字符串拼接骨架，
 * 字符串字段逐个 JSON.stringify 做转义（同 AddProviderDialog.buildCodexJson）。
 */
export function routeRulesToJson(rules: RouteRule[]): string {
  const parts: string[] = [];
  for (const r of rules) {
    parts.push(
      '{"id":' + jsonStr(r.id) +
      ',"name":' + jsonStr(r.name) +
      ',"priority":' + r.priority.toString() +
      ',"modelPrefix":' + jsonStr(r.modelPrefix) +
      ',"protocol":' + jsonStr(r.protocol) +
      ',"pathPrefix":' + jsonStr(r.pathPrefix) +
      ',"providerId":' + jsonStr(r.providerId) + '}'
    );
  }
  return '[' + parts.join(',') + ']';
}
