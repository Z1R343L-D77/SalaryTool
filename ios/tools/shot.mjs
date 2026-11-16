/**
 * 各页面截图（无人值守）。
 *
 * 给「不想开窗口」或者「想给改动留个前后对比」的场景用：
 *   node tools/shot.mjs                 # 全部栏目，存到 ios/screenshots/
 *   node tools/shot.mjs --device iphone8
 *   node tools/shot.mjs --section overtime
 *
 * 引擎同样是 WebKit，尺寸与 iPhone 一致，所以排版结果和真机基本一致。
 */

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { mkdir, readFile } from "node:fs/promises";
import process from "node:process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(root, "screenshots");

const [{ webkit }] = await Promise.all([import("playwright")]);

const args = process.argv.slice(2);
const argOf = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const DEVICES = {
  iphone15: { width: 393, height: 852, dpr: 3, label: "iPhone 15" },
  iphone16pro: { width: 402, height: 874, dpr: 3, label: "iPhone 16 Pro" },
  iphonese: { width: 375, height: 667, dpr: 2, label: "iPhone SE" },
};
const device = DEVICES[argOf("device", "iphone16pro")] ?? DEVICES.iphone16pro;
const onlySection = argOf("section", null);
/** 主题：真机上跟随系统，这里显式指定，方便同一份代码截两套 */
const theme = argOf("theme", "dark");
const PORT = 1423;

const SECTIONS = [
  { id: "income", label: "收入项", tab: "收入" },
  { id: "special", label: "专项附加扣除", tab: "专项" },
  { id: "social", label: "社保公积金", tab: "社保" },
  { id: "ytd", label: "累计数据", tab: "累计" },
  { id: "deduction", label: "其他扣除", tab: "扣除" },
  { id: "overtime", label: "加班费", tab: "加班" },
];

/** 安全区模拟：桌面 WebKit 里 env() 恒为 0 */
function safeAreaCss() {
  const top = device.height >= 800 ? 59 : 20;
  const bottom = device.height >= 800 ? 34 : 0;
  return `
html body { padding-top: ${top}px !important; padding-bottom: ${bottom}px !important; }
.topbar { padding-top: calc(8px + ${top}px) !important; }
.sheet__panel { padding-bottom: calc(16px + ${bottom}px) !important; }
`;
}

async function serve() {
  const vite = join(root, "node_modules", "vite", "bin", "vite.js");
  const p = spawn(process.execPath, [vite, "preview", "--port", String(PORT), "--strictPort"], {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
  });
  await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("preview 启动超时")), 30000);
    p.stdout.on("data", (b) => {
      if (b.toString().includes("Local")) {
        clearTimeout(t);
        resolve();
      }
    });
  });
  return p;
}

await mkdir(outDir, { recursive: true });
const server = await serve();
const browser = await webkit.launch();
const ctx = await browser.newContext({
  viewport: { width: device.width, height: device.height },
  deviceScaleFactor: device.dpr,
  isMobile: true,
  hasTouch: true,
  // 让 prefers-color-scheme 按需返回，模拟系统的深浅色设置
  colorScheme: theme === "light" ? "light" : "dark",
});
const page = await ctx.newPage();
await page.goto(`http://localhost:${PORT}/`, { waitUntil: "networkidle" });
await page.addStyleTag({ content: safeAreaCss() });
await page.waitForTimeout(600);

const targets = onlySection
  ? SECTIONS.filter((s) => s.id === onlySection)
  : SECTIONS;

for (const section of targets) {
  await page.click(`.tab >> text="${section.tab}"`).catch(() => {});
  await page.waitForTimeout(700);
  const file = join(outDir, `${section.id}-${theme}.png`);
  await page.screenshot({ path: file });
  const { size } = await readFile(file).then((b) => ({ size: b.length }));
  console.log(`  ${section.id.padEnd(12)} → screenshots/${section.id}-${theme}.png  (${Math.round(size / 1024)} KB)`);
}

// 顺带截一张明细面板
if (!onlySection || onlySection === "sheet") {
  await page.click(".dock").catch(() => {});
  await page.waitForTimeout(700);
  await page.screenshot({ path: join(outDir, `sheet-detail-${theme}.png`) });
  console.log(`  sheet-detail → screenshots/sheet-detail-${theme}.png`);
}

await browser.close();
server.kill();
console.log(`\n设备 ${device.label} ${device.width}×${device.height} @${device.dpr}x`);
console.log(`输出目录 ${outDir}`);
