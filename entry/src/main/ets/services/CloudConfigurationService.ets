/**
 * CloudConfigurationService —— 云端已发布配置拉取（HTTP(S) + ETag）。
 *
 * 本服务只负责传输、校验与快照持久化时机；云端供应商预设与原生安全引擎的实际
 * 应用由 GatewayController 编排。预设只服务于新增表单，不能修改本地供应商实例。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CloudConnectionStatus,
  CloudSnapshot,
  CloudSyncResult,
  normalizeCloudApiBaseUrl,
  parseCloudSnapshot,
} from '../types/CloudConfig';
import { SettingsRepository } from '../repository/SettingsRepository';

const DOMAIN = 0x0000;
const TAG = 'CloudConfigService';
const SYNC_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
const REQUEST_TIMEOUT_MS: number = 12000;

/** HTTP 协议字段需保留连字符；这是显式接口而非 Record 动态对象。 */
interface CloudPullHeaders {
  Accept: string;
  'X-AIGate-Device-Key': string;
  'If-None-Match': string;
}

export class CloudConfigurationService {
  private static syncing: boolean = false;

  static getConnectionStatus(): CloudConnectionStatus {
    return {
      apiBaseUrl: SettingsRepository.getCloudApiBaseUrl(),
      hasDeviceKey: SettingsRepository.getCloudDeviceKey().length > 0,
      configVersion: SettingsRepository.getCloudConfigVersion(),
      lastSuccessAt: SettingsRepository.getCloudLastSuccessAt(),
      lastError: SettingsRepository.getCloudLastError(),
    };
  }

  /** 保存前校验地址和设备密钥格式；密钥本身不写日志。 */
  static async saveConnection(rawApiBaseUrl: string, rawDeviceKey: string): Promise<string> {
    const apiBaseUrl: string = normalizeCloudApiBaseUrl(rawApiBaseUrl);
    const enteredKey: string = rawDeviceKey.trim();
    const deviceKey: string = enteredKey.length > 0 ? enteredKey : SettingsRepository.getCloudDeviceKey();
    if (apiBaseUrl.length === 0) {
      return '云端 API 地址必须是 HTTP 或 HTTPS 地址';
    }
    if (!/^agdk_[A-Za-z0-9-]+_[A-Za-z0-9_-]+$/.test(deviceKey)) {
      return '设备密钥格式无效';
    }
    await SettingsRepository.setCloudConnection(apiBaseUrl, deviceKey);
    return '';
  }

  static shouldSync(force: boolean): boolean {
    if (SettingsRepository.getCloudApiBaseUrl().length === 0 ||
      SettingsRepository.getCloudDeviceKey().length === 0) {
      return false;
    }
    if (force) {
      return true;
    }
    const lastSuccess: number = SettingsRepository.getCloudLastSuccessAt();
    return lastSuccess === 0 || Date.now() - lastSuccess >= SYNC_INTERVAL_MS;
  }

  /** 读取已持久化的最后有效快照，解析失败时返回 null 并不影响网关启动。 */
  static getCachedSnapshot(): CloudSnapshot | null {
    const raw: string = SettingsRepository.getCloudSnapshotJson();
    return raw.length > 0 ? parseCloudSnapshot(raw) : null;
  }

  /**
   * 拉取云端发布快照。304 不写入本地；网络/证书/校验错误只记录无敏感类别，
   * 调用者继续使用现有供应商和上一次成功快照。
   */
  static async pull(force: boolean): Promise<CloudSyncResult> {
    if (!CloudConfigurationService.shouldSync(force)) {
      return CloudConfigurationService.result('skipped', '未配置云端或尚未到同步时间');
    }
    if (CloudConfigurationService.syncing) {
      return CloudConfigurationService.result('skipped', '同步进行中');
    }
    CloudConfigurationService.syncing = true;
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: CloudPullHeaders = {
        Accept: 'application/json',
        'X-AIGate-Device-Key': SettingsRepository.getCloudDeviceKey(),
        'If-None-Match': SettingsRepository.getCloudEtag(),
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        usingCache: false,
        header: headers,
      };
      const endpoint: string = SettingsRepository.getCloudApiBaseUrl() + '/device/config';
      const response: http.HttpResponse = await request.request(endpoint, options);
      const code: number = response.responseCode as number;
      if (code === 304) {
        return CloudConfigurationService.result('not_modified', '云端配置已是最新');
      }
      if (code !== 200 || typeof response.result !== 'string') {
        const error: string = '云端返回 HTTP ' + code.toString();
        await SettingsRepository.setCloudLastError(error);
        return CloudConfigurationService.result('failed', error);
      }
      const rawSnapshot: string = response.result as string;
      const snapshot: CloudSnapshot | null = parseCloudSnapshot(rawSnapshot);
      if (snapshot === null) {
        await SettingsRepository.setCloudLastError('云端配置校验失败');
        return CloudConfigurationService.result('failed', '云端配置校验失败');
      }
      return {
        outcome: 'updated',
        message: '已获取云端配置版本 ' + snapshot.configVersion.toString(),
        snapshot: snapshot,
        eTag: CloudConfigurationService.readEtag(response.header),
        rawSnapshot: rawSnapshot,
      };
    } catch (e) {
      const error: string = '云端同步失败';
      hilog.warn(DOMAIN, TAG, `${error}: ${CloudConfigurationService.errorKind(e)}`);
      await SettingsRepository.setCloudLastError(error);
      return CloudConfigurationService.result('failed', error);
    } finally {
      CloudConfigurationService.syncing = false;
      request.destroy();
    }
  }

  /** 在预设目录与安全策略均完成热更新后提交快照元数据。 */
  static async commitAppliedSnapshot(result: CloudSyncResult): Promise<void> {
    if (result.outcome !== 'updated' || result.snapshot === null) {
      return;
    }
    await SettingsRepository.setAppliedCloudSnapshot(result.eTag, result.snapshot.configVersion,
      result.snapshot.securityPolicyVersion, result.rawSnapshot);
  }

  private static result(outcome: string, message: string): CloudSyncResult {
    return { outcome: outcome, message: message, snapshot: null, eTag: '', rawSnapshot: '' };
  }

  private static readEtag(headers: Object): string {
    const values: Record<string, ESObject> = headers as Record<string, ESObject>;
    const lower: ESObject = values['etag'];
    if (typeof lower === 'string') {
      return lower as string;
    }
    const upper: ESObject = values['ETag'];
    return typeof upper === 'string' ? upper as string : '';
  }

  /** 只记录错误类别，避免把地址、密钥或响应正文打入日志。 */
  private static errorKind(error: ESObject): string {
    if (error instanceof Error) {
      return error.name;
    }
    return 'request_error';
  }
}
