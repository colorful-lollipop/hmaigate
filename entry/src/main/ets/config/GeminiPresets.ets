/**
 * Gemini 预设供应商配置模板 —— 移植自 cc-switch src/config/geminiProviderPresets.ts
 *
 * Gemini settingsConfig 形态为 { env: { GOOGLE_GEMINI_BASE_URL, GEMINI_MODEL, GEMINI_API_KEY? } }。
 */
import { ProviderPreset } from '../types/Preset';

/** Gemini settings.json 的 env 字段（超集） */
interface GeminiEnv {
  GOOGLE_GEMINI_BASE_URL?: string;
  GEMINI_MODEL?: string;
  GEMINI_API_KEY?: string;
}

/** Gemini settingsConfig 结构：{ env } */
interface GeminiSettings {
  env: GeminiEnv;
}

function mk(env: GeminiEnv): string {
  const cfg: GeminiSettings = { env: env };
  return JSON.stringify(cfg);
}

export const geminiProviderPresets: ProviderPreset[] = [
  {
    name: 'Google Official',
    websiteUrl: 'https://ai.google.dev/',
    apiKeyUrl: 'https://aistudio.google.com/apikey',
    settingsConfigJson: mk({}),
    category: 'official',
    partnerPromotionKey: 'google-official',
    theme: { icon: 'gemini', backgroundColor: '#4285F4', textColor: '#FFFFFF' },
    icon: 'gemini',
    iconColor: '#4285F4',
  },
  {
    name: 'Shengsuanyun',
    nameKey: 'providerForm.presets.shengsuanyun',
    websiteUrl: 'https://www.shengsuanyun.com/?from=CH_4HHXMRYF',
    apiKeyUrl: 'https://www.shengsuanyun.com/?from=CH_4HHXMRYF',
    settingsConfigJson: mk({
      GOOGLE_GEMINI_BASE_URL: 'https://router.shengsuanyun.com/api',
      GEMINI_MODEL: 'google/gemini-3.5-flash',
    }),
    category: 'aggregator',
    isPartner: true,
    partnerPromotionKey: 'shengsuanyun',
    icon: 'shengsuanyun',
  },
  {
    name: 'Unity2.ai',
    websiteUrl: 'https://unity2.ai',
    apiKeyUrl: 'https://unity2.ai/register?source=ccs',
    settingsConfigJson: mk({
      GOOGLE_GEMINI_BASE_URL: 'https://api.unity2.ai',
      GEMINI_MODEL: 'gemini-3.1-pro',
    }),
    category: 'aggregator',
    isPartner: true,
    partnerPromotionKey: 'unity2',
    icon: 'unity2',
  },
  {
    name: 'SubRouter',
    websiteUrl: 'https://subrouter.ai',
    apiKeyUrl: 'https://subrouter.ai/register?aff=l3ri',
    settingsConfigJson: mk({
      GOOGLE_GEMINI_BASE_URL: 'https://subrouter.ai/v1beta',
      GEMINI_MODEL: 'gemini-3.5-flash',
    }),
    category: 'aggregator',
    isPartner: true,
    partnerPromotionKey: 'subrouter',
    endpointCandidates: ['https://subrouter.ai/v1beta'],
    icon: 'subrouter',
  },
  {
    name: 'Qiniu',
    nameKey: 'providerForm.presets.qiniu',
    websiteUrl: 'https://s.qiniu.com/nMvAvy',
    apiKeyUrl: 'https://s.qiniu.com/nMvAvy',
    settingsConfigJson: mk({
      GOOGLE_GEMINI_BASE_URL: 'https://api.qnaigc.com/bypass/vertex',
      GEMINI_MODEL: 'gemini-3.1-pro-preview',
    }),
    category: 'aggregator',
    isPartner: true,
    partnerPromotionKey: 'qiniu',
    endpointCandidates: ['https://api.qnaigc.com/bypass/vertex', 'https://api.modelink.ai/bypass/vertex'],
    icon: 'qiniu',
  },
  {
    name: 'APIKEY.FUN',
    websiteUrl: 'https://apikey.fun',
    apiKeyUrl: 'https://apikey.fun/register?aff=CCSwitch',
    settingsConfigJson: mk({
      GOOGLE_GEMINI_BASE_URL: 'https://api.apikey.fun',
      GEMINI_API_KEY: '',
      GEMINI_MODEL: 'gemini-3.5-flash',
    }),
    category: 'third_party',
    isPartner: true,
    partnerPromotionKey: 'apikeyfun',
    endpointCandidates: ['https://api.apikey.fun', 'https://slb.apikey.fun'],
    icon: 'apikeyfun',
  },
];
