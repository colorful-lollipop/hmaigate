/**
 * AIGate 应用入口Ability
 * 负责应用生命周期管理
 */
import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProviderRepository } from '../repository/ProviderRepository';
import { SettingsRepository } from '../repository/SettingsRepository';
import { TrayService } from '../services/TrayService';
import { LocalConfigService } from '../services/LocalConfigService';
import { PluginService } from '../services/PluginService';
import { ThemeController } from '../app/ThemeController';
import { GatewayController } from '../app/GatewayController';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');

    try {
      // 先按跟随系统设置颜色模式；持久化的主题偏好在 SettingsRepository.load()
      // 完成后由 ThemeController.applyFromSettings 回放校正（见下）
      this.context.getApplicationContext().setColorMode(
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      );

      // 初始化数据层（preferences 单一数据源；注入 ability context）
      // 本地仓储先就绪；云端同步在其后后台发起，不能阻塞首页首帧。
      ProviderRepository.init(this.context);
      SettingsRepository.init(this.context);
      GatewayController.init().then(() => {
        // M5：回放主题模式（setColorMode）与皮肤（AppStorage），并初始化 themeIsDark 标记
        ThemeController.applyFromSettings(this.context);
        GatewayController.syncCloudConfig(false).then(() => {
        }, () => {
        });
      }, () => {
      });

      // 系统托盘：放托盘图标 → 注册左键点击(showAbility)；关闭窗口走 hideAbility 常驻
      TrayService.loadStatusBar(this.context).then(() => {
        TrayService.registerShowOnIconClick(this.context);
      });

      // 本地 Agent 配置管理器（picker/读写需 ability context；重启时重新激活 URI 授权）
      LocalConfigService.init(this.context);
      LocalConfigService.activatePersisted().then(() => {
      }, () => {
      });

      // M2 动态库插件：扫描加载 filesDir/plugins 下的 .so。
      // 鸿蒙沙箱限制：第三方应用只能 dlopen 自己沙箱内/随包的动态库，
      // 插件目录因此固定在应用 filesDir 下；目录不存在/为空就跳过（不算错误）。
      const pluginDir = `${this.context.filesDir}/plugins`;
      if (fs.accessSync(pluginDir)) {
        PluginService.loadPlugins(pluginDir).then((count: number) => {
          hilog.info(DOMAIN, TAG, `plugins loaded from sandbox dir: %{public}d`, count);
        }, (err: Error) => {
          hilog.error(DOMAIN, TAG, `loadPlugins failed: ${JSON.stringify(err)}`);
        });
      }

      hilog.info(DOMAIN, TAG, 'AIGate initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Initialization error: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  // 系统亮暗切换（或 setColorMode 生效）时刷新 themeIsDark，供暗色变体组件消费（M5）
  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('themeIsDark',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    // 加载主页面
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Content loaded successfully');
    });

    // 拦截窗口关闭按钮(X)：点关闭不销毁，改为隐藏 → 进程与转发代理保活、托盘常驻
    // resolve(true) 表示阻止关闭窗口。
    try {
      const mainWindow = windowStage.getMainWindowSync();
      // 自由窗口标题栏沉浸：隐藏标题栏(应用图标+名称)，保留右上角三键，
      // 页面扩展至原标题栏区域；三键区高度经 AppStorage 交给页面做顶部避让。
      this.setupImmersiveTitleBar(mainWindow).then(() => {
      }, () => {
      });
      mainWindow.on('windowWillClose', (): Promise<boolean> => {
        hilog.info(DOMAIN, TAG, 'windowWillClose → hideAbility (keep resident)');
        this.context.hideAbility();
        return Promise.resolve(true);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, `window decor/close setup failed: ${JSON.stringify(err)}`);
    }
  }

  // 隐藏自由窗口标题栏；取右上角三键区高度写入 AppStorage 供页面避让。
  // setWindowDecorVisible 仅在自由窗口（有标题栏）下生效——先用 isInFreeWindowMode() 守卫，
  // 全屏模式直接跳过（否则报 1300002）。module.json5 已声明 supportWindowMode 含 "floating"。
  private async setupImmersiveTitleBar(mainWindow: window.Window): Promise<void> {
    if (!mainWindow.isInFreeWindowMode()) {
      AppStorage.setOrCreate('decorTopInset', 0); // 全屏模式：无标题栏可隐藏，不加 padding
      hilog.info(DOMAIN, TAG, 'not in free window mode; skip immersive title bar');
      return;
    }
    let decorHidden = false;
    try {
      await mainWindow.setWindowDecorVisible(false);
      decorHidden = true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `setWindowDecorVisible failed: ${JSON.stringify(e)}`);
    }
    if (decorHidden) {
      try {
        const rect = await mainWindow.getTitleButtonRect();
        AppStorage.setOrCreate('decorTopInset', rect.height);
      } catch (e) {
        AppStorage.setOrCreate('decorTopInset', 40); // 隐藏成功但取不到三键高度，兜底
      }
    } else {
      AppStorage.setOrCreate('decorTopInset', 0);
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    // 距上次成功超过 6 小时才请求；失败保留最后有效快照，不影响本地网关。
    GatewayController.syncCloudConfig(false).then(() => {
    }, () => {
    });
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onNewWant');
  }
}
