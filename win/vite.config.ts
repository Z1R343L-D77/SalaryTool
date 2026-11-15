import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
// @ts-expect-error type error without @types/node package
import process from "node:process";
// @ts-expect-error type error without @types/node package
import { fileURLToPath, URL } from "node:url";
// @ts-expect-error type error without @types/node package
import pkg from "./package.json" with { type: "json" };

const host = process.env.TAURI_DEV_HOST;

/*
 * 仓库根下有两套外壳：
 *   win/     Windows 桌面（Tauri 2，透明玻璃窗口）
 *   ios/     iPhone（Tauri 2，移动布局）
 * 计算逻辑、数据模型、外观设置两边完全一样，放在根目录的 shared/ 里，
 * 用别名 @shared 引用，避免复制两份之后改一处忘另一处。
 */
export default defineConfig(() => ({
  plugins: [vue()],

  resolve: {
    alias: {
      "@shared": fileURLToPath(new URL("../shared", import.meta.url)),
    },
  },

  // 版本号在构建时注入，界面不额外请求文件
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
    fs: {
      // 允许读取仓库根的 shared/ 目录
      allow: [".."],
    },
  },

  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "../shared/**/*.test.ts"],
  },
}));
