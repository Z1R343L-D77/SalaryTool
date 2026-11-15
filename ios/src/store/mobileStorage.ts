/**
 * iOS 持久化：localStorage + App 沙盒双写。
 *
 * 为什么要两套：
 *
 * localStorage 在 iOS 的 WKWebView 里属于「可被清理」的数据。设备存储紧张、
 * 系统清理缓存、或者 WebView 进程被回收后重建时，它可能被清掉。桌面端没这个问题，
 * 但手机上这是真实发生的事 —— 用户用了几个月，某天打开数据全没了。
 *
 * 所以主存储改成 App 沙盒里的 JSON 文件（Application Support 目录），
 * 那是受系统保护、不会被回收的位置；localStorage 只作为「首帧快速读取」的缓存，
 * 让界面不用等异步 IO 就能先渲染出来。
 */
import type { SalaryState } from "@shared/defaults";
import { normalizeState, saveState } from "@shared/storage";

interface TauriWindow extends Window {
  __TAURI_INTERNALS__?: unknown;
}

const FILE_NAME = "salarytool-state.json";

/**
 * 水合状态：挂载后异步读取沙盒文件，读完前界面先用 localStorage 的值。
 */
export const hydrateState = {
  ready: false,
  /** 沙盒里有数据但 localStorage 是空的，说明 localStorage 被清过 */
  recoveredFromDisk: false,
};

function tauri(): boolean {
  return typeof window !== "undefined" && Boolean((window as TauriWindow).__TAURI_INTERNALS__);
}

/** 从沙盒读取。浏览器调试时直接跳过。 */
export async function loadStateAsync(): Promise<SalaryState | null> {
  if (!tauri()) {
    hydrateState.ready = true;
    return null;
  }
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    const text = await invoke<string | null>("load_state_file", { fileName: FILE_NAME });
    if (!text) {
      hydrateState.ready = true;
      return null;
    }
    const parsed = normalizeState(JSON.parse(text));
    hydrateState.ready = true;
    hydrateState.recoveredFromDisk = true;
    return parsed;
  } catch {
    hydrateState.ready = true;
    return null;
  }
}

/** 双写：localStorage 负责快，沙盒负责持久。 */
export async function saveStateAsync(state: SalaryState): Promise<void> {
  // 先写 localStorage（同步、零成本）
  saveState(state);

  if (!tauri()) return;
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    await invoke("save_state_file", {
      fileName: FILE_NAME,
      contents: JSON.stringify(state),
    });
  } catch {
    // 写盘失败时不影响使用，localStorage 里还有一份
  }
}

/**
 * 挂载时调用：读沙盒 → 如果 localStorage 是空的而沙盒有数据，说明被清过，用沙盒恢复。
 *
 * 这个函数返回的 state 需要由调用方通过 applyState 写进 reactive 对象，
 * 所以这里只负责取数据，不直接改全局状态。
 */
export async function restoreFromDisk(): Promise<SalaryState | null> {
  return loadStateAsync();
}
