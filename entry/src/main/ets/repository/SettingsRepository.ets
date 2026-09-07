/**
 * SettingsRepository —— 应用级设置（持久化层，ArkData preferences；配置单一数据源）
 *
 * 取代了原先走 C++ ConfigManager 的 ConfigService：proxy.host/port、proxy.auto_start、
 * security.enabled 现统一由 preferences 持久化（此前 ConfigService 从未真正落盘）。
 * 镜像 ProviderRepository 的 pref 模式：init(ctx) → async load() → 同步 getter / 异步 setter。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalConfigApp } from '../types/App';

const DOMAIN = 0x0000;
const TAG = 'SettingsRepository';
const PREF_NAME = 'aigate_settings';
const KEY = 'settings';

/** 网关设置（缓存对象，强类型，规避 ArkTS 对任意对象字面量的限制） */
export interface GatewaySettings {
  proxyHost: string;
  proxyPort: number;
  proxyAutoStart: boolean;
  securityEnabled: boolean;
  claudeSettingsUri: string;    // 用户关联的 ~/.claude/settings.json 的持久化 URI（picker 授予）
  claudeSettingsBackup: string; // 启动时备份的 settings.json 原文，停止时还原
  claudeSettingsBackupReady: boolean;
  codexConfigUri: string;       // 用户关联的 ~/.codex/config.toml 的持久化 URI
  codexConfigBackup: string;
  codexConfigBackupReady: boolean;
  openCodeConfigUri: string;    // 用户关联的 ~/.config/opencode/opencode.json 的持久化 URI
  openCodeConfigBackup: string;
  openCodeConfigBackupReady: boolean;
  routeRulesJson: string;       // 路由规则（JSON 数组字符串，M3 用，本期只加存储）
  themeMode: string;            // 主题模式 'system'|'light'|'dark'（M5，由 ThemeController 消费）
  skinId: string;               // 皮肤 ID（M5，取值见 types/Skin.ets 的 SKINS，默认 'default'）
  responseSecurityEnabled: boolean; // M4：响应侧安全检测开关（默认开）
  ruleCustomJson: string;       // M4：规则自定义词条 {ruleId: {"keywords":[...],"patterns":[...]}}，重启回放给 C++
  passwordLeakAuditEnabled: boolean; // 密码泄露提醒总开关（默认开）
  passwordLeakAlertsJson: string;    // 仅保存脱敏告警元数据数组，最多 200 条/30 天
  activeAppId: string;          // 多渠道管理：当前活动渠道（取值见 types/App.ets 的 CHANNEL_APPS，默认 'claude'）
  cloudApiBaseUrl: string;      // 云端设备 API 前缀（HTTP/HTTPS，例如 http://config.example.com/api/v1）
  cloudDeviceKey: string;       // 云端设备密钥，仅存 preferences，日志/UI 不输出明文
  cloudEtag: string;            // 上一次成功快照的 ETag，用于 If-None-Match
  cloudConfigVersion: number;   // 上一次成功应用的全局配置版本
  cloudSecurityPolicyVersion: number;
  cloudLastSuccessAt: number;   // 毫秒时间戳；超过 6 小时允许后台自动同步
  cloudLastError: string;       // 仅保存无敏感信息的错误类别
  cloudSnapshotJson: string;    // 最后一次完整校验并应用的发布快照（不含真实 API Key）
}

function defaultSettings(): GatewaySettings {
  return {
    proxyHost: '127.0.0.1',
    proxyPort: 8080,
    proxyAutoStart: false,
    securityEnabled: true,
    claudeSettingsUri: '',
    claudeSettingsBackup: '',
    claudeSettingsBackupReady: false,
    codexConfigUri: '',
    codexConfigBackup: '',
    codexConfigBackupReady: false,
    openCodeConfigUri: '',
    openCodeConfigBackup: '',
    openCodeConfigBackupReady: false,
    routeRulesJson: '[]',
    themeMode: 'system',
    skinId: 'default',
    responseSecurityEnabled: true,
    ruleCustomJson: '{}',
    passwordLeakAuditEnabled: true,
    passwordLeakAlertsJson: '[]',
    activeAppId: 'claude',
    cloudApiBaseUrl: '',
    cloudDeviceKey: '',
    cloudEtag: '',
    cloudConfigVersion: 0,
    cloudSecurityPolicyVersion: 0,
    cloudLastSuccessAt: 0,
    cloudLastError: '',
    cloudSnapshotJson: '',
  };
}

export class SettingsRepository {
  private static ctx: common.Context | null = null;
  private static settings: GatewaySettings = defaultSettings();
  private static ready: boolean = false;

  /** 初始化（由 EntryAbility 调用，注入 ability context） */
  static init(context: common.Context): void {
    SettingsRepository.ctx = context;
  }

  private static async pref() {
    if (SettingsRepository.ctx === null) {
      return null;
    }
    return await preferences.getPreferences(SettingsRepository.ctx, PREF_NAME);
  }

  /** 从 preferences 加载；解析失败回退默认值 */
  static async load(): Promise<void> {
    const pref = await SettingsRepository.pref();
    if (pref === null) {
      SettingsRepository.ready = true;
      return;
    }
    const s: GatewaySettings = defaultSettings();
    const raw: ESObject = await pref.get(KEY, '');
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const obj: ESObject = JSON.parse(raw);
        const ph: ESObject = obj['proxyHost'];
        if (typeof ph === 'string') {
          s.proxyHost = ph as string;
        }
        const pp: ESObject = obj['proxyPort'];
        if (typeof pp === 'number') {
          s.proxyPort = pp as number;
        }
        const pa: ESObject = obj['proxyAutoStart'];
        if (typeof pa === 'boolean') {
          s.proxyAutoStart = pa as boolean;
        }
        const se: ESObject = obj['securityEnabled'];
        if (typeof se === 'boolean') {
          s.securityEnabled = se as boolean;
        }
        const cu: ESObject = obj['claudeSettingsUri'];
        if (typeof cu === 'string') {
          s.claudeSettingsUri = cu as string;
        }
        const cb: ESObject = obj['claudeSettingsBackup'];
        if (typeof cb === 'string') {
          s.claudeSettingsBackup = cb as string;
          // 兼容旧版本：旧版仅在原文件非空时才保存备份。
          s.claudeSettingsBackupReady = s.claudeSettingsBackup.length > 0;
        }
        const cbr: ESObject = obj['claudeSettingsBackupReady'];
        if (typeof cbr === 'boolean') {
          s.claudeSettingsBackupReady = cbr as boolean;
        }
        const codexUri: ESObject = obj['codexConfigUri'];
        if (typeof codexUri === 'string') {
          s.codexConfigUri = codexUri as string;
        }
        const codexBackup: ESObject = obj['codexConfigBackup'];
        if (typeof codexBackup === 'string') {
          s.codexConfigBackup = codexBackup as string;
        }
        const codexBackupReady: ESObject = obj['codexConfigBackupReady'];
        if (typeof codexBackupReady === 'boolean') {
          s.codexConfigBackupReady = codexBackupReady as boolean;
        }
        const openCodeUri: ESObject = obj['openCodeConfigUri'];
        if (typeof openCodeUri === 'string') {
          s.openCodeConfigUri = openCodeUri as string;
        }
        const openCodeBackup: ESObject = obj['openCodeConfigBackup'];
        if (typeof openCodeBackup === 'string') {
          s.openCodeConfigBackup = openCodeBackup as string;
        }
        const openCodeBackupReady: ESObject = obj['openCodeConfigBackupReady'];
        if (typeof openCodeBackupReady === 'boolean') {
          s.openCodeConfigBackupReady = openCodeBackupReady as boolean;
        }
        const rr: ESObject = obj['routeRulesJson'];
        if (typeof rr === 'string') {
          s.routeRulesJson = rr as string;
        }
        const tm: ESObject = obj['themeMode'];
        if (typeof tm === 'string') {
          s.themeMode = tm as string;
        }
        const sk: ESObject = obj['skinId'];
        if (typeof sk === 'string') {
          s.skinId = sk as string;
        }
        const rs: ESObject = obj['responseSecurityEnabled'];
        if (typeof rs === 'boolean') {
          s.responseSecurityEnabled = rs as boolean;
        }
        const rc: ESObject = obj['ruleCustomJson'];
        if (typeof rc === 'string') {
          s.ruleCustomJson = rc as string;
        }
        const pla: ESObject = obj['passwordLeakAuditEnabled'];
        if (typeof pla === 'boolean') {
          s.passwordLeakAuditEnabled = pla as boolean;
        }
        const plh: ESObject = obj['passwordLeakAlertsJson'];
        if (typeof plh === 'string') {
          s.passwordLeakAlertsJson = plh as string;
        }
        const aa: ESObject = obj['activeAppId'];
        if (typeof aa === 'string') {
          s.activeAppId = aa as string;
        }
        const cloudUrl: ESObject = obj['cloudApiBaseUrl'];
        if (typeof cloudUrl === 'string') {
          s.cloudApiBaseUrl = cloudUrl as string;
        }
        const cloudKey: ESObject = obj['cloudDeviceKey'];
        if (typeof cloudKey === 'string') {
          s.cloudDeviceKey = cloudKey as string;
        }
        const cloudEtag: ESObject = obj['cloudEtag'];
        if (typeof cloudEtag === 'string') {
          s.cloudEtag = cloudEtag as string;
        }
        const cloudVersion: ESObject = obj['cloudConfigVersion'];
        if (typeof cloudVersion === 'number') {
          s.cloudConfigVersion = cloudVersion as number;
        }
        const cloudPolicyVersion: ESObject = obj['cloudSecurityPolicyVersion'];
        if (typeof cloudPolicyVersion === 'number') {
          s.cloudSecurityPolicyVersion = cloudPolicyVersion as number;
        }
        const cloudSuccess: ESObject = obj['cloudLastSuccessAt'];
        if (typeof cloudSuccess === 'number') {
          s.cloudLastSuccessAt = cloudSuccess as number;
        }
        const cloudError: ESObject = obj['cloudLastError'];
        if (typeof cloudError === 'string') {
          s.cloudLastError = cloudError as string;
        }
        const cloudSnapshot: ESObject = obj['cloudSnapshotJson'];
        if (typeof cloudSnapshot === 'string') {
          s.cloudSnapshotJson = cloudSnapshot as string;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, `load parse failed: ${JSON.stringify(e)}`);
      }
    }
    SettingsRepository.settings = s;
    SettingsRepository.ready = true;
    hilog.info(DOMAIN, TAG, 'SettingsRepository loaded');
  }

  private static async persist(): Promise<void> {
    const pref = await SettingsRepository.pref();
    if (pref === null) {
      return;
    }
    await pref.put(KEY, JSON.stringify(SettingsRepository.settings));
    await pref.flush();
  }

  // —— 同步 getter（读缓存）——
  static getProxyHost(): string {
    return SettingsRepository.settings.proxyHost;
  }
  static getProxyPort(): number {
    return SettingsRepository.settings.proxyPort;
  }
  static getProxyAutoStart(): boolean {
    return SettingsRepository.settings.proxyAutoStart;
  }
  static getSecurityEnabled(): boolean {
    return SettingsRepository.settings.securityEnabled;
  }

  // —— 异步 setter（改缓存 + 落盘）——
  static async setProxy(host: string, port: number): Promise<void> {
    SettingsRepository.settings.proxyHost = host;
    SettingsRepository.settings.proxyPort = port;
    await SettingsRepository.persist();
  }

  static async setAutoStart(autoStart: boolean): Promise<void> {
    SettingsRepository.settings.proxyAutoStart = autoStart;
    await SettingsRepository.persist();
  }

  static async setSecurityEnabled(enabled: boolean): Promise<void> {
    SettingsRepository.settings.securityEnabled = enabled;
    await SettingsRepository.persist();
  }

  // —— 本地 Agent 配置关联 / 备份（Claude / Codex / OpenCode）——
  static getLocalConfigUri(app: LocalConfigApp): string {
    if (app === 'codex') {
      return SettingsRepository.settings.codexConfigUri;
    }
    if (app === 'opencode') {
      return SettingsRepository.settings.openCodeConfigUri;
    }
    return SettingsRepository.settings.claudeSettingsUri;
  }
  static getLocalConfigBackup(app: LocalConfigApp): string {
    if (app === 'codex') {
      return SettingsRepository.settings.codexConfigBackup;
    }
    if (app === 'opencode') {
      return SettingsRepository.settings.openCodeConfigBackup;
    }
    return SettingsRepository.settings.claudeSettingsBackup;
  }
  static isLocalConfigBackupReady(app: LocalConfigApp): boolean {
    if (app === 'codex') {
      return SettingsRepository.settings.codexConfigBackupReady;
    }
    if (app === 'opencode') {
      return SettingsRepository.settings.openCodeConfigBackupReady;
    }
    return SettingsRepository.settings.claudeSettingsBackupReady;
  }
  static async setLocalConfigUri(app: LocalConfigApp, uri: string): Promise<void> {
    if (app === 'codex') {
      SettingsRepository.settings.codexConfigUri = uri;
    } else if (app === 'opencode') {
      SettingsRepository.settings.openCodeConfigUri = uri;
    } else {
      SettingsRepository.settings.claudeSettingsUri = uri;
    }
    await SettingsRepository.persist();
  }
  static async setLocalConfigBackup(app: LocalConfigApp, backup: string, ready: boolean): Promise<void> {
    if (app === 'codex') {
      SettingsRepository.settings.codexConfigBackup = backup;
      SettingsRepository.settings.codexConfigBackupReady = ready;
    } else if (app === 'opencode') {
      SettingsRepository.settings.openCodeConfigBackup = backup;
      SettingsRepository.settings.openCodeConfigBackupReady = ready;
    } else {
      SettingsRepository.settings.claudeSettingsBackup = backup;
      SettingsRepository.settings.claudeSettingsBackupReady = ready;
    }
    await SettingsRepository.persist();
  }

  // —— 路由规则 / 主题模式 / 皮肤（M3 / M5）——
  static getRouteRulesJson(): string {
    return SettingsRepository.settings.routeRulesJson;
  }
  static getThemeMode(): string {
    return SettingsRepository.settings.themeMode;
  }
  static getSkinId(): string {
    return SettingsRepository.settings.skinId;
  }
  static async setRouteRulesJson(rulesJson: string): Promise<void> {
    SettingsRepository.settings.routeRulesJson = rulesJson;
    await SettingsRepository.persist();
  }
  static async setThemeMode(mode: string): Promise<void> {
    SettingsRepository.settings.themeMode = mode;
    await SettingsRepository.persist();
  }
  static async setSkinId(id: string): Promise<void> {
    SettingsRepository.settings.skinId = id;
    await SettingsRepository.persist();
  }

  // —— M4：响应侧安全检测开关 + 规则自定义词条 ——
  static getResponseSecurityEnabled(): boolean {
    return SettingsRepository.settings.responseSecurityEnabled;
  }
  static getRuleCustomJson(): string {
    return SettingsRepository.settings.ruleCustomJson;
  }
  static async setResponseSecurityEnabled(enabled: boolean): Promise<void> {
    SettingsRepository.settings.responseSecurityEnabled = enabled;
    await SettingsRepository.persist();
  }
  static async setRuleCustomJson(json: string): Promise<void> {
    SettingsRepository.settings.ruleCustomJson = json;
    await SettingsRepository.persist();
  }

  // —— 密码泄露提醒（异步审计的脱敏历史镜像）——
  static getPasswordLeakAuditEnabled(): boolean {
    return SettingsRepository.settings.passwordLeakAuditEnabled;
  }
  static getPasswordLeakAlertsJson(): string {
    return SettingsRepository.settings.passwordLeakAlertsJson;
  }
  static async setPasswordLeakAuditEnabled(enabled: boolean): Promise<void> {
    SettingsRepository.settings.passwordLeakAuditEnabled = enabled;
    await SettingsRepository.persist();
  }
  static async setPasswordLeakAlertsJson(json: string): Promise<void> {
    SettingsRepository.settings.passwordLeakAlertsJson = json;
    await SettingsRepository.persist();
  }

  // —— 多渠道管理：活动渠道 ——
  static getActiveAppId(): string {
    return SettingsRepository.settings.activeAppId;
  }
  static async setActiveAppId(appId: string): Promise<void> {
    SettingsRepository.settings.activeAppId = appId;
    await SettingsRepository.persist();
  }

  // —— 云端发布快照（设备密钥、ETag、最后一次成功配置）——
  static getCloudApiBaseUrl(): string {
    return SettingsRepository.settings.cloudApiBaseUrl;
  }
  static getCloudDeviceKey(): string {
    return SettingsRepository.settings.cloudDeviceKey;
  }
  static getCloudEtag(): string {
    return SettingsRepository.settings.cloudEtag;
  }
  static getCloudConfigVersion(): number {
    return SettingsRepository.settings.cloudConfigVersion;
  }
  static getCloudSecurityPolicyVersion(): number {
    return SettingsRepository.settings.cloudSecurityPolicyVersion;
  }
  static getCloudLastSuccessAt(): number {
    return SettingsRepository.settings.cloudLastSuccessAt;
  }
  static getCloudLastError(): string {
    return SettingsRepository.settings.cloudLastError;
  }
  static getCloudSnapshotJson(): string {
    return SettingsRepository.settings.cloudSnapshotJson;
  }
  static async setCloudConnection(apiBaseUrl: string, deviceKey: string): Promise<void> {
    const changed: boolean = SettingsRepository.settings.cloudApiBaseUrl !== apiBaseUrl ||
      SettingsRepository.settings.cloudDeviceKey !== deviceKey;
    SettingsRepository.settings.cloudApiBaseUrl = apiBaseUrl;
    SettingsRepository.settings.cloudDeviceKey = deviceKey;
    if (changed) {
      SettingsRepository.settings.cloudEtag = '';
      SettingsRepository.settings.cloudConfigVersion = 0;
      SettingsRepository.settings.cloudSecurityPolicyVersion = 0;
      SettingsRepository.settings.cloudLastSuccessAt = 0;
      SettingsRepository.settings.cloudLastError = '';
      // 设备密钥或租户地址变化后，旧快照不再属于当前配置域，避免启动时先回放旧策略。
      SettingsRepository.settings.cloudSnapshotJson = '';
    }
    await SettingsRepository.persist();
  }
  /** 只有完整快照完成端侧合并后才调用，避免半套云配置落盘。 */
  static async setAppliedCloudSnapshot(etag: string, configVersion: number,
    securityPolicyVersion: number, snapshotJson: string): Promise<void> {
    SettingsRepository.settings.cloudEtag = etag;
    SettingsRepository.settings.cloudConfigVersion = configVersion;
    SettingsRepository.settings.cloudSecurityPolicyVersion = securityPolicyVersion;
    SettingsRepository.settings.cloudLastSuccessAt = Date.now();
    SettingsRepository.settings.cloudLastError = '';
    SettingsRepository.settings.cloudSnapshotJson = snapshotJson;
    await SettingsRepository.persist();
  }
  static async setCloudLastError(message: string): Promise<void> {
    SettingsRepository.settings.cloudLastError = message;
    await SettingsRepository.persist();
  }
}
