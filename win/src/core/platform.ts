/**
 * 平台能力封装。
 *
 * 打包成桌面程序时：
 * - 导出备份可以通过系统「另存为」对话框选择保存位置，再交给 Rust 写盘
 * - WebView 里的 <a download> 在 Tauri 窗口内不生效，必须走原生通道
 * 浏览器里调试时退回 Blob 下载。
 */

interface TauriWindow extends Window {
  __TAURI_INTERNALS__?: unknown;
}

export function isTauri(): boolean {
  return typeof window !== "undefined" && Boolean((window as TauriWindow).__TAURI_INTERNALS__);
}

export interface SaveResult {
  /** "saved" 表示已写盘，"cancelled" 表示用户取消，"downloaded" 表示走浏览器下载 */
  status: "saved" | "cancelled" | "downloaded";
  path: string;
}

export interface SaveOptions {
  /** 建议的文件名，出现在保存对话框里 */
  fileName: string;
  contents: string;
  /** 文件类型过滤器，桌面版用；浏览器版忽略 */
  filters?: { name: string; extensions: string[] }[];
  /** true 时直接写到下载目录，不弹对话框 */
  skipPicker?: boolean;
}

/** 保存文件。桌面版弹出「另存为」对话框让用户选路径。 */
export async function saveFile(options: SaveOptions): Promise<SaveResult> {
  if (!isTauri()) {
    downloadInBrowser(options.fileName, options.contents);
    return { status: "downloaded", path: options.fileName };
  }

  let path: string | null = null;
  if (!options.skipPicker) {
    const { save } = await import("@tauri-apps/plugin-dialog");
    path = await save({
      defaultPath: options.fileName,
      filters: options.filters ?? [{ name: "JSON", extensions: ["json"] }],
    });
    // 用户点了「取消」
    if (!path) return { status: "cancelled", path: "" };
  }

  const { invoke } = await import("@tauri-apps/api/core");
  const saved = await invoke<string>("save_backup", { contents: options.contents, path });
  return { status: "saved", path: saved };
}

function downloadInBrowser(fileName: string, contents: string): void {
  const blob = new Blob([contents], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
}
