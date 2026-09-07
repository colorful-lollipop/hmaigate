export type PublishState = 'DRAFT' | 'PUBLISHED' | 'ARCHIVED';

export interface Channel {
  id: string;
  code: string;
  displayName: string;
  clientType: string;
  protocol: string;
  iconKey: string;
  documentationUrl?: string;
  /** 仅在端侧展示的默认位置提示，实际文件仍需用户授权选择。 */
  localConfigPathHint?: string;
  enabled: boolean;
  state: PublishState;
  configuration: Record<string, unknown>;
  draftVersion: number;
  publishedVersion: number;
  publishedAt?: string;
  updatedAt: string;
}

export interface Provider {
  id: string;
  code: string;
  displayName: string;
  channelCode: string;
  category: string;
  websiteUrl?: string;
  apiKeyUrl?: string;
  iconKey: string;
  iconColor?: string;
  partner: boolean;
  enabled: boolean;
  state: PublishState;
  configuration: Record<string, unknown>;
  draftVersion: number;
  publishedVersion: number;
  publishedAt?: string;
  updatedAt: string;
}

export interface SecurityPolicy {
  policy: Record<string, unknown>;
  draftVersion: number;
  publishedVersion: number;
  publishedAt?: string;
  updatedAt: string;
}

export interface ManagedDevice {
  id: string;
  displayName: string;
  status: 'ACTIVE' | 'REVOKED';
  createdAt: string;
  lastSeenAt?: string;
}

export interface IssuedDevice {
  device: ManagedDevice;
  deviceKey: string;
}

export interface RecentEvent {
  id: string;
  deviceId: string;
  eventType: string;
  severity: 'INFO' | 'WARN' | 'BLOCK' | 'ERROR';
  channelCode?: string;
  ruleId?: string;
  occurredAt?: string;
  receivedAt: string;
}

export interface Overview {
  configVersion: number;
  publishedChannels: number;
  publishedProviders: number;
  activeDevices: number;
  eventsLast24Hours: number;
  blockedLast24Hours: number;
  recentEvents: RecentEvent[];
}

export const DEFAULT_CHANNEL_CONFIGURATION: Record<string, unknown> = {
  schemaVersion: 1,
  configurationFormat: 'settings-json-env',
  fieldMap: {
    baseUrlField: 'ANTHROPIC_BASE_URL',
    apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
    modelField: 'ANTHROPIC_MODEL'
  }
};

export const DEFAULT_PROVIDER_CONFIGURATION: Record<string, unknown> = {
  schemaVersion: 1,
  settingsTemplate: {
    env: {
      ANTHROPIC_BASE_URL: '{{baseUrl}}',
      ANTHROPIC_AUTH_TOKEN: '{{apiKey}}',
      ANTHROPIC_MODEL: '{{model}}'
    }
  },
  endpointCandidates: [],
  defaultModel: ''
};
