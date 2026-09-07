/**
 * 插件服务 —— libentry.so 动态库插件能力的薄封装（M2）。
 * 类型定义见 types/PluginTypes。
 *
 * 鸿蒙现实约束：第三方应用只能 dlopen 自己沙箱内/随包发货的 .so，
 * 因此插件目录固定为应用 filesDir/plugins（由 EntryAbility 启动时传入），
 * 不支持加载沙箱外任意路径的动态库。
 */
import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { PluginItem } from '../types/PluginTypes';

const DOMAIN = 0x0000;
const TAG = 'PluginService';

export class PluginService {
  /**
   * 扫描目录加载全部动态库插件（设备侧 .so），返回成功加载数。
   * 目录不存在/为空返回 0，不算错误。
   */
  static async loadPlugins(dir: string): Promise<number> {
    try {
      const count = await libentry.loadPlugins(dir);
      hilog.info(DOMAIN, TAG, `loadPlugins(${dir}): %{public}d loaded`, count);
      return count;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `loadPlugins failed: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  /** 获取统一插件表（内置适配器 + 文件插件；含加载失败条目及其错误信息） */
  static listPlugins(): PluginItem[] {
    try {
      const json = libentry.listPlugins();
      return JSON.parse(json) as PluginItem[];
    } catch (error) {
      hilog.error(DOMAIN, TAG, `listPlugins failed: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /** 启用/禁用插件（含内置检测器适配器 builtin-security-detector） */
  static setPluginEnabled(id: string, enabled: boolean): boolean {
    try {
      const ok = libentry.setPluginEnabled(id, enabled);
      hilog.info(DOMAIN, TAG, `Plugin ${id} ${enabled ? 'enabled' : 'disabled'}: %{public}s`,
        ok ? 'ok' : 'rejected');
      return ok;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `setPluginEnabled failed: ${JSON.stringify(error)}`);
      return false;
    }
  }
}
