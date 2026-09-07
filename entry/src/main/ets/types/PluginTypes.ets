/**
 * 动态库插件相关共享类型（单一数据源，M2）
 * 字段形态与 libentry.so listPlugins 返回的 JSON 数组元素一致。
 */

/** 单个插件的可展示状态 */
export interface PluginItem {
  id: string;
  name: string;
  version: string;
  description: string;
  author: string;
  type: string;    // 'security' | 'transform' | 'other'
  enabled: boolean;
  source: string;  // 'builtin' | 'file'
  error: string;   // 空串 = 加载成功；非空 = 加载/校验失败原因
}
