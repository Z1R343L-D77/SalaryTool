/**
 * iOS 的 WebView 行为屏蔽。
 *
 * 和桌面版（desktopGuards.ts）目标不同：
 * - 桌面要拦「浏览器功能」（刷新、打印、另存为、右键菜单）
 * - 手机上要拦「网页感」（长按选中、双击缩放、下拉刷新、橡皮筋回弹）
 *
 * 输入框里的选择、复制、粘贴必须保留 —— 那是正常操作。
 */

/** 输入类元素，长按菜单和选择都要放行。 */
function isEditable(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  if (!el || !el.closest) return false;
  return Boolean(el.closest("input, textarea, [contenteditable='true']"));
}

export function installMobileGuards(): void {
  if (typeof window === "undefined") return;

  // 长按弹出「拷贝 / 查询 / 分享」菜单：编辑区以外一律拦掉
  document.addEventListener(
    "contextmenu",
    (event) => {
      if (isEditable(event.target)) return;
      event.preventDefault();
    },
    { capture: true },
  );

  /*
   * 双击缩放。
   * iOS 上 Safari 会延迟 300ms 等第二次点击，判断是不是双击。
   * 这里自己吃掉双击，让单击立刻生效 —— 手感差别很明显。
   */
  let lastTouchEnd = 0;
  document.addEventListener(
    "touchend",
    (event) => {
      const now = Date.now();
      if (now - lastTouchEnd <= 300) {
        event.preventDefault();
      }
      lastTouchEnd = now;
    },
    { passive: false },
  );

  /*
   * 输入框聚焦时 iOS 会自动放大页面（字号小于 16px 时）。
   * global.css 里已经把 -webkit-text-size-adjust 设成 100%，这里是双保险：
   * 用 gesturestart 拦掉捏合缩放。
   */
  document.addEventListener("gesturestart", (event) => event.preventDefault());

  // 拖文件进来会触发页面跳转，手机上不会发生，但拖拽事件仍可能来
  for (const type of ["dragover", "drop"]) {
    window.addEventListener(type, (event) => event.preventDefault(), { capture: true });
  }
}
