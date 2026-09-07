/**
 * AboutSection —— 设置面板「关于」分组（R3 从 ConfigPanel 拆出）
 *
 * 版本号走 bundleManager（失败兜底空串不崩）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { SectionTitle } from '../common/SectionWidgets';

const DOMAIN = 0x0000;
const TAG = 'AboutSection';

@Component
export struct AboutSection {
  @State appVersion: string = '';

  aboutToAppear(): void {
    this.loadVersion().then(() => {
    }, () => {
    });
  }

  /** 读版本号（bundleManager），失败兜底空串不崩 */
  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.appVersion = info.versionName;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `getBundleInfoForSelf failed: ${JSON.stringify(err)}`);
    }
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '关于' })

      Column({ space: 6 }) {
        Row() {
          Text('AIGate 鸿蒙安全网关')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if (this.appVersion.length > 0) {
            Text('v' + this.appVersion)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')

        Text('运行在鸿蒙 PC 上的本地 LLM API 安全网关：转发请求到上游供应商，密钥由网关侧注入，请求/响应安全检测。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Text('License: MIT')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .border({ width: 0.5, color: $r('app.color.border') })
    }
    .width('100%')
  }
}
