/**
 * 平台能力封装（iOS）。
 *
 * 与 win/ 的区别：
 * - 没有「另存为」对话框，导出直接写进 App 的 Documents 目录
 * - Documents 会在「文件」App 里露面（文件 → 我的 iPhone → SalaryTool），
 *   也能插数据线或走 iCloud 取走
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
  /** "saved" 已写入 Documents；"cancelled" 失败或被拒；"downloaded" 浏览器下载 */
  status: "saved" | "cancelled" | "downloaded";
  /** 沙盒内的完整路径，界面可以用来提示用户去哪找 */
  path: string;
  /** 仅文件名，去掉一长串沙盒前缀，方便直接显示 */
  fileName: string;
}

export interface SaveOptions {
  fileName: string;
  contents: string;
  filters?: { name: string; extensions: string[] }[];
  skipPicker?: boolean;
}

/**
 * 保存文件到 Documents。
 *
 * 界面上的提示文案要配合这里：iOS 上没有「另存为」这一步，
 * 文件是直接落到 App 的 Documents 里的，用户要去「文件」App 找。
 */
export async function saveFile(options: SaveOptions): Promise<SaveResult> {
  if (!isTauri()) {
    downloadInBrowser(options.fileName, options.contents);
    return { status: "downloaded", path: options.fileName, fileName: options.fileName };
  }

  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const path = await invoke<string>("save_export", {
      fileName: options.fileName,
      contents: options.contents,
    });
    return { status: "saved", path, fileName: options.fileName };
  } catch (error) {
    // 写盘失败时把原因抛给界面，不要静默吞掉
    throw error instanceof Error ? error : new Error(String(error));
  }
}

/** 列出 Documents 里已有的导出文件，供界面显示「已导出 N 份」。 */
export async function listExports(): Promise<string[]> {
  if (!isTauri()) return [];
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    return await invoke<string[]>("list_exports");
  } catch {
    return [];
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
