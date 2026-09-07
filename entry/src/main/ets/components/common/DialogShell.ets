/**
 * DialogShell —— 模态对话框脚手架（R3 抽取）
 *
 * 遮罩（点击关闭）+ 居中卡片 + 标题栏（标题 + 关闭钮）+ 底部按钮行
 * （取消/确认，确认文案与颜色参数化），内容区由 @BuilderParam 槽提供。
 * 收敛原 ConfigPanel(RuleDialog/CustomRuleDialog)、Add/EditProviderDialog、
 * Index(DeleteConfirm) 五处逐字重复的骨架（~310 行）。
 *
 * 皮肤强调色由调用方组件读 @StorageLink 后以 confirmColor 传入（严格模式约束：
 * 各使用方自行持有 @StorageLink，默认值走 types/Skin 常量兜底）。
 *
 * 布局约定：cardHeight > 0 时内容区套 Scroll 并按 layoutWeight 撑满、底部按钮
 * 固定；cardHeight <= 0（默认）时高度随内容自适应、不套 Scroll，调用方可在内容
 * 槽内自管高度/滚动（如 AddProviderDialog 按模式切换高度）。
 */
import { IconChevronLeft, IconClose } from '../Icons';
import { DEFAULT_ACCENT } from '../../types/Skin';

@Component
export struct DialogShell {
  @Prop title: string = ''; // 空串 = 不渲染标题栏（内容由调用方自带头部）
  @Prop showClose: boolean = true;
  @Prop showBack: boolean = false; // 标题栏左侧返回钮（AddProviderDialog 表单步回预设步）
  @Prop cardWidth: number = 460;
  @Prop cardHeight: number = 0;
  @Prop showFooter: boolean = false;
  @Prop showCancel: boolean = true;
  @Prop cancelText: string = '取消';
  @Prop confirmText: string = '保存';
  @Prop stretchButtons: boolean = false; // 取消/确认等宽拉伸（删除确认类），否则右对齐
  /** 卡片底色；空串 = 默认 page_bg（删除确认类对话框传 panel_bg 保持原样） */
  cardBg: ResourceColor = '';
  confirmColor: ResourceColor = DEFAULT_ACCENT;
  onDismiss: () => void = () => {};
  onConfirm: () => void = () => {};
  onBack: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
    Column() {
    }
  }

  @Builder
  TitleBar() {
    Row() {
      if (this.showBack) {
        Stack() {
          IconChevronLeft({ size: 20, color: $r('app.color.text_secondary') })
        }
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.button_secondary'))
        .borderRadius(10)
        .margin({ right: 8 })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onBack())
      }

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.showClose) {
        Stack() {
          IconClose({ size: 18, color: $r('app.color.text_secondary') })
        }
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.button_secondary'))
        .borderRadius(10)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onDismiss())
      }
    }
    .width('100%')
    .padding({ left: 20, right: 16, top: 16, bottom: 12 })
  }

  @Builder
  Footer() {
    Row({ space: 12 }) {
      if (!this.stretchButtons) {
        Blank()
      }
      if (this.showCancel) {
        Button(this.cancelText)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.button_secondary'))
          .borderRadius(10)
          .padding({ left: 20, right: 20 })
          .layoutWeight(this.stretchButtons ? 1 : 0)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => this.onDismiss())
      }
      Button(this.confirmText)
        .height(40)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor(this.confirmColor)
        .borderRadius(10)
        .padding({ left: 24, right: 24 })
        .layoutWeight(this.stretchButtons ? 1 : 0)
        .hoverEffect(HoverEffect.Highlight)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => this.onConfirm())
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 16, top: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩，点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
        .onClick(() => this.onDismiss())

      Column() {
        if (this.title.length > 0) {
          this.TitleBar()
        }
        if (this.cardHeight > 0) {
          Scroll() {
            this.content()
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        } else {
          this.content()
        }
        if (this.showFooter) {
          this.Footer()
        }
      }
      .width(this.cardWidth)
      .height(this.cardHeight > 0 ? this.cardHeight : undefined)
      .backgroundColor(this.cardBg === '' ? $r('app.color.page_bg') : this.cardBg)
      .borderRadius(20)
      .shadow({ radius: 32, color: '#33000000', offsetX: 0, offsetY: 10 })
      // 对话框统一入场/退场：淡入 + 轻微缩放（TransitionEffect 自带动画，无需调用方包 animateTo）
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
        .animation({ duration: 200, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
  }
}
