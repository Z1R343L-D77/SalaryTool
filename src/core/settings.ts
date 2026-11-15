/**
 * 应用外观设置。
 *
 * 主题、字号、壁纸这些属于「怎么显示」，不属于「工资数据」，
 * 所以单独存一个 localStorage key，导出工资配置时不会带上它们。
 *
 * 设置值只决定三个根元素属性（data-theme / data-wallpaper / data-opaque）
 * 和一个 CSS 变量（--fs-scale），具体长什么样全在 global.css 里。
 */

export type ThemeMode = "system" | "dark" | "light";
export type FontScale = "sm" | "md" | "lg" | "xl";
export type WallpaperId = "fuji" | "aurora" | "dusk" | "plain";

export interface AppSettings {
  /** 跟随系统 / 强制暗色 / 强制亮色 */
  theme: ThemeMode;
  /** 字号档位 */
  fontScale: FontScale;
  /** 壁纸 */
  wallpaper: WallpaperId;
  /** 关闭毛玻璃模糊：低配机器上更流畅，也更省电 */
  reduceTransparency: boolean;
}

const STORAGE_KEY = "salarytool.settings.v1";

/** 字号档位对应的缩放比例，乘在每一个 --fs-* 令牌上。 */
export const FONT_SCALE_VALUES: Record<FontScale, number> = {
  sm: 0.92,
  md: 1,
  lg: 1.08,
  xl: 1.16,
};

export const FONT_SCALE_OPTIONS: ReadonlyArray<{ id: FontScale; label: string }> = [
  { id: "sm", label: "小" },
  { id: "md", label: "标准" },
  { id: "lg", label: "大" },
  { id: "xl", label: "特大" },
];

export const THEME_OPTIONS: ReadonlyArray<{ id: ThemeMode; label: string }> = [
  { id: "system", label: "跟随系统" },
  { id: "dark", label: "深色" },
  { id: "light", label: "浅色" },
];

/** 壁纸选项，缩略图由 CSS 类名决定（见 global.css 的 .wallpaper-thumb--*）。 */
export const WALLPAPER_OPTIONS: ReadonlyArray<{ id: WallpaperId; label: string; hint: string }> = [
  { id: "fuji", label: "富士山", hint: "默认实景图，约 260 KB" },
  { id: "aurora", label: "极光", hint: "深青渐变，纯 CSS 绘制" },
  { id: "dusk", label: "暮色", hint: "紫橙渐变，纯 CSS 绘制" },
  { id: "plain", label: "无壁纸", hint: "纯色底，最省资源" },
];

export function createDefaultSettings(): AppSettings {
  return {
    theme: "system",
    fontScale: "md",
    wallpaper: "fuji",
    reduceTransparency: false,
  };
}

function pick<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return typeof value === "string" && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : fallback;
}

/** 读取设置；字段缺失或非法时用默认值补齐。 */
export function normalizeSettings(input: unknown): AppSettings {
  const base = createDefaultSettings();
  if (!input || typeof input !== "object") return base;
  const raw = input as Record<string, unknown>;
  return {
    theme: pick(raw.theme, ["system", "dark", "light"], base.theme),
    fontScale: pick(raw.fontScale, ["sm", "md", "lg", "xl"], base.fontScale),
    wallpaper: pick(raw.wallpaper, ["fuji", "aurora", "dusk", "plain"], base.wallpaper),
    reduceTransparency:
      typeof raw.reduceTransparency === "boolean" ? raw.reduceTransparency : base.reduceTransparency,
  };
}

export function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return createDefaultSettings();
    return normalizeSettings(JSON.parse(raw));
  } catch {
    return createDefaultSettings();
  }
}

export function saveSettings(settings: AppSettings): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // 存储不可用时静默失败，设置只在本次会话生效
  }
}

/** 系统当前是否偏好浅色。 */
export function systemPrefersLight(): boolean {
  if (typeof window === "undefined" || !window.matchMedia) return false;
  return window.matchMedia("(prefers-color-scheme: light)").matches;
}

/**
 * 把设置应用到 <html> 上。
 *
 * 主题只写 data-theme；「跟随系统」时由这里的 matchMedia 决定实际值，
 * 并在系统主题变化时重新调用一次。CSS 里不写 prefers-color-scheme 媒体查询，
 * 因为像 Chrome 的强制深色模式之类的功能会干扰它。
 */
export function applySettings(settings: AppSettings): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  const theme =
    settings.theme === "system" ? (systemPrefersLight() ? "light" : "dark") : settings.theme;

  root.dataset.theme = theme;
  root.dataset.themeMode = settings.theme;
  root.dataset.wallpaper = settings.wallpaper;
  root.dataset.opaque = settings.reduceTransparency ? "true" : "false";
  root.style.setProperty("--fs-scale", String(FONT_SCALE_VALUES[settings.fontScale]));
}
