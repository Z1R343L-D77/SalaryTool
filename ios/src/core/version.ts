/**
 * 版本号（iOS）。
 *
 * 从 Rust 侧读 CARGO_PKG_VERSION，浏览器调试时用构建时注入的常量。
 */
import { isTauri } from "./platform";

const FALLBACK_VERSION = "0.3.20261116";

let cached: string | null = null;

export async function getVersion(): Promise<string> {
  if (cached) return cached;
  if (isTauri()) {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      const value = await invoke<string>("app_version");
      cached = value;
      return value;
    } catch {
      // 取不到就退回构建时注入的版本
    }
  }
  const fallback =
    typeof __APP_VERSION__ === "string" && __APP_VERSION__ ? __APP_VERSION__ : FALLBACK_VERSION;
  cached = fallback;
  return fallback;
}
