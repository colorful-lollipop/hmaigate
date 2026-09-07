/**
 * 路由服务 —— libentry.so 智能路由能力的薄封装（M3）。
 *
 * 推送给 C++ 的 JSON 契约（数组，priority 大者优先，同优先级按数组顺序）：
 * [{ "id", "name", "priority", "modelPrefix", "protocol", "pathPrefix",
 *    "upstream": { "baseUrl", "apiKey", "apiKeyField", "model" } }]
 * upstream 由 GatewayController.applyRouteRules 从规则绑定的 Provider 展开；
 * 空数组 = 关闭路由，回退默认上游。契约构造见 app/GatewayController.ets。
 */
import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RouteService';

export class RouteService {
  /**
   * 下发路由规则（契约 JSON 数组字符串），返回 C++ 侧是否接受。
   * 可在代理运行中调用（规则/供应商变更时热更新）。
   */
  static setRouteRules(rulesJson: string): boolean {
    try {
      const ok = libentry.setRouteRules(rulesJson);
      hilog.info(DOMAIN, TAG, `setRouteRules: %{public}s`, ok ? 'ok' : 'rejected');
      return ok;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `setRouteRules failed: ${JSON.stringify(error)}`);
      return false;
    }
  }
}
