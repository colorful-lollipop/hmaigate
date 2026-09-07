/**
 * LabeledInput —— 字段标签 + 输入框行（R3 抽取）
 *
 * 收敛 ConfigPanel / AddProviderDialog / EditProviderDialog 里逐字重复的
 * FieldLabel + TextInputField 组合；label 样式与 common/SectionWidgets 的
 * FieldLabel 一致（需要纯标签时直接用 FieldLabel）。
 */
import { FieldLabel } from './SectionWidgets';

@Component
export struct LabeledInput {
  @Prop label: string = '';
  @Prop placeholder: string = '';
  @Prop value: string = '';
  @Prop inputType: InputType = InputType.Normal;
  onInput: (v: string) => void = (v: string) => {};

  build() {
    Column() {
      FieldLabel({ text: this.label })
      TextInput({ placeholder: this.placeholder, text: this.value })
        .type(this.inputType)
        .width('100%')
        .height(42)
        .fontSize(14)
        .backgroundColor($r('app.color.input_bg'))
        .borderRadius(10)
        .onChange(this.onInput)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
