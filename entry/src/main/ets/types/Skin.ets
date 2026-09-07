/**
 * Skin —— 皮肤/主题色包（M5）
 *
 * 运行时换肤不走 resources/color.json：ArkUI 资源是编译期静态产物，运行时无法改写。
 * 因此由 ThemeController 把当前皮肤的色值写入 AppStorage（skinAccent/skinAccentTint），
 * 需要换肤的组件以 @StorageLink 消费。
 *
 * 换肤范围刻意克制：只覆盖强调色类元素（主按钮、开关选中态、高亮文字/浅底色）。
 * 底色/文字色仍走 $r('app.color.*')，亮暗切换继续由系统资源目录（resources/dark）
 * 负责——「皮肤管强调色、系统资源管亮暗」，两套机制职责分离，互不踩脚。
 *
 * accentTint 用 rgba 半透明而不是实体浅色：同一色值叠在亮色/暗色底上都成立，
 * 免去为每套皮肤再维护亮暗两份浅底色。
 */
/** 默认蓝皮肤的强调色（AppStorage 未初始化前各 @StorageLink 的兜底默认值，R3 收敛硬编码） */
export const DEFAULT_ACCENT: string = '#2563EB';
export const DEFAULT_ACCENT_TINT: string = 'rgba(37,99,235,0.10)';

export interface SkinPack {
  id: string;
  name: string;
  accent: string;      // 强调色：主按钮底色、开关选中态、高亮文字
  accentTint: string;  // 强调色浅底（rgba 半透明，亮暗两态通用）
  success: string;     // 语义色覆盖（预留，当前未应用——状态指示灯保持语义色，不随皮肤变）
  warn: string;        // 同上（预留）
}

export const SKINS: SkinPack[] = [
  { id: 'default', name: '默认蓝', accent: DEFAULT_ACCENT, accentTint: DEFAULT_ACCENT_TINT, success: '#10B981', warn: '#F59E0B' },
  { id: 'emerald', name: '翠绿', accent: '#059669', accentTint: 'rgba(5,150,105,0.12)', success: '#10B981', warn: '#F59E0B' },
  { id: 'violet', name: '紫罗兰', accent: '#7C3AED', accentTint: 'rgba(124,58,237,0.10)', success: '#10B981', warn: '#F59E0B' },
];

/** 按 id 查皮肤；未知 id 回退第一套（默认蓝） */
export function skinById(id: string): SkinPack {
  for (const s of SKINS) {
    if (s.id === id) {
      return s;
    }
  }
  return SKINS[0];
}
