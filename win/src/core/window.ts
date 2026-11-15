/**
 * 窗口控制。
 *
 * 应用使用无边框窗口（decorations: false），窗口的三个按钮由前端自绘，
 * 这里封装 minimize / toggleMaximize / close 的调用。
 * 在浏览器里调试时这些动作没有意义，直接静默忽略。
 */

interface TauriWindow extends Window {
  __TAURI_INTERNALS__?: unknown;
}

function isTauri(): boolean {
  return typeof window !== "undefined" && Boolean((window as TauriWindow).__TAURI_INTERNALS__);
}

async function currentWindow() {
  const { getCurrentWindow } = await import("@tauri-apps/api/window");
  return getCurrentWindow();
}

export async function minimizeWindow(): Promise<void> {
  if (!isTauri()) return;
  try {
    await (await currentWindow()).minimize();
  } catch {
    // 权限不足或平台不支持时忽略
  }
}

export async function toggleMaximizeWindow(): Promise<boolean> {
  if (!isTauri()) return false;
  try {
    const win = await currentWindow();
    await win.toggleMaximize();
    return await win.isMaximized();
  } catch {
    return false;
  }
}

export async function closeWindow(): Promise<void> {
  if (!isTauri()) return;
  try {
    await (await currentWindow()).close();
  } catch {
    // ignore
  }
}

/** 双击标题栏切换最大化（和系统行为一致）。 */
export async function toggleMaximizeOnDoubleClick(event: MouseEvent): Promise<void> {
  if (!isTauri()) return;
  // 只响应标题栏空白处的双击，避免点到按钮
  const target = event.target as HTMLElement | null;
  if (target?.closest("button, a, input, select, textarea")) return;
  await toggleMaximizeWindow();
}
