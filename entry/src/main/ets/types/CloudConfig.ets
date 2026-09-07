/**
 * CloudConfig —— 云端发布快照的端侧契约与宽容解析。
 *
 * 云端只下发已发布的渠道、供应商模板与安全策略；真实 API Key 始终留在
 * ProviderRepository / preferences，绝不放入快照或回传云端。
 */
import { CHANNEL_APPS, LocalConfigApp } from './App';
import { EnvKeySet, envKeysForApp } from './EnvKeys';
import { parseStringArray } from './Json';

const MAX_TEMPLATE_ITEMS: number = 64;
const MAX_TOKEN_LENGTH: number = 512;

/** 已通过端侧白名单与 schema 校验的云端渠道。 */
export interface CloudChannel {
  code: LocalConfigApp;
  displayName: string;
  clientType: string;
  protocol: string;
  iconKey: string;
  /** 云端仅提供展示位置提示；实际文件仍由用户通过 picker 授权选择。 */
  localConfigPathHint: string;
  revision: number;
}

/** 已通过模板约束校验的云端供应商预设。 */
export interface CloudProviderPreset {
  code: string;
  displayName: string;
  channelCode: LocalConfigApp;
  category: string;
  websiteUrl: string;
  apiKeyUrl: string;
  iconKey: string;
  iconColor: string;
  partner: boolean;
  revision: number;
  endpoint: string;
  defaultModel: string;
}

/** 云端安全策略单条规则。BLOCK/WARN 的原生动作映射仍以 C++ 为准。 */
export interface CloudSecurityRule {
  ruleId: string;
  action: string;
  keywords: string[];
  patterns: string[];
}

/** 已校验的云端安全策略。 */
export interface CloudSecurityPolicy {
  requestScanEnabled: boolean;
  responseScanEnabled: boolean;
  rules: CloudSecurityRule[];
}

/** 设备配置接口返回的完整发布快照。 */
export interface CloudSnapshot {
  configVersion: number;
  securityPolicyVersion: number;
  channels: CloudChannel[];
  providerPresets: CloudProviderPreset[];
  securityPolicy: CloudSecurityPolicy;
}

/** 云端同步的结果，供 UI 展示并由控制器决定何时提交快照。 */
export interface CloudSyncResult {
  outcome: string; // 'updated' | 'not_modified' | 'skipped' | 'failed'
  message: string;
  snapshot: CloudSnapshot | null;
  eTag: string;
  rawSnapshot: string;
}

/** 设置页展示的云连接状态；deviceKey 只暴露是否已配置，绝不返回明文。 */
export interface CloudConnectionStatus {
  apiBaseUrl: string;
  hasDeviceKey: boolean;
  configVersion: number;
  lastSuccessAt: number;
  lastError: string;
}

function asObject(value: ESObject): ESObject | null {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
    return value as ESObject;
  }
  return null;
}

function stringField(value: ESObject, key: string): string {
  const raw: ESObject = value[key];
  return typeof raw === 'string' ? raw as string : '';
}

function numberField(value: ESObject, key: string): number {
  const raw: ESObject = value[key];
  return typeof raw === 'number' && Number.isFinite(raw as number) ? raw as number : -1;
}

function boolField(value: ESObject, key: string, fallback: boolean): boolean {
  const raw: ESObject = value[key];
  return typeof raw === 'boolean' ? raw as boolean : fallback;
}

function isSupportedApp(code: string): boolean {
  for (const app of CHANNEL_APPS) {
    if (app === code) {
      return true;
    }
  }
  return false;
}

function asChannelApp(code: string): LocalConfigApp | null {
  if (isSupportedApp(code)) {
    return code as LocalConfigApp;
  }
  return null;
}

/** 云下发的供应商上游端点必须使用 HTTPS。 */
export function isHttpsUrl(raw: string): boolean {
  return /^https:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:\/[A-Za-z0-9._~:/?#[\]@!$&'()*+,;=%-]*)?$/.test(raw);
}

/** 当前开发部署允许 HTTP；生产环境应填写 HTTPS 云 API 前缀。 */
export function isCloudApiUrl(raw: string): boolean {
  return /^https?:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:\/[A-Za-z0-9._~:/?#[\]@!$&'()*+,;=%-]*)?$/.test(raw);
}

/** 设备设置填写的是 API 前缀，例如 http://config.example.com/api/v1。 */
export function normalizeCloudApiBaseUrl(raw: string): string {
  const value: string = raw.trim().replace(/\/+$/, '');
  return isCloudApiUrl(value) ? value : '';
}

function validToken(value: string): boolean {
  return value.length > 0 && value.length <= MAX_TOKEN_LENGTH;
}

function parseBoundedStrings(value: ESObject): string[] | null {
  const parsed: string[] = parseStringArray(value);
  if (!Array.isArray(value) || parsed.length !== (value as ESObject[]).length || parsed.length > MAX_TEMPLATE_ITEMS) {
    return null;
  }
  for (const item of parsed) {
    if (!validToken(item)) {
      return null;
    }
  }
  return parsed;
}

function templateEnvMatches(app: LocalConfigApp, template: ESObject): boolean {
  const env: ESObject | null = asObject(template['env']);
  if (env === null) {
    return false;
  }
  const keys: EnvKeySet = envKeysForApp(app);
  return stringField(env, keys.baseUrlKey) === '{{baseUrl}}' &&
    stringField(env, keys.apiKeyField) === '{{apiKey}}' &&
    stringField(env, keys.modelKey) === '{{model}}';
}

function codexTemplateMatches(template: ESObject): boolean {
  const auth: ESObject | null = asObject(template['auth']);
  const config: string = stringField(template, 'config');
  return auth !== null && stringField(auth, 'OPENAI_API_KEY') === '{{apiKey}}' &&
    config.indexOf('{{baseUrl}}') >= 0 && config.indexOf('{{model}}') >= 0;
}

function parseChannel(value: ESObject): CloudChannel | null {
  const code: LocalConfigApp | null = asChannelApp(stringField(value, 'code'));
  const config: ESObject | null = asObject(value['configuration']);
  const displayName: string = stringField(value, 'displayName');
  if (code === null || config === null || numberField(config, 'schemaVersion') !== 1 ||
    !validToken(displayName) || stringField(value, 'clientType') !== code) {
    return null;
  }
  const revision: number = numberField(value, 'revision');
  if (revision < 0) {
    return null;
  }
  return {
    code: code,
    displayName: displayName,
    clientType: stringField(value, 'clientType'),
    protocol: stringField(value, 'protocol'),
    iconKey: stringField(value, 'iconKey'),
    localConfigPathHint: validToken(stringField(value, 'localConfigPathHint'))
      ? stringField(value, 'localConfigPathHint') : '',
    revision: revision,
  };
}

function parseProvider(value: ESObject, channels: Map<string, CloudChannel>): CloudProviderPreset | null {
  const channelCode: LocalConfigApp | null = asChannelApp(stringField(value, 'channelCode'));
  const config: ESObject | null = asObject(value['configuration']);
  const code: string = stringField(value, 'code');
  const displayName: string = stringField(value, 'displayName');
  if (channelCode === null || !channels.has(channelCode) || config === null ||
    numberField(config, 'schemaVersion') !== 1 || !validToken(code) || !validToken(displayName)) {
    return null;
  }
  const template: ESObject | null = asObject(config['settingsTemplate']);
  if (template === null || (channelCode === 'codex'
    ? !codexTemplateMatches(template)
    : !templateEnvMatches(channelCode, template))) {
    return null;
  }
  const endpoints: string[] | null = parseBoundedStrings(config['endpointCandidates']);
  const defaultModel: string = stringField(config, 'defaultModel');
  const revision: number = numberField(value, 'revision');
  if (endpoints === null || endpoints.length === 0 || !isHttpsUrl(endpoints[0]) ||
    !validToken(defaultModel) || revision < 0) {
    return null;
  }
  return {
    code: code,
    displayName: displayName,
    channelCode: channelCode,
    category: stringField(value, 'category'),
    websiteUrl: stringField(value, 'websiteUrl'),
    apiKeyUrl: stringField(value, 'apiKeyUrl'),
    iconKey: stringField(value, 'iconKey'),
    iconColor: stringField(value, 'iconColor'),
    partner: boolField(value, 'partner', false),
    revision: revision,
    endpoint: endpoints[0],
    defaultModel: defaultModel,
  };
}

function parseSecurityRule(value: ESObject): CloudSecurityRule | null {
  const ruleId: string = stringField(value, 'ruleId');
  const action: string = stringField(value, 'action');
  const keywords: string[] | null = parseBoundedStrings(value['keywords']);
  const patterns: string[] | null = parseBoundedStrings(value['patterns']);
  if (!validToken(ruleId) || (action !== 'ALLOW' && action !== 'WARN' && action !== 'BLOCK') ||
    keywords === null || patterns === null) {
    return null;
  }
  return { ruleId: ruleId, action: action, keywords: keywords, patterns: patterns };
}

/**
 * 解析完整快照。未知渠道/无效供应商按端侧白名单跳过，但基础响应、策略 schema
 * 或已声明规则结构不合法时整体拒绝，确保不会将半套策略写入本地。
 */
export function parseCloudSnapshot(raw: string): CloudSnapshot | null {
  try {
    const root: ESObject = JSON.parse(raw);
    const channelsRaw: ESObject = root['channels'];
    const providerPresetsRaw: ESObject = root['providerPresets'];
    const policyRaw: ESObject | null = asObject(root['securityPolicy']);
    const configVersion: number = numberField(root, 'configVersion');
    const policyVersion: number = numberField(root, 'securityPolicyVersion');
    if (!Array.isArray(channelsRaw) || !Array.isArray(providerPresetsRaw) || policyRaw === null ||
      configVersion < 0 || policyVersion < 0 || numberField(policyRaw, 'schemaVersion') !== 1) {
      return null;
    }

    const channels: CloudChannel[] = [];
    const channelMap: Map<string, CloudChannel> = new Map<string, CloudChannel>();
    const channelItems: ESObject[] = channelsRaw as ESObject[];
    for (let i = 0; i < channelItems.length; i++) {
      const item: ESObject | null = asObject(channelItems[i]);
      if (item === null) {
        continue;
      }
      const channel: CloudChannel | null = parseChannel(item);
      if (channel !== null && !channelMap.has(channel.code)) {
        channels.push(channel);
        channelMap.set(channel.code, channel);
      }
    }

    const providerPresets: CloudProviderPreset[] = [];
    const providerCodes: Map<string, boolean> = new Map<string, boolean>();
    const providerItems: ESObject[] = providerPresetsRaw as ESObject[];
    for (let i = 0; i < providerItems.length; i++) {
      const item: ESObject | null = asObject(providerItems[i]);
      if (item === null) {
        continue;
      }
      const provider: CloudProviderPreset | null = parseProvider(item, channelMap);
      if (provider !== null) {
        const key: string = provider.channelCode + ':' + provider.code;
        if (!providerCodes.has(key)) {
          providerPresets.push(provider);
          providerCodes.set(key, true);
        }
      }
    }

    const rulesRaw: ESObject = policyRaw['rules'];
    if (!Array.isArray(rulesRaw)) {
      return null;
    }
    const rules: CloudSecurityRule[] = [];
    const ruleItems: ESObject[] = rulesRaw as ESObject[];
    for (let i = 0; i < ruleItems.length; i++) {
      const item: ESObject | null = asObject(ruleItems[i]);
      if (item === null) {
        return null;
      }
      const rule: CloudSecurityRule | null = parseSecurityRule(item);
      if (rule === null) {
        return null;
      }
      rules.push(rule);
    }
    return {
      configVersion: configVersion,
      securityPolicyVersion: policyVersion,
      channels: channels,
      providerPresets: providerPresets,
      securityPolicy: {
        requestScanEnabled: boolField(policyRaw, 'requestScanEnabled', true),
        responseScanEnabled: boolField(policyRaw, 'responseScanEnabled', true),
        rules: rules,
      },
    };
  } catch (e) {
    return null;
  }
}
