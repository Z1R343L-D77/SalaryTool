/**
 * iOS 界面预览器（Windows / macOS / Linux 都能跑）。
 *
 * 为什么不是「模拟器」：
 * 真正的 iOS 模拟器只有 Xcode 提供，只能在 macOS 上跑。但界面这一层是
 * WebView 渲染的 HTML/CSS，而 iOS 的 WebView = WebKit。Playwright 自带
 * 一份 WebKit，可以在 Windows 上以 iPhone 的视口、DPR、触摸模式打开页面 ——
 * 排版、字号、点击热区、滚动行为都对得上，只有系统级的东西（原生分享面板、
 * 安全区、Liquid Glass 材质）需要真机确认。
 *
 * 用法：
 *   node tools/preview.mjs            # 用 vite dev 跑，改代码自动热更新
 *   node tools/preview.mjs --build    # 先构建再用 dist 跑，验最终产物
 *   node tools/preview.mjs --device iphone15
 *   node tools/preview.mjs --no-notch # 关掉安全区模拟，看纯内容布局
 */

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import process from "node:process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

/** 常见机型的逻辑分辨率。默认取你手上那台的尺寸。 */
const DEVICES = {
  iphone15: { width: 393, height: 852, dpr: 3, label: "iPhone 15 / 15 Pro" },
  iphone16pro: { width: 402, height: 874, dpr: 3, label: "iPhone 16 Pro / 18 Pro" },
  iphonese: { width: 375, height: 667, dpr: 2, label: "iPhone SE (3rd)" },
  iphone8: { width: 375, height: 667, dpr: 2, label: "iPhone 8 (小屏极限)" },
};

const args = process.argv.slice(2);
const useBuild = args.includes("--build");
const noNotch = args.includes("--no-notch");
const deviceArg = args.find((a) => a.startsWith("--device="))?.split("=")[1]
  ?? (args.includes("--device") ? args[args.indexOf("--device") + 1] : null);
const device = DEVICES[deviceArg] ?? DEVICES.iphone16pro;

const PORT = 1422;
const URL = `http://localhost:${PORT}/`;

/*
 * 桌面 WebKit 里 env(safe-area-inset-*) 一律是 0，而 iPhone 上是
 * 顶部 47–59px / 底部 34px。不模拟的话，标题会贴着屏幕边缘，
 * 看起来就不像真机。
 *
 * CSS 的 env() 没法用变量覆盖，所以直接注入一组 !important 规则，
 * 把用到安全区的几处改写成固定值。
 */
function safeAreaCss(device) {
  const top = device.height >= 800 ? 59 : 20;
  const bottom = device.height >= 800 ? 34 : 0;
  return `
html body { padding-top: ${top}px !important; padding-bottom: ${bottom}px !important; }
.topbar { padding-top: calc(8px + ${top}px) !important; }
.sheet__panel { padding-bottom: calc(16px + ${bottom}px) !important; }
.sheet__panel--compact { padding-bottom: calc(20px + ${bottom}px) !important; }
.toast { bottom: calc(84px + ${bottom}px) !important; }
`;
}

async function startVite() {
  const bin = join(root, "node_modules", "vite", "bin", "vite.js");
  const child = spawn(process.execPath, [bin, "--port", String(PORT), "--strictPort"], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
  });

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("vite 启动超时")), 30000);
    child.stdout.on("data", (buf) => {
      const text = buf.toString();
      if (text.includes("Local") || text.includes("ready in")) {
        clearTimeout(timer);
        resolve();
      }
    });
    child.stderr.on("data", (buf) => process.stderr.write(buf));
    child.on("exit", (code) => reject(new Error(`vite 退出：${code}`)));
  });

  return child;
}

async function buildDist() {
  console.log("→ 构建生产包…");
  const vite = join(root, "node_modules", "vite", "bin", "vite.js");
  await new Promise((resolve, reject) => {
    const p = spawn(process.execPath, [vite, "build", "--port", String(PORT)], {
      cwd: root,
      stdio: "inherit",
    });
    p.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`build 失败：${code}`))));
  });

  const preview = spawn(process.execPath, [vite, "preview", "--port", String(PORT), "--strictPort"], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("preview 启动超时")), 30000);
    preview.stdout.on("data", (buf) => {
      if (buf.toString().includes("Local")) {
        clearTimeout(timer);
        resolve();
      }
    });
  });
  return preview;
}

async function main() {
  let server;
  if (useBuild) {
    server = await buildDist();
  } else {
    console.log("→ 启动 vite dev…");
    server = await startVite();
  }

  const { webkit } = await import("playwright");
  const browser = await webkit.launch({
    headless: false,
    args: ["--disable-web-security"],
  });

  const context = await browser.newContext({
    viewport: { width: device.width, height: device.height },
    deviceScaleFactor: device.dpr,
    isMobile: true,
    hasTouch: true,
    userAgent:
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " +
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  });

  const page = await context.newPage();

  if (!noNotch) {
    await page.addStyleTag({ content: safeAreaCss(device) });
    // SPA 刷新时样式会丢，重新挂一次
    page.on("load", () => {
      page.addStyleTag({ content: safeAreaCss(device) }).catch(() => {});
    });
  }

  page.on("pageerror", (e) => console.error("[页面错误]", e.message));
  page.on("console", (msg) => {
    if (msg.type() === "error") console.error("[console]", msg.text());
  });

  await page.goto(URL, { waitUntil: "domcontentloaded" });

  console.log("");
  console.log(`  设备   ${device.label}  ${device.width}×${device.height} @${device.dpr}x`);
  console.log(`  引擎   WebKit（和 iOS 上同一套排版系统）`);
  console.log(`  地址   ${URL}`);
  console.log("");
  console.log("  改代码会热更新，关掉窗口即退出。");
  console.log("  ⚠ 原生能力（分享面板、写沙盒、安全区）仍需真机验证。");
  console.log("");

  // 窗口关闭时收尾
  const cleanup = () => {
    try { server?.kill(); } catch { /* ignore */ }
  };
  browser.on("disconnected", cleanup);
  process.on("SIGINT", () => {
    cleanup();
    process.exit(0);
  });

  await new Promise(() => {});
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
