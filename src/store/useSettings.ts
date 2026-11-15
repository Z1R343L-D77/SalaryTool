import { computed, reactive, watch } from "vue";
import type { AppSettings } from "../core/settings";
import {
  applySettings,
  loadSettings,
  saveSettings,
  systemPrefersLight,
} from "../core/settings";

/**
 * 外观设置的响应式状态。
 *
 * 设置和工资数据是两回事：工资数据导出时会带上所有字段，
 * 而「我用深色还是浅色」不该跟着走，所以存另一个 key。
 */

export const settings = reactive<AppSettings>(loadSettings());

/** 应用一次设置，写回 localStorage。 */
function commit(): void {
  applySettings(settings);
  saveSettings({ ...settings });
}

// 任何字段改动都立即生效，不需要「保存」按钮
watch(settings, commit, { deep: true });

/** 首次挂载时应用一次，并在系统主题变化时跟随刷新。 */
export function initSettings(): void {
  applySettings(settings);

  if (typeof window !== "undefined" && window.matchMedia) {
    const query = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = () => {
      // 只在「跟随系统」时响应
      if (settings.theme === "system") applySettings(settings);
    };
    if (query.addEventListener) query.addEventListener("change", onChange);
    else query.addListener?.(onChange);
  }
}

/** 当前实际生效的主题（把「跟随系统」解析成 dark / light）。 */
export const effectiveTheme = computed<"dark" | "light">(() => {
  if (settings.theme === "system") return systemPrefersLight() ? "light" : "dark";
  return settings.theme;
});

export function resetSettings(): void {
  settings.theme = "system";
  settings.fontScale = "md";
  settings.wallpaper = "fuji";
  settings.reduceTransparency = false;
}
