/**
 * 预设注册表 —— 按 AppId 汇总各应用的预设供应商列表
 */
import { AppId } from '../types/App';
import { ProviderPreset } from '../types/Preset';
import { claudeProviderPresets } from './ClaudePresets';
import { codexProviderPresets } from './CodexPresets';
import { geminiProviderPresets } from './GeminiPresets';
import { openCodeProviderPresets } from './OpenCodePresets';

/** 获取指定应用的预设列表（未专门维护的应用返回 Claude 预设作为通用模板） */
export function getPresetsForApp(app: AppId): ProviderPreset[] {
  switch (app) {
    case 'claude':
    case 'claude-desktop':
      return claudeProviderPresets;
    case 'codex':
      return codexProviderPresets;
    case 'gemini':
      return geminiProviderPresets;
    case 'opencode':
      return openCodeProviderPresets;
    case 'openclaw':
    case 'hermes':
      // 这些应用在 cc-switch 中有独立预设；移植版暂复用 Claude 通用模板
      return claudeProviderPresets;
    default:
      return claudeProviderPresets;
  }
}

/** 是否为 Claude 系（env 形态的 settingsConfig） */
export function isClaudeLikeApp(app: AppId): boolean {
  return app === 'claude' || app === 'claude-desktop' || app === 'gemini' || app === 'opencode' || app === 'openclaw' || app === 'hermes';
}
