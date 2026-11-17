/**
 * 版本号。
 *
 * 桌面版从 Rust 侧读 CARGO_PKG_VERSION，浏览器调试时用 package.json 里的版本
 * （由 Vite 在构建时注入成常量，不额外请求文件）。
 */
import { isTauri } from "./platform";

const FALLBACK_VERSION = "0.3.20261117";

let cached: string | null = null;

export async function getVersion(): Promise<string> {
  if (cached) return cached;
  if (isTauri()) {
    try {
      const { invoke } = await import("@tauri-apps/api/core");
      cached = await invoke<string>("app_version");
      return cached;
    } catch {
      // 取不到就退回构建时注入的版本
    }
  }
  cached =
    typeof __APP_VERSION__ === "string" && __APP_VERSION__ ? __APP_VERSION__ : FALLBACK_VERSION;
  return cached;
}
