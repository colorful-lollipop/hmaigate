/**
 * Json —— 手写 JSON 拼接/解析的共享助手（types/ 层，R3 收敛）
 *
 * 背景：ArkTS 严格模式不允许 JSON.stringify 对象字面量，动态 JSON 一律
 * 「字符串拼接骨架 + 字符串字段逐个转义」；ESObject 的宽容解析也有固定写法
 * （索引循环 + 显式注解，for-of 循环变量会被推成隐式 any，过不了
 * arkts-no-any-unknown）。这些写法此前在 GatewayController / SecurityService /
 * AddProviderDialog / EditProviderDialog / RouteRule 里逐字重复，这里收敛为一份。
 */

/** 字符串字段转义（JSON.stringify 的语义化别名，拼接骨架专用） */
export function jsonStr(s: string): string {
  return JSON.stringify(s);
}

/** 字符串数组 → JSON 数组字面量（每个元素 jsonStr 转义） */
export function strArrayJson(arr: string[]): string {
  const parts: string[] = [];
  for (const s of arr) {
    parts.push(jsonStr(s));
  }
  return '[' + parts.join(',') + ']';
}

/** 从任意 JSON 值宽容解析字符串数组（非数组 / 非字符串元素一律跳过，回退空数组） */
export function parseStringArray(v: ESObject): string[] {
  const out: string[] = [];
  if (Array.isArray(v)) {
    // 索引循环 + 显式注解：for-of 的循环变量会被推成隐式 any，过不了 arkts-no-any-unknown
    const arr: ESObject[] = v as ESObject[];
    for (let i = 0; i < arr.length; i++) {
      const item: ESObject = arr[i];
      if (typeof item === 'string') {
        out.push(item as string);
      }
    }
  }
  return out;
}

/** Codex 形态 settingsConfigJson：{"auth":{"OPENAI_API_KEY":...},"config":...} */
export function buildCodexJson(apiKey: string, config: string): string {
  return '{"auth":{"OPENAI_API_KEY":' + jsonStr(apiKey) + '},"config":' + jsonStr(config) + '}';
}
