/**
 * 平台能力封装（iOS）。
 *
 * 与 win/ 的实现有两点不同：
 * - 没有「另存为」对话框，导出走系统分享面板（Share Sheet）
 * - 文件写到 App 沙盒的 Documents 目录，再由分享面板交给用户选择用哪个 App 打开
 *
 * 浏览器里调试时退回 Blob 下载。
 */

interface TauriWindow extends Window {
  __TAURI_INTERNALS__?: unknown;
}

export function isTauri(): boolean {
  return typeof window !== "undefined" && Boolean((window as TauriWindow).__TAURI_INTERNALS__);
}

/** 移动端判断：iOS 上不支持桌面那套窗口控制。 */
export function isMobile(): boolean {
  return isTauri();
}

export interface SaveResult {
  status: "saved" | "cancelled" | "downloaded";
  path: string;
}

export interface SaveOptions {
  fileName: string;
  contents: string;
  filters?: { name: string; extensions: string[] }[];
  skipPicker?: boolean;
}

/**
 * 保存文件。
 *
 * iOS 上先写进沙盒，再调系统分享面板 —— 用户可以直接「存到文件」发到 iCloud、
 * 发给微信、或者用其他 App 打开。返回值里的 path 是沙盒内的路径。
 */
export async function saveFile(options: SaveOptions): Promise<SaveResult> {
  if (!isTauri()) {
    downloadInBrowser(options.fileName, options.contents);
    return { status: "downloaded", path: options.fileName };
  }

  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const path = await invoke<string>("save_export", {
      fileName: options.fileName,
      contents: options.contents,
    });
    return { status: "saved", path };
  } catch {
    // 用户取消或写入失败都按取消处理，不做二次弹窗
    return { status: "cancelled", path: "" };
  }
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
