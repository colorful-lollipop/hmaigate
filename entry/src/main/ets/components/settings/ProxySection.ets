/**
 * ProxySection —— 设置面板「代理设置」分组（R3 从 ConfigPanel 拆出）
 *
 * 监听地址/端口/自动启动的本地编辑态 + 保存/重置逻辑；持久化走
 * SettingsRepository，由壳（ConfigPanel）的底部按钮经 handle 触发。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsRepository } from '../../repository/SettingsRepository';
import { SectionPersistHandle, SectionTitle, ToggleRow } from '../common/SectionWidgets';

const DOMAIN = 0x0000;
const TAG = 'ProxySection';

const DEFAULT_HOST: string = '127.0.0.1';
const DEFAULT_PORT: number = 8080;

@Component
export struct ProxySection {
  @State proxyHost: string = DEFAULT_HOST;
  @State proxyPort: number = DEFAULT_PORT;
  @State proxyAutoStart: boolean = false;
  /** 壳传入的动作句柄，aboutToAppear 时装配 save/reset */
  handle: SectionPersistHandle = new SectionPersistHandle();

  aboutToAppear(): void {
    this.proxyHost = SettingsRepository.getProxyHost();
    this.proxyPort = SettingsRepository.getProxyPort();
    this.proxyAutoStart = SettingsRepository.getProxyAutoStart();
    this.handle.save = async () => {
      await SettingsRepository.setProxy(this.proxyHost, this.proxyPort);
      await SettingsRepository.setAutoStart(this.proxyAutoStart);
    };
    this.handle.reset = () => {
      this.proxyHost = DEFAULT_HOST;
      this.proxyPort = DEFAULT_PORT;
      this.proxyAutoStart = false;
      hilog.info(DOMAIN, TAG, 'proxy config reset (local)');
    };
  }

  build() {
    Column({ space: 12 }) {
      SectionTitle({ title: '代理设置' })

      Column({ space: 4 }) {
        Row() {
          Text('监听地址')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(90)
          TextInput({ placeholder: '请输入监听地址', text: this.proxyHost })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius(10)
            .onChange((value: string) => this.proxyHost = value)
        }
        .width('100%')
        .height(44)

        Divider().color($r('app.color.divider')).strokeWidth(0.5)

        Row() {
          Text('监听端口')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width(90)
          TextInput({ placeholder: '请输入监听端口', text: this.proxyPort.toString() })
            .type(InputType.Number)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.input_bg'))
            .borderRadius(10)
            .onChange((value: string) => this.proxyPort = parseInt(value) || DEFAULT_PORT)
        }
        .width('100%')
        .height(44)

        Divider().color($r('app.color.divider')).strokeWidth(0.5)

        ToggleRow({
          label: '自动启动', isOn: this.proxyAutoStart, onToggle: (isOn: boolean) => {
            this.proxyAutoStart = isOn;
          }
        })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .border({ width: 0.5, color: $r('app.color.border') })
    }
    .width('100%')
  }
}
