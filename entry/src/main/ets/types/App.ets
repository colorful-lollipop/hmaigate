/**
 * 应用标识与可见性 —— 移植自 cc-switch src/lib/api/types.ts 与 src/types.ts (VisibleApps)
 *
 * 前端统一使用 AppId 作为应用标识（与后端命令参数 `app` 一致）。
 */

/** 受支持的 agent / 客户端类型（与 cc-switch 的 AppId 一致） */
export type AppId =
  | 'claude'
  | 'claude-desktop'
  | 'codex'
  | 'gemini'
  | 'opencode'
  | 'openclaw'
  | 'hermes';

/** 支持本地配置接管的 Agent 渠道。 */
export type LocalConfigApp = 'claude' | 'codex' | 'opencode';

/** 全部应用，顺序即 AppSwitcher 的展示顺序 */
export const APP_IDS: AppId[] = [
  'claude',
  'claude-desktop',
  'codex',
  'gemini',
  'opencode',
  'openclaw',
  'hermes',
];

/** 每个应用的展示名（对应 cc-switch appDisplayName） */
export function appDisplayName(app: AppId): string {
  switch (app) {
    case 'claude':
      return 'Claude Code';
    case 'claude-desktop':
      return 'Claude Desktop';
    case 'codex':
      return 'Codex';
    case 'gemini':
      return 'Gemini';
    case 'opencode':
      return 'OpenCode';
    case 'openclaw':
      return 'OpenClaw';
    case 'hermes':
      return 'Hermes';
    default:
      return app;
  }
}

/** 每个应用的图标标识（对应 cc-switch appIconName） */
export function appIconName(app: AppId): string {
  switch (app) {
    case 'claude':
    case 'claude-desktop':
      return 'claude';
    case 'codex':
      return 'openai';
    case 'gemini':
      return 'gemini';
    case 'opencode':
      return 'opencode';
    case 'openclaw':
      return 'openclaw';
    case 'hermes':
      return 'hermes';
    default:
      return 'claude';
  }
}

/** UI 渠道切换条暴露的渠道（多渠道管理），顺序即展示顺序。
 *  端口策略决策：单端口 + 活动渠道切换（cc-switch 式 UX）——同一时刻只有一个渠道的
 *  供应商生效，切换渠道即把该渠道的当前供应商热推给网关；C++ 侧渠道无关、零改动。 */
export const CHANNEL_APPS: LocalConfigApp[] = ['claude', 'codex', 'opencode'];

/** 宽容解析持久化的渠道 id；不在 CHANNEL_APPS 内的一律回退 'claude' */
export function toChannelApp(id: string): LocalConfigApp {
  for (const app of CHANNEL_APPS) {
    if (app === id) {
      return app;
    }
  }
  return 'claude';
}

/** 主页面显示的应用配置（对应 cc-switch VisibleApps）
 *  注：字段名使用 claudeDesktop（而非 'claude-desktop'），因为 ArkTS 不允许
 *  通过索引访问接口字段；AppId 字符串值仍为 'claude-desktop'。*/
export interface VisibleApps {
  claude: boolean;
  claudeDesktop: boolean;
  codex: boolean;
  gemini: boolean;
  opencode: boolean;
  openclaw: boolean;
  hermes: boolean;
}

/** 默认全部可见 */
export function defaultVisibleApps(): VisibleApps {
  return {
    claude: true,
    claudeDesktop: true,
    codex: true,
    gemini: true,
    opencode: true,
    openclaw: true,
    hermes: true,
  };
}
