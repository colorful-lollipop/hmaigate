/**
 * PasswordLeakAuditService —— 原生异步密码泄露提醒的薄封装。
 *
 * C++ 返回的始终是脱敏元数据 JSON；此处再以固定枚举与长度上限过滤，避免异常
 * 原生返回值或损坏 preferences 进入 UI/持久化层。
 */
import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  PasswordLeakAlert,
  PasswordLeakAlertPage,
  PasswordLeakAlertStatus,
  PasswordLeakAuditStatus,
  PasswordLeakLocation,
  PasswordLeakSecretType,
  PasswordLeakSeverity,
} from '../types/PasswordLeakAudit';
import { strArrayJson } from '../types/Json';

const DOMAIN = 0x0000;
const TAG = 'PasswordLeakAudit';

function isSeverity(value: string): boolean {
  return value === 'high' || value === 'medium';
}

function isSecretType(value: string): boolean {
  return value === 'api_key' || value === 'password' || value === 'token' ||
    value === 'private_key' || value === 'credential';
}

function isLocation(value: string): boolean {
  return value === 'json_field' || value === 'env_assignment' ||
    value === 'code_text' || value === 'known_pattern';
}

function isAlertStatus(value: string): boolean {
  return value === 'new' || value === 'read';
}

function boundedText(value: ESObject, maxLength: number): string {
  if (typeof value !== 'string') {
    return '';
  }
  const text: string = value as string;
  return text.length <= maxLength ? text : '';
}

function parseAlert(value: ESObject): PasswordLeakAlert | null {
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  const id: string = boundedText(value['id'], 96);
  const timeMs: ESObject = value['timeMs'];
  const severity: string = boundedText(value['severity'], 16);
  const secretType: string = boundedText(value['secretType'], 32);
  const location: string = boundedText(value['location'], 32);
  const protocol: string = boundedText(value['protocol'], 32);
  const model: string = boundedText(value['model'], 128);
  const status: string = boundedText(value['status'], 16);
  if (id.length === 0 || typeof timeMs !== 'number' || (timeMs as number) <= 0 ||
    !isSeverity(severity) || !isSecretType(secretType) || !isLocation(location) ||
    !isAlertStatus(status)) {
    return null;
  }
  return {
    id: id,
    timeMs: timeMs as number,
    severity: severity as PasswordLeakSeverity,
    secretType: secretType as PasswordLeakSecretType,
    location: location as PasswordLeakLocation,
    protocol: protocol,
    model: model,
    status: status as PasswordLeakAlertStatus,
  };
}

function readNonNegativeInt(value: ESObject): number {
  if (typeof value !== 'number' || (value as number) < 0) {
    return 0;
  }
  return Math.floor(value as number);
}

export class PasswordLeakAuditService {
  static getStatus(): PasswordLeakAuditStatus {
    const fallback: PasswordLeakAuditStatus = {
      enabled: true,
      unreadCount: 0,
      todayCount: 0,
      lastAlertTimeMs: 0,
      droppedTasks: 0,
      truncatedTasks: 0,
      failedTasks: 0,
    };
    try {
      const raw: ESObject = JSON.parse(libentry.getPasswordLeakAuditStatus());
      if (typeof raw !== 'object' || raw === null) {
        return fallback;
      }
      const enabled: ESObject = raw['enabled'];
      return {
        enabled: typeof enabled === 'boolean' ? enabled as boolean : fallback.enabled,
        unreadCount: readNonNegativeInt(raw['unreadCount']),
        todayCount: readNonNegativeInt(raw['todayCount']),
        lastAlertTimeMs: readNonNegativeInt(raw['lastAlertTimeMs']),
        droppedTasks: readNonNegativeInt(raw['droppedTasks']),
        truncatedTasks: readNonNegativeInt(raw['truncatedTasks']),
        failedTasks: readNonNegativeInt(raw['failedTasks']),
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'native audit status unavailable');
      return fallback;
    }
  }

  static getAlerts(offset: number, limit: number): PasswordLeakAlertPage {
    const empty: PasswordLeakAlertPage = { alerts: [], total: 0 };
    try {
      const raw: ESObject = JSON.parse(libentry.getPasswordLeakAlerts(offset, limit));
      if (typeof raw !== 'object' || raw === null) {
        return empty;
      }
      const alerts: PasswordLeakAlert[] = [];
      const source: ESObject = raw['alerts'];
      if (Array.isArray(source)) {
        const items: ESObject[] = source as ESObject[];
        for (let i = 0; i < items.length; i++) {
          const parsed: PasswordLeakAlert | null = parseAlert(items[i]);
          if (parsed !== null) {
            alerts.push(parsed);
          }
        }
      }
      return { alerts: alerts, total: readNonNegativeInt(raw['total']) };
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'native audit alerts unavailable');
      return empty;
    }
  }

  static setEnabled(enabled: boolean): boolean {
    try {
      return libentry.setPasswordLeakAuditEnabled(enabled);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'native audit switch unavailable');
      return false;
    }
  }

  static markRead(ids: string[]): number {
    try {
      return libentry.markPasswordLeakAlertsRead(strArrayJson(ids));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'native audit mark-read unavailable');
      return 0;
    }
  }

  static clear(): void {
    try {
      libentry.clearPasswordLeakAlerts();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'native audit clear unavailable');
    }
  }

  /** preferences 回放/读取共用的固定结构解析。 */
  static parsePersistedAlerts(raw: string): PasswordLeakAlert[] {
    try {
      const value: ESObject = JSON.parse(raw);
      if (!Array.isArray(value)) {
        return [];
      }
      const items: ESObject[] = value as ESObject[];
      const alerts: PasswordLeakAlert[] = [];
      for (let i = 0; i < items.length; i++) {
        const parsed: PasswordLeakAlert | null = parseAlert(items[i]);
        if (parsed !== null) {
          alerts.push(parsed);
        }
      }
      return alerts;
    } catch (error) {
      return [];
    }
  }
}
