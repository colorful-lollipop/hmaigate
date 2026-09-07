/**
 * TrayService —— 系统托盘（鸿蒙 PC 状态栏）封装。
 *
 * 托盘常驻方案：在 PC 状态栏放入本应用图标（可见、可退出，满足鸿蒙 PC「后台进程需可见可退出」
 * 的保活前提）；关闭主窗口时 EntryAbility 走 onPrepareToTerminate → hideAbility（仅隐藏不销毁，
 * 进程与转发代理保持存活）；左键托盘 → showAbility 把主界面拉回前台。
 *
 * 说明：官方还提供把进程绑定到托盘图标的 holdStatusBar（processMode NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM）
 * 以获得更强的系统级保活；但该路径在当前模拟器上 startOptions 校验失败（16000067），且绑定进程为独立
 * 新进程、不与持有代理的 EntryAbility 共享 libentry.so 单例，意义有限，故暂未启用。当前依靠
 * 「托盘图标可见 + hideAbility 不销毁 Ability」实现常驻，已能满足窗口关闭后转发任务不中断的需求。
 */
import { statusBarManager } from '@kit.DesktopExtensionKit';
import image from '@ohos.multimedia.image';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'TrayService';
const TRAY_ICON = 'tray_icon.png';

/** 从 rawfile 读取图标并构造 PixelMap */
async function getPixelMap(name: string, ctx: common.Context): Promise<image.PixelMap> {
  const resourceMgr = ctx.resourceManager;
  const fileData = resourceMgr.getRawFileContentSync(name);
  const imageSource = image.createImageSource(fileData.buffer);
  return await imageSource.createPixelMap();
}

export class TrayService {
  /** 添加系统托盘图标 */
  static async loadStatusBar(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const icon: statusBarManager.StatusBarIcon = {
        white: await getPixelMap(TRAY_ICON, ctx),
        black: await getPixelMap(TRAY_ICON, ctx),
      };
      const operation: statusBarManager.QuickOperation = {
        abilityName: '', // 左键不弹窗，统一走 statusBarIconClick → showAbility
        title: '鸿蒙安全网关',
        height: 30,
        moduleName: 'entry',
      };
      const item: statusBarManager.StatusBarItem = {
        icons: icon,
        quickOperation: operation,
      };
      statusBarManager.addToStatusBar(ctx, item);
      hilog.info(DOMAIN, TAG, 'addToStatusBar success');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `addToStatusBar failed: ${JSON.stringify(error)}`);
    }
  }

  /** 注册左键托盘点击 → 显示主界面 */
  static registerShowOnIconClick(ctx: common.UIAbilityContext): void {
    try {
      statusBarManager.on('statusBarIconClick', () => {
        ctx.showAbility().then(() => {
          hilog.info(DOMAIN, TAG, 'tray click: showAbility success');
        }).catch((err: BusinessError) => {
          hilog.error(DOMAIN, TAG, `tray click showAbility failed: ${JSON.stringify(err)}`);
        });
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, `registerShowOnIconClick failed: ${JSON.stringify(error)}`);
    }
  }

  /** 从托盘移除（真正退出时调用） */
  static removeStatusBar(ctx: common.Context): void {
    try {
      statusBarManager.removeFromStatusBar(ctx);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `removeFromStatusBar failed: ${JSON.stringify(error)}`);
    }
  }
}
