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
 * iOS 外壳的构建配置。
 *
 * 与 win/ 的区别只在端口和 outDir：
 * Tauri 的 iOS 开发模式会把 devUrl 指过来，端口必须固定。
 */
export default defineConfig(() => ({
  plugins: [vue()],

  resolve: {
    alias: {
      "@shared": fileURLToPath(new URL("../shared", import.meta.url)),
    },
  },

  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
  },

  clearScreen: false,
  server: {
    port: 1422,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1423,
        }
      : undefined,
    watch: {
      ignored: ["**/src-tauri/**", "**/gen/**"],
    },
    fs: {
      allow: [".."],
    },
  },

  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "../shared/**/*.test.ts"],
  },
}));
