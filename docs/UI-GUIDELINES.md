# UI 设计规范（M6 视觉打磨沉淀）

> 改 `.ets` UI 代码时按需查阅本文。权威事实来源仍是根目录 `AGENTS.md`；若本文与源码冲突，以源码为准。

- **质感来自克制，不用渐变**：卡面一律纯色 `card_bg`（曾尝试过运行态绿色渐变，用户反馈"不如纯色"后移除并定为规范）。商业感靠：柔和阴影（低透明度大半径，如 `#0A000000` radius 12）、半透明描边（运行/选中态用 `status_running_border` 这类带 alpha 的描边色，不用实体色 border）、间距节奏与文字层级。
- **圆角**：卡片 16、对话框 20、按钮 10、图标方块 12-14、药丸/分段控件全圆角（height/2）。
- **字号层级**：页面标题 20 Bold / 对话框标题 18 Bold / 卡片主标题 15-17 Medium / 正文 14 / 辅助说明 12 secondary / 统计大数字 20 Bold + 标签 11。
- **交互动效**（PC 鼠标优先）：可点元素统一 `hoverEffect(HoverEffect.Highlight)` + `clickEffect({level: ClickEffectLevel.LIGHT})`（小图标钮用 MIDDLE）；供应商卡片自定义 hover（onHover + 边框/阴影 + `.animation({duration:150})`）；对话框入场统一 `TransitionEffect.OPACITY.combine(scale 0.94).animation({duration:200})`（DialogShell/ConfigPanel 已各加一次，TransitionEffect 自带动画，调用方无需包 animateTo）。
- **状态驱动动效只做细腻的**：运行态呼吸点用递归 `getUIContext().animateTo` 往返（Index.pulseStep，运行中持续、停止自停）；注意呼吸环放大超槽会被 Stack 默认裁剪，需 `.clip(false)`。禁止花哨渐变动画。
- **@Builder 参数传递坑**：基本类型参数按值捕获不随状态刷新（统计格曾因此显示陈旧数字）——需要联动刷新的参数必须包成对象字面量按引用传（如 `StatCell($$: StatCellData)`）。
- **全局 animateTo 已 deprecated**：用 `this.getUIContext().animateTo`。
