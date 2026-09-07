/**
 * SectionWidgets —— 设置面板各分组共用的零组件与持久化句柄（R3 抽取）
 *
 * SectionTitle / FieldLabel / ToggleRow 原先在 ConfigPanel 内是 @Builder，
 * Add/EditProviderDialog 里又逐字复制了一份 FieldLabel/TextInputField，这里收敛。
 * ToggleRow 自读 @StorageLink 皮肤强调色（默认值走 types/Skin 常量兜底），
 * 调用方无需再传色值。
 */
import { DEFAULT_ACCENT } from '../../types/Skin';

/** 分组向上暴露给 ConfigPanel 壳的动作句柄（分组 aboutToAppear 时装配，壳的底部按钮/对话框据此触发） */
export class SectionPersistHandle {
  /** 持久化本分组管理的设置项（壳的「保存」按钮调用） */
  save: () => Promise<void> = async () => {};
  /** 重置本分组管理的设置项为默认（壳的「重置」按钮调用） */
  reset: () => void = () => {};
  /** 重读本分组列表数据（壳在对话框关闭后调用） */
  refresh: () => void = () => {};
}

/** 分组标题（大写、小字号、次级色） */
@Component
export struct SectionTitle {
  @Prop title: string = '';

  build() {
    Text(this.title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .textCase(TextCase.UpperCase)
      .letterSpacing(0.5)
      .textAlign(TextAlign.Start)
      .width('100%')
  }
}

/** 表单字段标签（小字号次级色，与 LabeledInput 的 label 同款样式） */
@Component
export struct FieldLabel {
  @Prop text: string = '';

  build() {
    Text(this.text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .margin({ bottom: 6 })
  }
}

/** 标签 + 开关行（开关尺寸统一 48x26；强调色自读 AppStorage） */
@Component
export struct ToggleRow {
  @Prop label: string = '';
  @Prop isOn: boolean = false;
  onToggle: (on: boolean) => void = (on: boolean) => {};
  @StorageLink('skinAccent') skinAccent: string = DEFAULT_ACCENT;

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(this.skinAccent)
        .switchPointColor(Color.White)
        .size({ width: 48, height: 26 })
        .onChange(this.onToggle)
    }
    .width('100%')
    .height(44)
  }
}
