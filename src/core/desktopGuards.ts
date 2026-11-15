/**
 * 桌面应用的浏览器行为屏蔽。
 *
 * WebView 默认带着一堆浏览器功能（右键菜单、刷新、打印、另存为、开发者工具），
 * 在桌面程序里这些既多余又破坏「原生应用」的感觉。
 * 这里在窗口最外层统一拦掉，只保留输入框里真正需要的编辑快捷键。
 */

/** 需要屏蔽的快捷键（ctrl / cmd 部分）。 */
const BLOCKED_CTRL_KEYS = new Set([
  "r", // 刷新
  "f5", // 刷新
  "p", // 打印
  "s", // 另存为网页
  "o", // 打开文件
  "u", // 查看源码
  "j", // 下载
  "d", // 收藏
  "n", // 新窗口
  "t", // 新标签
  "w", // 关闭（交给应用自己的关闭逻辑）
  "+", // 缩放
  "-",
  "0",
]);

/** 需要屏蔽的 F 键。 */
const BLOCKED_FKEYS = new Set(["F3", "F5", "F7", "F11", "F12"]);

/** Cmd/Ctrl + Shift 组合里要放行的（开发者工具在调试时才需要）。 */
function isDevToolsCombo(event: KeyboardEvent): boolean {
  const key = event.key.toLowerCase();
  return (key === "i" || key === "j" || key === "c") && event.shiftKey;
}

export function installDesktopGuards(options: { allowDevTools?: boolean } = {}): void {
  if (typeof window === "undefined") return;
  const allowDevTools = options.allowDevTools ?? false;

  // 右键菜单：桌面应用里不需要
  window.addEventListener(
    "contextmenu",
    (event) => {
      event.preventDefault();
    },
    { capture: true },
  );

  // 拖拽文件到窗口会触发浏览器导航，直接拦掉
  for (const type of ["dragover", "drop"]) {
    window.addEventListener(
      type,
      (event) => {
        event.preventDefault();
      },
      { capture: true },
    );
  }

  window.addEventListener(
    "keydown",
    (event) => {
      const mod = event.ctrlKey || event.metaKey;
      const key = event.key.toLowerCase();

      if (BLOCKED_FKEYS.has(event.key)) {
        if (event.key === "F12" && allowDevTools) return;
        event.preventDefault();
        return;
      }

      if (!mod) return;

      if (!allowDevTools && isDevToolsCombo(event)) {
        event.preventDefault();
        return;
      }

      // 放行输入框真正需要的编辑操作（含 Ctrl+Shift+Z 重做），其余浏览器功能一律拦掉
      const editingKeys = new Set(["a", "c", "v", "x", "z", "y"]);
      if (editingKeys.has(key)) {
        return;
      }

      if (BLOCKED_CTRL_KEYS.has(key)) {
        event.preventDefault();
      }
    },
    { capture: true },
  );
}
