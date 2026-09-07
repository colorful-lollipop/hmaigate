/**
 * ThemeController —— 外观编排层（M5：主题模式 + 皮肤）
 *
 * 对齐 GatewayController 的静态单例风格，可被 @Component 直接调用。
 * 持久化走 SettingsRepository（themeMode/skinId），即时生效分两条路：
 *  - 主题模式：ApplicationContext.setColorMode（系统据此在 base/dark 资源目录间切换）；
 *  - 皮肤：把色值写进 AppStorage（设计说明见 types/Skin.ets）。
 * 当前生效的亮暗态（themeIsDark，含「跟随系统」时的系统值）也写入 AppStorage，
 * 供需要暗色变体的组件消费；系统模式变化由 EntryAbility.onConfigurationUpdate 刷新。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsRepository } from '../repository/SettingsRepository';
import { SkinPack, SKINS, skinById } from '../types/Skin';

const DOMAIN = 0x0000;
const TAG = 'ThemeController';

/** 主题模式可选项（外观分组的药丸分段控件数据源；value 与 SettingsRepository.themeMode 取值一致） */
export interface ThemeModeItem {
  value: string; // 'system' | 'light' | 'dark'
  label: string;
}

export const THEME_MODES: ThemeModeItem[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '亮色' },
  { value: 'dark', label: '暗色' },
];

export class ThemeController {
  /** applyFromSettings 时缓存的 ApplicationContext，供运行中 setColorMode 用 */
  private static appContext: common.ApplicationContext | null = null;

  /** 启动回放（EntryAbility 在 SettingsRepository.load() 完成后调用一次） */
  static applyFromSettings(context: common.UIAbilityContext): void {
    try {
      ThemeController.appContext = context.getApplicationContext();
      ThemeController.applyColorMode(ThemeController.toColorMode(SettingsRepository.getThemeMode()));
      ThemeController.applySkin(skinById(SettingsRepository.getSkinId()));
      AppStorage.setOrCreate('themeIsDark',
        context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `applyFromSettings failed: ${JSON.stringify(err)}`);
    }
  }

  // —— 主题模式 ——
  static getThemeMode(): string {
    return SettingsRepository.getThemeMode();
  }

  /** 切换主题模式：持久化 + 立即 setColorMode；上下文未就绪时记日志不崩 */
  static async setThemeMode(mode: string): Promise<void> {
    await SettingsRepository.setThemeMode(mode);
    ThemeController.applyColorMode(ThemeController.toColorMode(mode));
  }

  // —— 皮肤 ——
  static getSkinId(): string {
    return SettingsRepository.getSkinId();
  }

  static getSkins(): SkinPack[] {
    return SKINS;
  }

  /** 切换皮肤：持久化 + 立即写 AppStorage（@StorageLink 组件自动刷新） */
  static async setSkinId(id: string): Promise<void> {
    await SettingsRepository.setSkinId(id);
    ThemeController.applySkin(skinById(id));
  }

  private static toColorMode(mode: string): ConfigurationConstant.ColorMode {
    if (mode === 'light') {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    if (mode === 'dark') {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // 跟随系统
  }

  private static applyColorMode(mode: ConfigurationConstant.ColorMode): void {
    const ctx: common.ApplicationContext | null = ThemeController.appContext;
    if (ctx === null) {
      hilog.warn(DOMAIN, TAG, 'appContext not ready; color mode not applied');
      return;
    }
    try {
      ctx.setColorMode(mode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `setColorMode failed: ${JSON.stringify(err)}`);
    }
  }

  /** 只推强调色两个键；语义色（success/warn）刻意不动，状态指示灯保持语义 */
  private static applySkin(skin: SkinPack): void {
    AppStorage.setOrCreate('skinAccent', skin.accent);
    AppStorage.setOrCreate('skinAccentTint', skin.accentTint);
  }
}
