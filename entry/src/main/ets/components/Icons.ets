/**
 * Icons —— 统一图标库
 *
 * 使用 ArkUI Path 绘制的轻量矢量图标，避免依赖 emoji，保持鸿蒙 PC 精致感。
 * 所有图标默认 24×24 画布，支持尺寸与颜色覆盖。
 */

export interface IconProps {
  size?: number;
  color?: ResourceColor;
  strokeWidth?: number;
}

const DEFAULT_SIZE: number = 24;
const DEFAULT_COLOR: ResourceColor = $r('app.color.text_secondary');
const DEFAULT_STROKE: number = 1.75;

function iconSize(p?: IconProps): number {
  return p?.size ?? DEFAULT_SIZE;
}

function iconColor(p?: IconProps): ResourceColor {
  return p?.color ?? DEFAULT_COLOR;
}

function iconStroke(p?: IconProps): number {
  return p?.strokeWidth ?? DEFAULT_STROKE;
}

@Builder
export function IconSearch(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M16.5 16.5 L21 21 M11 4 A7 7 0 1 1 11 18 A7 7 0 1 1 11 4')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconPlus(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M12 5 L12 19 M5 12 L19 12')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
}

@Builder
export function IconClose(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M6 6 L18 18 M18 6 L6 18')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
}

@Builder
export function IconChevronLeft(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M15 5 L8 12 L15 19')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconChevronRight(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M9 5 L16 12 L9 19')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconCheck(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M5 12 L10 17 L19 7')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconEdit(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M13 5 L19 11 L8 22 L3 22 L3 17 Z')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconTrash(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M4 7 L20 7 M10 11 L10 17 M14 11 L14 17 M8 7 L9 4 L15 4 L16 7')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconSettings(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M12 3 L14 6 L17 5 L18 8 L21 9 L19 12 L21 15 L18 16 L17 19 L14 18 L12 21 L10 18 L7 19 L6 16 L3 15 L5 12 L3 9 L6 8 L7 5 L10 6 Z')
    .fill(iconColor(props))
    .stroke('none')
}

@Builder
export function IconShield(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M12 3 L20 6 L20 11 C20 16 16.5 20 12 21 C7.5 20 4 16 4 11 L4 6 Z')
    .fill(iconColor(props))
    .stroke('none')
}

@Builder
export function IconShieldCheck(props?: IconProps) {
  Stack() {
    Path()
      .width(iconSize(props))
      .height(iconSize(props))
      .commands('M12 3 L20 6 L20 11 C20 16 16.5 20 12 21 C7.5 20 4 16 4 11 L4 6 Z')
      .fill(iconColor(props))
      .stroke('none')
    Path()
      .width((iconSize(props) as number) * 0.6)
      .height((iconSize(props) as number) * 0.6)
      .commands('M7 12 L10 15 L16 9')
      .fill('none')
      .stroke('#FFFFFF')
      .strokeWidth(2)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
  }
  .width(iconSize(props))
  .height(iconSize(props))
}

@Builder
export function IconLink(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M9 15 L15 9 M11 7 L13 5 C15.5 2.5 19.5 2.5 22 5 C24.5 7.5 24.5 11.5 22 14 L20 16 M13 19 L11 21 C8.5 23.5 4.5 23.5 2 21 C-0.5 18.5 -0.5 14.5 2 12 L4 10')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}

@Builder
export function IconExternal(props?: IconProps) {
  Path()
    .width(iconSize(props))
    .height(iconSize(props))
    .commands('M10 14 L20 4 M15 4 L20 4 L20 9 M14 9 L5 9 C4 9 3 10 3 11 L3 19 C3 20 4 21 5 21 L17 21 C18 21 19 20 19 19 L19 12')
    .fill('none')
    .stroke(iconColor(props))
    .strokeWidth(iconStroke(props))
    .strokeLineCap(LineCapStyle.Round)
    .strokeLineJoin(LineJoinStyle.Round)
}
