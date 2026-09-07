/**
 * GatewayController —— 网关编排层（应用用例）
 *
 * 收纳原先散落在 UI（pages/Index）里的业务逻辑：把「当前供应商」映射为上游配置并
 * 推送给 C++ 代理、协调供应商 CRUD 与上游热更新、代理启停，M3 智能路由规则的
 * CRUD 与下发（providerId → Provider → upstream 展开后推给 RouteService）。
 * 多渠道管理：活动渠道（claude/codex/opencode，见 types/App.ets 的 CHANNEL_APPS）
 * 由本控制器持有，切换即持久化并把该渠道当前供应商 + 路由表热推给网关（单端口策略）。
 * M4 安全规则自定义词条的 CRUD 与启动回放已下沉到 RuleCustomService（R3），
 * 这里只保留同名公开入口转发。UI 只负责渲染 @State
 * 并把动作委派给本控制器，不再直接接触 repository/service，也不感知 env schema。
 *
 * 采用静态方法单例（与 ProviderRepository / ProxyService 一致），可被 @Component
 * 直接调用；返回同步视图数据供 UI 拷入 @State。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppId, LocalConfigApp, appDisplayName, toChannelApp } from '../types/App';
import { EnvKeySet, envKeysForApp } from '../types/EnvKeys';
import { Provider, ProviderCategory, getEnvValue, inferApiKeyField, getCodexApiKey, getCodexConfigText, tomlStringValue } from '../types/Provider';
import { ProviderPreset } from '../types/Preset';
import { UpstreamConfig, ProxyStatus } from '../types/ProxyTypes';
import { RouteRule, parseRouteRules, routeRulesToJson, genRouteRuleId } from '../types/RouteRule';
import { SecurityRule, RuleCustomEntry } from '../types/SecurityTypes';
import { PasswordLeakAlert, PasswordLeakAuditViewState } from '../types/PasswordLeakAudit';
import { CloudConnectionStatus, CloudProviderPreset, CloudSnapshot, CloudSyncResult } from '../types/CloudConfig';
import { buildCodexJson, jsonStr, strArrayJson } from '../types/Json';
import { ProviderRepository } from '../repository/ProviderRepository';
import { SettingsRepository } from '../repository/SettingsRepository';
import { ProxyService } from '../services/ProxyService';
import { RouteService } from '../services/RouteService';
import { SecurityService } from '../services/SecurityService';
import { PasswordLeakAuditService } from '../services/PasswordLeakAuditService';
import { RuleCustomService } from '../services/RuleCustomService';
import { LocalConfigService } from '../services/LocalConfigService';
import { CloudConfigurationService } from '../services/CloudConfigurationService';
import { getPresetsForApp } from '../config/PresetRegistry';

const DOMAIN = 0x0000;
const TAG = 'GatewayController';
const PASSWORD_ALERT_MAX = 200;
const PASSWORD_ALERT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

function passwordAlertToJson(alert: PasswordLeakAlert): string {
  return '{"id":' + jsonStr(alert.id) +
    ',"timeMs":' + alert.timeMs.toString() +
    ',"severity":' + jsonStr(alert.severity) +
    ',"secretType":' + jsonStr(alert.secretType) +
    ',"location":' + jsonStr(alert.location) +
    ',"protocol":' + jsonStr(alert.protocol) +
    ',"model":' + jsonStr(alert.model) +
    ',"status":' + jsonStr(alert.status) + '}';
}

function passwordAlertsToJson(alerts: PasswordLeakAlert[]): string {
  const parts: string[] = [];
  for (const alert of alerts) {
    parts.push(passwordAlertToJson(alert));
  }
  return '[' + parts.join(',') + ']';
}

function mergePasswordAlerts(persisted: PasswordLeakAlert[], nativeAlerts: PasswordLeakAlert[]): PasswordLeakAlert[] {
  const byId: Map<string, PasswordLeakAlert> = new Map<string, PasswordLeakAlert>();
  for (const alert of persisted) {
    byId.set(alert.id, alert);
  }
  for (const alert of nativeAlerts) {
    byId.set(alert.id, alert);
  }
  const merged: PasswordLeakAlert[] = [];
  byId.forEach((alert: PasswordLeakAlert) => {
    merged.push(alert);
  });
  const now: number = Date.now();
  const kept: PasswordLeakAlert[] = [];
  for (const alert of merged) {
    if (alert.timeMs > 0 && now >= alert.timeMs && now - alert.timeMs <= PASSWORD_ALERT_RETENTION_MS) {
      kept.push(alert);
    }
  }
  kept.sort((left: PasswordLeakAlert, right: PasswordLeakAlert) => right.timeMs - left.timeMs);
  return kept.slice(0, PASSWORD_ALERT_MAX);
}

function passwordAuditView(enabled: boolean, alerts: PasswordLeakAlert[]): PasswordLeakAuditViewState {
  const now: number = Date.now();
  const dayStart: number = now - (now % (24 * 60 * 60 * 1000));
  let unreadCount: number = 0;
  let todayCount: number = 0;
  let lastAlertTimeMs: number = 0;
  for (const alert of alerts) {
    if (alert.status === 'new') {
      unreadCount++;
    }
    if (alert.timeMs >= dayStart) {
      todayCount++;
    }
    if (alert.timeMs > lastAlertTimeMs) {
      lastAlertTimeMs = alert.timeMs;
    }
  }
  return {
    enabled: enabled,
    unreadCount: unreadCount,
    todayCount: todayCount,
    lastAlertTimeMs: lastAlertTimeMs,
    alerts: alerts,
  };
}

export class GatewayController {
  /**
   * 当前活动渠道（多渠道管理）。端口策略：单端口 + 活动渠道切换（cc-switch 式 UX）——
   * 同一时刻只有一个渠道的供应商生效，切换渠道即把该渠道当前供应商与路由表热推给网关。
   * 启动时从 SettingsRepository.activeAppId 回放（见 init）。
   */
  private static activeAppId: LocalConfigApp = 'claude';
  private static initPromise: Promise<void> | null = null;

  /** 初始化数据层（页面 aboutToAppear 调用，保证 repository 就绪） */
  static async init(): Promise<void> {
    if (GatewayController.initPromise !== null) {
      return GatewayController.initPromise;
    }
    GatewayController.initPromise = GatewayController.initialize();
    return GatewayController.initPromise;
  }

  private static async initialize(): Promise<void> {
    await ProviderRepository.loadAll();
    await SettingsRepository.load();
    PasswordLeakAuditService.setEnabled(SettingsRepository.getPasswordLeakAuditEnabled());
    GatewayController.activeAppId = toChannelApp(SettingsRepository.getActiveAppId()); // 回放活动渠道
    const cachedSnapshot: CloudSnapshot | null = CloudConfigurationService.getCachedSnapshot();
    if (cachedSnapshot !== null) {
      await GatewayController.applyCloudSnapshot(cachedSnapshot);
    }
    GatewayController.applyRouteRules(); // 启动即下发已持久化的路由规则
    GatewayController.applyRuleConfigs(); // M4：启动即回放安全自定义词条 + 响应检测开关
  }

  // —— 活动渠道（多渠道管理）——
  static getActiveApp(): LocalConfigApp {
    return GatewayController.activeAppId;
  }

  /** 切换活动渠道：持久化 + 推该渠道当前供应商（applyCurrentProvider 内部连带重下发路由规则） */
  static async setActiveApp(app: LocalConfigApp): Promise<void> {
    if (app === GatewayController.activeAppId) {
      return;
    }
    const previousApp: LocalConfigApp = GatewayController.activeAppId;
    GatewayController.activeAppId = app;
    await SettingsRepository.setActiveAppId(app);
    GatewayController.applyCurrentProvider();
    const status: ProxyStatus = ProxyService.getStatus();
    if (status.isRunning) {
      await LocalConfigService.restoreStop(previousApp);
      await LocalConfigService.applyStart(app, status.port,
        GatewayController.currentProviderModel(app));
    }
  }

  // —— 视图读取（同步）——
  static getProviders(): Provider[] {
    return ProviderRepository.getProviders(GatewayController.activeAppId);
  }

  /**
   * 内置预设与云端已发布预设共同用于“添加供应商”表单。这里绝不写
   * ProviderRepository，因此云端同步不能创建、覆盖或删除用户供应商。
   * 命中云端预设的渠道只显示云端预设（云端成为该渠道唯一运营入口）；
   * 云端未配置的渠道回退内置预设，不限制使用。
   */
  static getProviderPresets(app: AppId): ProviderPreset[] {
    const builtIn: ProviderPreset[] = getPresetsForApp(app);
    if (app !== 'claude' && app !== 'codex' && app !== 'opencode') {
      return builtIn;
    }
    const snapshot: CloudSnapshot | null = CloudConfigurationService.getCachedSnapshot();
    if (snapshot === null) {
      return builtIn;
    }
    const cloudFirst: ProviderPreset[] = [];
    for (const remote of snapshot.providerPresets) {
      if (remote.channelCode === app) {
        cloudFirst.push(GatewayController.cloudPresetToFormPreset(remote));
      }
    }
    if (cloudFirst.length === 0) {
      return builtIn;
    }
    return cloudFirst;
  }
  static getCurrentId(): string {
    return ProviderRepository.getCurrentId(GatewayController.activeAppId);
  }
  static getProxyHost(): string {
    return SettingsRepository.getProxyHost();
  }
  static getProxyPort(): number {
    return SettingsRepository.getProxyPort();
  }

  // —— 云端发布配置（仅已发布快照；真实 API Key 始终留在本地）——
  static getCloudConnectionStatus(): CloudConnectionStatus {
    return CloudConfigurationService.getConnectionStatus();
  }

  /** 云端渠道显示名覆盖本地文案；未配置或未下发时回退内置名称。 */
  static getChannelDisplayName(app: LocalConfigApp): string {
    const snapshot: CloudSnapshot | null = CloudConfigurationService.getCachedSnapshot();
    if (snapshot !== null) {
      for (const channel of snapshot.channels) {
        if (channel.code === app) {
          return channel.displayName;
        }
      }
    }
    return appDisplayName(app);
  }

  /** 云端位置仅作 picker 的展示提示；未下发时保留端侧内置位置且不限制渠道功能。 */
  static getLocalConfigPathHint(app: LocalConfigApp): string {
    const snapshot: CloudSnapshot | null = CloudConfigurationService.getCachedSnapshot();
    if (snapshot !== null) {
      for (const channel of snapshot.channels) {
        if (channel.code === app && channel.localConfigPathHint.length > 0) {
          return channel.localConfigPathHint;
        }
      }
    }
    if (app === 'codex') {
      return '~/.codex/config.toml';
    }
    if (app === 'opencode') {
      return '~/.config/opencode/opencode.json';
    }
    return '~/.claude/settings.json';
  }

  /** 保存设备 API 配置并立刻拉取，供设置页「保存并同步」使用。 */
  static async configureAndSyncCloud(apiBaseUrl: string, deviceKey: string): Promise<CloudSyncResult> {
    const error: string = await CloudConfigurationService.saveConnection(apiBaseUrl, deviceKey);
    if (error.length > 0) {
      return { outcome: 'failed', message: error, snapshot: null, eTag: '', rawSnapshot: '' };
    }
    return GatewayController.syncCloudConfig(true);
  }

  /** 手动/前台/定时触发云端同步；失败时不动现有本地配置。 */
  static async syncCloudConfig(force: boolean): Promise<CloudSyncResult> {
    const result: CloudSyncResult = await CloudConfigurationService.pull(force);
    if (result.outcome !== 'updated' || result.snapshot === null) {
      return result;
    }
    try {
      await GatewayController.applyCloudSnapshot(result.snapshot);
      await CloudConfigurationService.commitAppliedSnapshot(result);
      AppStorage.setOrCreate('cloudConfigEpoch', Date.now());
      return result;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'cloud config apply failed: %{public}s', 'apply_error');
      await SettingsRepository.setCloudLastError('云端配置应用失败');
      return { outcome: 'failed', message: '云端配置应用失败', snapshot: null, eTag: '', rawSnapshot: '' };
    }
  }

  /** 把当前激活供应商推送到代理（设置转发上游 + 网关侧注入真实 Key） */
  static applyCurrentProvider(): void {
    const cur: Provider | null = ProviderRepository.getCurrentProvider(GatewayController.activeAppId);
    if (cur !== null) {
      ProxyService.setUpstream(GatewayController.providerToUpstream(GatewayController.activeAppId, cur));
    } else {
      hilog.info(DOMAIN, TAG, 'no active provider; upstream not set');
    }
    // 上游/供应商变化可能影响规则绑定的 Provider，路由规则随之一并热更新
    GatewayController.applyRouteRules();
  }

  // —— 供应商 CRUD（编排：改仓库 → 热更新上游）——
  static async addProvider(p: Provider): Promise<void> {
    await ProviderRepository.add(GatewayController.activeAppId, p);
    GatewayController.applyCurrentProvider(); // 首个供应商会自动激活
    await GatewayController.refreshActiveLocalConfig();
  }
  static async switchProvider(p: Provider): Promise<void> {
    await ProviderRepository.switchTo(GatewayController.activeAppId, p.id);
    GatewayController.applyCurrentProvider();
    await GatewayController.refreshActiveLocalConfig();
  }
  static async updateProvider(p: Provider, originalId: string): Promise<void> {
    await ProviderRepository.update(GatewayController.activeAppId, p, originalId);
    GatewayController.applyCurrentProvider(); // 编辑可能改了 Key/URL
    await GatewayController.refreshActiveLocalConfig();
  }
  static async removeProvider(id: string): Promise<void> {
    await ProviderRepository.remove(GatewayController.activeAppId, id);
    GatewayController.applyCurrentProvider(); // 删除后当前供应商可能已切换
    await GatewayController.refreshActiveLocalConfig();
  }
  static async duplicateProvider(id: string): Promise<void> {
    await ProviderRepository.duplicate(GatewayController.activeAppId, id);
  }

  // —— 本地 Agent 配置接管（picker URI + 备份恢复）——
  static isLocalConfigLinked(app: LocalConfigApp): boolean {
    return LocalConfigService.isLinked(app);
  }

  static async linkLocalConfig(app: LocalConfigApp): Promise<boolean> {
    const linked: boolean = await LocalConfigService.link(app);
    const status: ProxyStatus = ProxyService.getStatus();
    if (linked && app === GatewayController.activeAppId && status.isRunning) {
      await LocalConfigService.applyStart(app, status.port, GatewayController.currentProviderModel(app));
    }
    return linked;
  }

  static async unlinkLocalConfig(app: LocalConfigApp): Promise<void> {
    await LocalConfigService.unlink(app);
  }

  // —— 智能路由规则 CRUD（M3；持久化在 SettingsRepository.routeRulesJson）——
  /** 读取全部路由规则（同步视图，供 UI 拷入 @State） */
  static getRouteRules(): RouteRule[] {
    return parseRouteRules(SettingsRepository.getRouteRulesJson());
  }

  /** 写回规则数组并热更新到 C++ 代理 */
  private static async saveRouteRules(rules: RouteRule[]): Promise<void> {
    await SettingsRepository.setRouteRulesJson(routeRulesToJson(rules));
    GatewayController.applyRouteRules();
  }

  /** 新增规则（id 为空时自动生成） */
  static async addRouteRule(rule: RouteRule): Promise<void> {
    const rules: RouteRule[] = GatewayController.getRouteRules();
    const created: RouteRule = {
      id: rule.id ? rule.id : genRouteRuleId(),
      name: rule.name,
      priority: rule.priority,
      modelPrefix: rule.modelPrefix,
      protocol: rule.protocol,
      pathPrefix: rule.pathPrefix,
      providerId: rule.providerId,
    };
    rules.push(created);
    await GatewayController.saveRouteRules(rules);
  }

  /** 更新规则（按 id 匹配；不存在则忽略） */
  static async updateRouteRule(rule: RouteRule): Promise<void> {
    const rules: RouteRule[] = GatewayController.getRouteRules();
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].id === rule.id) {
        rules[i] = rule;
        break;
      }
    }
    await GatewayController.saveRouteRules(rules);
  }

  /** 删除规则 */
  static async removeRouteRule(id: string): Promise<void> {
    const kept: RouteRule[] = [];
    for (const r of GatewayController.getRouteRules()) {
      if (r.id !== id) {
        kept.push(r);
      }
    }
    await GatewayController.saveRouteRules(kept);
  }

  /**
   * 把路由规则展开为契约 JSON 推送给 C++ 代理（运行中热更新）。
   * 每条规则的 providerId 经 ProviderRepository 解析成 Provider，再展开为
   * upstream 配置；providerId 已失效（供应商被删）的规则跳过并记日志。
   * 空数组 = 关闭路由，C++ 侧回退默认上游。
   */
  static applyRouteRules(): void {
    const rules: RouteRule[] = GatewayController.getRouteRules();
    const providers: Provider[] = ProviderRepository.getProviders(GatewayController.activeAppId);
    const parts: string[] = [];
    for (const rule of rules) {
      let target: Provider | null = null;
      for (const p of providers) {
        if (p.id === rule.providerId) {
          target = p;
          break;
        }
      }
      if (target === null) {
        hilog.warn(DOMAIN, TAG, `route rule ${rule.id} skipped: provider ${rule.providerId} not found`);
        continue;
      }
      const upstream: UpstreamConfig =
        GatewayController.providerToUpstream(GatewayController.activeAppId, target);
      parts.push(GatewayController.ruleToContractJson(rule, upstream));
    }
    RouteService.setRouteRules('[' + parts.join(',') + ']');
  }

  /**
   * 单条规则 → 契约 JSON 对象（字符串拼接骨架 + 字符串字段逐个
   * jsonStr 转义；严格模式不许 stringify 对象字面量）。
   */
  private static ruleToContractJson(rule: RouteRule, upstream: UpstreamConfig): string {
    return '{"id":' + jsonStr(rule.id) +
      ',"name":' + jsonStr(rule.name) +
      ',"priority":' + rule.priority.toString() +
      ',"modelPrefix":' + jsonStr(rule.modelPrefix) +
      ',"protocol":' + jsonStr(rule.protocol) +
      ',"pathPrefix":' + jsonStr(rule.pathPrefix) +
      ',"upstream":{"baseUrl":' + jsonStr(upstream.baseUrl) +
      ',"apiKey":' + jsonStr(upstream.apiKey) +
      ',"apiKeyField":' + jsonStr(upstream.apiKeyField) +
      ',"model":' + jsonStr(upstream.model) + '}}';
  }

  // —— 安全规则自定义（M4；持久化在 SettingsRepository.ruleCustomJson）——
  /** 读取全部安全规则（含 M4 命中计数/自定义词条，同步视图，供 UI 拷入 @State） */
  static getSecurityRules(): SecurityRule[] {
    return SecurityService.getRules();
  }

  static getResponseSecurityEnabled(): boolean {
    return SettingsRepository.getResponseSecurityEnabled();
  }

  static getSecurityEnabled(): boolean {
    return SettingsRepository.getSecurityEnabled();
  }

  /** 请求侧安全检测开关：持久化并即时下发 C++ 转发管线。 */
  static async setSecurityEnabled(enabled: boolean): Promise<void> {
    await SettingsRepository.setSecurityEnabled(enabled);
    SecurityService.setSecurityEnabled(enabled);
  }

  /** M4：响应侧安全检测开关 —— 持久化 + 即时下发 C++（不经「保存」按钮） */
  static async setResponseSecurityEnabled(enabled: boolean): Promise<void> {
    await SettingsRepository.setResponseSecurityEnabled(enabled);
    SecurityService.setResponseSecurityEnabled(enabled);
  }

  // —— 密码泄露提醒（异步、只保存脱敏元数据）——
  static getPasswordLeakAuditEnabled(): boolean {
    return SettingsRepository.getPasswordLeakAuditEnabled();
  }

  /** 切换开关立即作用于原生队列，并保存本地偏好。 */
  static async setPasswordLeakAuditEnabled(enabled: boolean): Promise<void> {
    const applied: boolean = PasswordLeakAuditService.setEnabled(enabled);
    if (!applied) {
      hilog.warn(DOMAIN, TAG, 'password leak audit switch rejected');
    }
    await SettingsRepository.setPasswordLeakAuditEnabled(enabled);
  }

  /** 合并本次运行的原生环形队列与 ArkData 脱敏镜像，执行 200 条/30 天保留策略。 */
  static async refreshPasswordLeakAudit(): Promise<PasswordLeakAuditViewState> {
    const persisted: PasswordLeakAlert[] = PasswordLeakAuditService.parsePersistedAlerts(
      SettingsRepository.getPasswordLeakAlertsJson());
    const nativePage = PasswordLeakAuditService.getAlerts(0, PASSWORD_ALERT_MAX);
    const merged: PasswordLeakAlert[] = mergePasswordAlerts(persisted, nativePage.alerts);
    await SettingsRepository.setPasswordLeakAlertsJson(passwordAlertsToJson(merged));
    return passwordAuditView(SettingsRepository.getPasswordLeakAuditEnabled(), merged);
  }

  /** 将当前可见历史全部标记为已读，并同步 native 与 preferences。 */
  static async markPasswordLeakAlertsRead(): Promise<PasswordLeakAuditViewState> {
    const existing: PasswordLeakAlert[] = PasswordLeakAuditService.parsePersistedAlerts(
      SettingsRepository.getPasswordLeakAlertsJson());
    const ids: string[] = [];
    for (const alert of existing) {
      ids.push(alert.id);
    }
    PasswordLeakAuditService.markRead(ids);
    const updated: PasswordLeakAlert[] = [];
    for (const alert of existing) {
      updated.push({
        id: alert.id,
        timeMs: alert.timeMs,
        severity: alert.severity,
        secretType: alert.secretType,
        location: alert.location,
        protocol: alert.protocol,
        model: alert.model,
        status: 'read',
      });
    }
    await SettingsRepository.setPasswordLeakAlertsJson(passwordAlertsToJson(updated));
    return GatewayController.refreshPasswordLeakAudit();
  }

  static async clearPasswordLeakAlerts(): Promise<PasswordLeakAuditViewState> {
    PasswordLeakAuditService.clear();
    await SettingsRepository.setPasswordLeakAlertsJson('[]');
    return passwordAuditView(SettingsRepository.getPasswordLeakAuditEnabled(), []);
  }

  /**
   * M4：启动回放 —— 委托 RuleCustomService（R3 下沉）：回放自定义词条 + 下发响应检测开关。
   * C++ 是运行时真相，preferences 只是进程重启后的回放源。
   */
  static applyRuleConfigs(): void {
    RuleCustomService.applyRuleConfigs();
  }

  /** 读取某规则的自定义词条（供自定义对话框展示；数据来自持久化回放源） */
  static getRuleCustomEntry(ruleId: string): RuleCustomEntry {
    return RuleCustomService.getRuleCustomEntry(ruleId);
  }

  /** 添加自定义关键词；返回空串 = 成功，否则为错误提示文案 */
  static async addRuleKeyword(ruleId: string, word: string): Promise<string> {
    return RuleCustomService.addKeyword(ruleId, word);
  }

  /** 添加自定义正则；返回空串 = 成功 */
  static async addRulePattern(ruleId: string, pattern: string): Promise<string> {
    return RuleCustomService.addPattern(ruleId, pattern);
  }

  /** 删除自定义关键词；返回空串 = 成功 */
  static async removeRuleKeyword(ruleId: string, word: string): Promise<string> {
    return RuleCustomService.removeKeyword(ruleId, word);
  }

  /** 删除自定义正则；返回空串 = 成功 */
  static async removeRulePattern(ruleId: string, pattern: string): Promise<string> {
    return RuleCustomService.removePattern(ruleId, pattern);
  }

  /** 应用云端预设目录与安全策略；供应商实例仅由用户在本地创建和维护。 */
  private static async applyCloudSnapshot(snapshot: CloudSnapshot): Promise<void> {
    const securityOk: boolean = await GatewayController.applyCloudSecurityPolicy(snapshot);
    if (!securityOk) {
      throw new Error('security policy rejected');
    }
    await ProviderRepository.removeLegacyCloudProviders();
    GatewayController.applyCurrentProvider();
    await GatewayController.refreshActiveLocalConfig();
  }

  /** 云预设只生成“添加供应商”表单的初始值，API Key 始终为空并由用户填写。 */
  private static cloudPresetToFormPreset(preset: CloudProviderPreset): ProviderPreset {
    const app: LocalConfigApp = preset.channelCode;
    const settingsConfigJson: string = app === 'codex'
      ? GatewayController.buildCloudCodexConfig(preset.endpoint, preset.defaultModel, '')
      : GatewayController.buildCloudEnvConfig(app, preset.endpoint, preset.defaultModel, '');
    return {
      name: preset.displayName,
      settingsConfigJson: settingsConfigJson,
      websiteUrl: preset.websiteUrl,
      apiKeyUrl: preset.apiKeyUrl,
      category: GatewayController.cloudCategory(preset.category),
      isPartner: preset.partner,
      iconColor: GatewayController.safeIconColor(preset.iconColor),
      endpointCandidates: [preset.endpoint],
      isCloudPreset: true,
    };
  }

  private static buildCloudEnvConfig(app: LocalConfigApp, baseUrl: string, model: string,
    apiKey: string): string {
    const keys: EnvKeySet = envKeysForApp(app);
    return '{"env":{' + jsonStr(keys.baseUrlKey) + ':' + jsonStr(baseUrl) + ',' +
      jsonStr(keys.apiKeyField) + ':' + jsonStr(apiKey) + ',' +
      jsonStr(keys.modelKey) + ':' + jsonStr(model) + '}}';
  }

  /** Codex 不直接拼接云端 TOML 原文，只把已校验的端点/模型写入固定模板。 */
  private static buildCloudCodexConfig(baseUrl: string, model: string, apiKey: string): string {
    const config: string = 'model = ' + GatewayController.tomlQuoted(model) +
      '\n\n[model_providers.aigate]\nbase_url = ' + GatewayController.tomlQuoted(baseUrl) +
      '\nwire_api = "responses"\n';
    return buildCodexJson(apiKey, config);
  }

  private static tomlQuoted(value: string): string {
    return '"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
  }

  private static cloudCategory(category: string): ProviderCategory {
    if (category === 'official' || category === 'cn_official' || category === 'cloud_provider' ||
      category === 'aggregator' || category === 'third_party' || category === 'custom' ||
      category === 'omo' || category === 'omo-slim') {
      return category as ProviderCategory;
    }
    return 'cloud_provider';
  }

  /** iconColor 只能采用受信任的十六进制色；iconKey 不作为远程资源 URL 使用。 */
  private static safeIconColor(color: string): string | undefined {
    return /^#[0-9A-Fa-f]{6}$/.test(color) ? color : undefined;
  }

  private static async applyCloudSecurityPolicy(snapshot: CloudSnapshot): Promise<boolean> {
    const available: Map<string, boolean> = new Map<string, boolean>();
    for (const rule of SecurityService.getRules()) {
      available.set(rule.id, true);
    }
    const parts: string[] = [];
    for (const rule of snapshot.securityPolicy.rules) {
      if (!available.has(rule.ruleId)) {
        hilog.warn(DOMAIN, TAG, `cloud rule skipped: ${rule.ruleId}`);
        continue;
      }
      SecurityService.setRuleEnabled(rule.ruleId, rule.action !== 'ALLOW');
      parts.push(jsonStr(rule.ruleId) + ':{"keywords":' + strArrayJson(rule.keywords) +
        ',"patterns":' + strArrayJson(rule.patterns) + '}');
    }
    const rulesApplied: boolean = await RuleCustomService.replaceRuleCustomJson('{' + parts.join(',') + '}');
    if (!rulesApplied) {
      return false;
    }
    await GatewayController.setSecurityEnabled(snapshot.securityPolicy.requestScanEnabled);
    await GatewayController.setResponseSecurityEnabled(snapshot.securityPolicy.responseScanEnabled);
    return true;
  }

  // —— 代理生命周期 ——
  static async startGateway(host: string, port: number): Promise<boolean> {
    GatewayController.applyCurrentProvider(); // 启动前确保上游为最新
    const ok: boolean = await ProxyService.start({ host: host, port: port });
    if (ok) {
      try {
        await LocalConfigService.applyStart(GatewayController.activeAppId, port,
          GatewayController.currentProviderModel(GatewayController.activeAppId));
      } catch (e) {
        hilog.error(DOMAIN, TAG, `local config apply failed: ${JSON.stringify(e)}`);
      }
    }
    return ok;
  }
  static stopGateway(): void {
    ProxyService.stop();
    LocalConfigService.restoreAll().then(() => { // 后台还原所有被接管的本地配置
    }, () => {
    });
  }
  static getStatus(): ProxyStatus {
    return ProxyService.getStatus();
  }

  /** Provider（settingsConfigJson）→ 上游配置；env 键名以 envKeysForApp(app) 为准，codex 走 {auth,config} 形态解析 */
  private static providerToUpstream(app: AppId, p: Provider): UpstreamConfig {
    const json: string = p.settingsConfigJson;
    if (app === 'codex') {
      // codex 形态：{"auth":{"OPENAI_API_KEY":...},"config":"<TOML>"}，baseUrl/model 在 TOML 里
      const toml: string = getCodexConfigText(json);
      return {
        baseUrl: tomlStringValue(toml, 'base_url'),
        apiKey: getCodexApiKey(json),
        apiKeyField: GatewayController.cppApiKeyField('OPENAI_API_KEY'),
        model: tomlStringValue(toml, 'model'),
      };
    }
    const keys: EnvKeySet = envKeysForApp(app);
    const field: string = GatewayController.resolveApiKeyField(json, keys);
    return {
      baseUrl: getEnvValue(json, keys.baseUrlKey),
      apiKey: getEnvValue(json, field),
      apiKeyField: GatewayController.cppApiKeyField(field),
      model: getEnvValue(json, keys.modelKey),
    };
  }

  /** 供本地配置模板写入当前模型；未选择供应商时由服务层使用默认模型。 */
  private static currentProviderModel(app: AppId): string {
    const provider: Provider | null = ProviderRepository.getCurrentProvider(app);
    if (provider === null) {
      return '';
    }
    return GatewayController.providerToUpstream(app, provider).model;
  }

  /** 运行中切换供应商时，刷新 Codex/OpenCode 配置中的可见模型名。 */
  private static async refreshActiveLocalConfig(): Promise<void> {
    const status: ProxyStatus = ProxyService.getStatus();
    if (status.isRunning) {
      await LocalConfigService.applyStart(GatewayController.activeAppId, status.port,
        GatewayController.currentProviderModel(GatewayController.activeAppId));
    }
  }

  /**
   * 认证字段名 → C++ 可识别字段。C++ BuildAuthHeader 只认 ANTHROPIC_API_KEY /
   * ANTHROPIC_AUTH_TOKEN / GEMINI_API_KEY 三个名字（未知字段不注入）；OpenAI 兼容
   * 渠道（codex/opencode 的 OPENAI_API_KEY）的鉴权形态就是 Authorization: Bearer，
   * 与 ANTHROPIC_AUTH_TOKEN 的注入行为完全一致，故映射复用，C++ 零改动。
   */
  private static cppApiKeyField(field: string): string {
    if (field === 'OPENAI_API_KEY') {
      return 'ANTHROPIC_AUTH_TOKEN';
    }
    return field;
  }

  /**
   * 认证字段名：默认取 envKeysForApp 的 apiKeyField。
   * claude 系保留既有行为——env 里显式配置了 ANTHROPIC_API_KEY 时以它为准
   * （该数据驱动的区分逻辑封装在 Provider.inferApiKeyField）。
   */
  private static resolveApiKeyField(json: string, keys: EnvKeySet): string {
    if (keys.apiKeyField === 'ANTHROPIC_AUTH_TOKEN') {
      return inferApiKeyField(json);
    }
    return keys.apiKeyField;
  }
}
