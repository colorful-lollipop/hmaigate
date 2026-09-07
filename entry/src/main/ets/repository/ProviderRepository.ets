/**
 * ProviderRepository —— 供应商数据层（持久化层，ArkData preferences）
 *
 * 每个应用维护一份 AppConfig { providers, current }，持久化到 preferences。
 * 对应 cc-switch src/lib/api/providers.ts 的 providersApi（getAll/getCurrent/add/
 * update/delete/switch）。纯持久化，不含业务编排（编排见 app/GatewayController）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppId, APP_IDS, LocalConfigApp } from '../types/App';
import { Provider, AppConfig, emptyAppConfig } from '../types/Provider';

const DOMAIN = 0x0000;
const TAG = 'ProviderRepository';
const PREF_NAME = 'cc_switch_providers';

function prefKey(app: AppId): string {
  return 'providers.' + app;
}

export class ProviderRepository {
  private static ctx: common.Context | null = null;
  private static cache: Map<string, AppConfig> = new Map<string, AppConfig>();
  private static ready: boolean = false;

  /** 初始化（由 EntryAbility 调用，传入 ability context） */
  static init(context: common.Context): void {
    ProviderRepository.ctx = context;
  }

  private static async pref() {
    if (ProviderRepository.ctx === null) {
      return null;
    }
    return await preferences.getPreferences(ProviderRepository.ctx, PREF_NAME);
  }

  /** 加载全部应用到内存缓存 */
  static async loadAll(): Promise<void> {
    const pref = await ProviderRepository.pref();
    if (pref === null) {
      ProviderRepository.ready = true;
      return;
    }
    for (const app of APP_IDS) {
      const raw: ESObject = await pref.get(prefKey(app), '');
      if (typeof raw === 'string' && raw.length > 0) {
        ProviderRepository.cache.set(app, ProviderRepository.parseConfig(raw));
      } else {
        ProviderRepository.cache.set(app, emptyAppConfig());
      }
    }
    ProviderRepository.ready = true;
    hilog.info(DOMAIN, TAG, 'ProviderStore loaded');
  }

  private static parseConfig(raw: string): AppConfig {
    try {
      const obj: ESObject = JSON.parse(raw);
      const providersVal: ESObject = obj['providers'];
      const currentVal: ESObject = obj['current'];
      const providers: Record<string, Provider> =
        (providersVal !== undefined && providersVal !== null && typeof providersVal === 'object')
          ? providersVal as Record<string, Provider>
          : {};
      const current: string =
        (typeof currentVal === 'string') ? currentVal as string : '';
      return { providers: providers, current: current };
    } catch (e) {
      hilog.error(DOMAIN, TAG, `parseConfig failed: ${JSON.stringify(e)}`);
      return emptyAppConfig();
    }
  }

  private static async persist(app: AppId): Promise<void> {
    const pref = await ProviderRepository.pref();
    if (pref === null) {
      return;
    }
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    const json: string = cfg ? JSON.stringify(cfg) : JSON.stringify(emptyAppConfig());
    await pref.put(prefKey(app), json);
    await pref.flush();
  }

  /** 三个可见渠道的一次持久化提交，用于兼容迁移避免可见半状态。 */
  private static async persistVisibleAppBatch(): Promise<void> {
    const pref = await ProviderRepository.pref();
    if (pref === null) {
      return;
    }
    const apps: LocalConfigApp[] = ['claude', 'codex', 'opencode'];
    for (const app of apps) {
      const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
      await pref.put(prefKey(app), JSON.stringify(cfg !== undefined ? cfg : emptyAppConfig()));
    }
    await pref.flush();
  }

  /** 获取某应用的全部供应商（按 sortIndex 排序） */
  static getProviders(app: AppId): Provider[] {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg) {
      return [];
    }
    const list: Provider[] = [];
    const keys: string[] = Object.keys(cfg.providers);
    for (const k of keys) {
      list.push(cfg.providers[k]);
    }
    list.sort((a: Provider, b: Provider): number => {
      const ai: number = a.sortIndex !== undefined ? a.sortIndex : 0;
      const bi: number = b.sortIndex !== undefined ? b.sortIndex : 0;
      return ai - bi;
    });
    return list;
  }

  /** 当前激活的供应商 id */
  static getCurrentId(app: AppId): string {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    return cfg ? cfg.current : '';
  }

  /** 当前激活的供应商对象 */
  static getCurrentProvider(app: AppId): Provider | null {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg || !cfg.current) {
      return null;
    }
    return cfg.providers[cfg.current] ?? null;
  }

  /** 生成新 id */
  private static genId(): string {
    return 'p_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 1000000).toString(36);
  }

  /** 以 base 为模板，用 edits 中的可编辑字段覆盖（显式拷贝，规避 ArkTS 对对象展开的限制） */
  private static cloneWithEdits(base: Provider, edits: Provider): Provider {
    return {
      id: edits.id ? edits.id : base.id,
      name: edits.name,
      settingsConfigJson: edits.settingsConfigJson,
      websiteUrl: edits.websiteUrl,
      category: edits.category !== undefined ? edits.category : base.category,
      createdAt: base.createdAt,
      sortIndex: base.sortIndex,
      notes: edits.notes,
      isPartner: edits.isPartner !== undefined ? edits.isPartner : base.isPartner,
      icon: edits.icon !== undefined ? edits.icon : base.icon,
      iconColor: edits.iconColor !== undefined ? edits.iconColor : base.iconColor,
      inFailoverQueue: base.inFailoverQueue,
    };
  }

  /** 从 Record 中移除指定 key（ArkTS 不支持 delete，需重建） */
  private static removeProviderKey(rec: Record<string, Provider>, key: string): Record<string, Provider> {
    const out: Record<string, Provider> = {};
    const keys: string[] = Object.keys(rec);
    for (const k of keys) {
      if (k !== key) {
        out[k] = rec[k];
      }
    }
    return out;
  }

  /** 新增供应商；返回新 id。对应 cc-switch add_provider */
  static async add(app: AppId, provider: Provider): Promise<string> {
    if (!ProviderRepository.cache.has(app)) {
      ProviderRepository.cache.set(app, emptyAppConfig());
    }
    const cfg: AppConfig = ProviderRepository.cache.get(app) as AppConfig;
    const id: string = provider.id ? provider.id : ProviderRepository.genId();
    const created: Provider = {
      id: id,
      name: provider.name,
      settingsConfigJson: provider.settingsConfigJson,
      websiteUrl: provider.websiteUrl,
      category: provider.category,
      createdAt: Date.now(),
      sortIndex: provider.sortIndex !== undefined ? provider.sortIndex : Object.keys(cfg.providers).length,
      notes: provider.notes,
      isPartner: provider.isPartner,
      icon: provider.icon,
      iconColor: provider.iconColor,
      inFailoverQueue: provider.inFailoverQueue,
    };
    cfg.providers[id] = created;
    // 首个供应商自动激活
    if (!cfg.current) {
      cfg.current = id;
    }
    ProviderRepository.cache.set(app, cfg);
    await ProviderRepository.persist(app);
    hilog.info(DOMAIN, TAG, `added provider ${id} to ${app}`);
    return id;
  }

  /** 更新供应商；originalId 用于 id 变更场景。对应 cc-switch update_provider */
  static async update(app: AppId, provider: Provider, originalId?: string): Promise<void> {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg) {
      return;
    }
    const oldId: string = originalId ? originalId : provider.id;
    const existing: Provider | undefined = cfg.providers[oldId];
    if (!existing) {
      return;
    }
    const updated: Provider = ProviderRepository.cloneWithEdits(existing, provider);
    if (originalId && originalId !== provider.id) {
      cfg.providers = ProviderRepository.removeProviderKey(cfg.providers, oldId);
      cfg.providers[provider.id] = updated;
      if (cfg.current === oldId) {
        cfg.current = provider.id;
      }
    } else {
      cfg.providers[oldId] = updated;
    }
    ProviderRepository.cache.set(app, cfg);
    await ProviderRepository.persist(app);
  }

  /** 删除供应商。对应 cc-switch delete_provider */
  static async remove(app: AppId, id: string): Promise<void> {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg) {
      return;
    }
    if (cfg.providers[id] === undefined) {
      return;
    }
    cfg.providers = ProviderRepository.removeProviderKey(cfg.providers, id);
    if (cfg.current === id) {
      const keys: string[] = Object.keys(cfg.providers);
      cfg.current = keys.length > 0 ? keys[0] : '';
    }
    ProviderRepository.cache.set(app, cfg);
    await ProviderRepository.persist(app);
  }

  /** 切换当前供应商。对应 cc-switch switch_provider */
  static async switchTo(app: AppId, id: string): Promise<void> {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg) {
      return;
    }
    if (cfg.providers[id] === undefined) {
      hilog.warn(DOMAIN, TAG, `switchTo: provider ${id} not found in ${app}`);
      return;
    }
    cfg.current = id;
    ProviderRepository.cache.set(app, cfg);
    await ProviderRepository.persist(app);
    hilog.info(DOMAIN, TAG, `switched ${app} -> ${id}`);
  }

  /** 复制供应商。对应 cc-switch handleDuplicateProvider */
  static async duplicate(app: AppId, id: string): Promise<string | null> {
    const cfg: AppConfig | undefined = ProviderRepository.cache.get(app);
    if (!cfg) {
      return null;
    }
    const src: Provider | undefined = cfg.providers[id];
    if (!src) {
      return null;
    }
    const newId: string = ProviderRepository.genId();
    const copy: Provider = {
      id: newId,
      name: src.name + ' copy',
      settingsConfigJson: src.settingsConfigJson,
      websiteUrl: src.websiteUrl,
      category: src.category,
      createdAt: Date.now(),
      sortIndex: src.sortIndex !== undefined ? src.sortIndex + 1 : undefined,
      notes: src.notes,
      isPartner: src.isPartner,
      icon: src.icon,
      iconColor: src.iconColor,
    };
    cfg.providers[newId] = copy;
    ProviderRepository.cache.set(app, cfg);
    await ProviderRepository.persist(app);
    return newId;
  }

  /**
   * 清理早期版本误把云端预设落为供应商实例的遗留项。云端预设现在只用于
   * “添加供应商”表单，用户创建的供应商与其密钥不会被这一步触及。
   */
  static async removeLegacyCloudProviders(): Promise<void> {
    const oldClaude: AppConfig = ProviderRepository.cache.get('claude') ?? emptyAppConfig();
    const oldCodex: AppConfig = ProviderRepository.cache.get('codex') ?? emptyAppConfig();
    const oldOpenCode: AppConfig = ProviderRepository.cache.get('opencode') ?? emptyAppConfig();
    const nextClaude: AppConfig = ProviderRepository.withoutLegacyCloudProviders(oldClaude);
    const nextCodex: AppConfig = ProviderRepository.withoutLegacyCloudProviders(oldCodex);
    const nextOpenCode: AppConfig = ProviderRepository.withoutLegacyCloudProviders(oldOpenCode);
    if (nextClaude === oldClaude && nextCodex === oldCodex && nextOpenCode === oldOpenCode) {
      return;
    }
    ProviderRepository.cache.set('claude', nextClaude);
    ProviderRepository.cache.set('codex', nextCodex);
    ProviderRepository.cache.set('opencode', nextOpenCode);
    try {
      await ProviderRepository.persistVisibleAppBatch();
    } catch (e) {
      ProviderRepository.cache.set('claude', oldClaude);
      ProviderRepository.cache.set('codex', oldCodex);
      ProviderRepository.cache.set('opencode', oldOpenCode);
      throw new Error('cloud provider persistence failed');
    }
  }

  private static withoutLegacyCloudProviders(current: AppConfig): AppConfig {
    const nextProviders: Record<string, Provider> = {};
    let changed: boolean = false;
    const oldIds: string[] = Object.keys(current.providers);
    for (const id of oldIds) {
      const existing: Provider = current.providers[id];
      if (!id.startsWith('cloud:')) {
        nextProviders[id] = existing;
      } else {
        changed = true;
      }
    }
    if (!changed) {
      return current;
    }
    let nextCurrent: string = current.current;
    if (nextProviders[nextCurrent] === undefined) {
      const ids: string[] = Object.keys(nextProviders);
      nextCurrent = ids.length > 0 ? ids[0] : '';
    }
    return { providers: nextProviders, current: nextCurrent };
  }
}
