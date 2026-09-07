/**
 * 密码泄露提醒的脱敏数据契约。
 *
 * 这些类型刻意不包含请求正文、字段值、命中片段或密钥后缀；历史持久化只能使用
 * PasswordLeakAlert 的固定元数据字段。
 */

export type PasswordLeakSeverity = 'high' | 'medium';
export type PasswordLeakSecretType = 'api_key' | 'password' | 'token' | 'private_key' | 'credential';
export type PasswordLeakLocation = 'json_field' | 'env_assignment' | 'code_text' | 'known_pattern';
export type PasswordLeakAlertStatus = 'new' | 'read';

export interface PasswordLeakAlert {
  id: string;
  timeMs: number;
  severity: PasswordLeakSeverity;
  secretType: PasswordLeakSecretType;
  location: PasswordLeakLocation;
  protocol: string;
  model: string;
  status: PasswordLeakAlertStatus;
}

export interface PasswordLeakAuditStatus {
  enabled: boolean;
  unreadCount: number;
  todayCount: number;
  lastAlertTimeMs: number;
  droppedTasks: number;
  truncatedTasks: number;
  failedTasks: number;
}

export interface PasswordLeakAlertPage {
  alerts: PasswordLeakAlert[];
  total: number;
}

/** 供安全设置页面一次性渲染的状态快照。 */
export interface PasswordLeakAuditViewState {
  enabled: boolean;
  unreadCount: number;
  todayCount: number;
  lastAlertTimeMs: number;
  alerts: PasswordLeakAlert[];
}
