# SalaryTool · iPhone 版

和 `win/` 共用 `shared/` 里的计算逻辑，界面按 iPhone 重排。

## 产物怎么拿到

iOS 只能由 macOS 上的 Xcode 编译（Apple 的授权限制），所以走 GitHub Actions：

1. 打开 [Actions → Build iOS](https://github.com/Z1R343L-D77/SalaryTool/actions/workflows/ios-build.yml)
2. 点 **Run workflow**
3. 约 2 分钟后，页面底部 **Artifacts** 里下载 `SalaryTool-unsigned-ipa`
4. 解压得到 `SalaryTool-unsigned.ipa`（约 3 MB）

## 装到手机

用 [Sideloadly](https://sideloadly.io/)（Windows 可用）：

1. iPhone 用数据线连电脑
2. 把 `.ipa` 拖进 Sideloadly
3. 填你的 Apple ID
4. 点 Start

装好后第一次打开需要在手机上信任证书：
**设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任**

> 免费 Apple ID 签的 App **7 天过期**。过期后重跑一次 Sideloadly 即可，
> 数据不会丢（bundle ID 没变，系统是覆盖安装）。

## 技术要点

- **代码签名**：CI 上没有证书，所以在 `project.pbxproj` 里注入
  `CODE_SIGNING_ALLOWED = NO` 等设置，先编译出未签名的 `.app`，
  再由 Sideloadly 在本地补签名。
- **为什么用 `tauri ios build` 而不是直接 `xcodebuild`**：
  Tauri 生成的 Xcode 工程里，"Build Rust Code" 脚本阶段会执行
  `tauri ios xcode-script`，它需要读 `gen/apple/.tauri/cli-options-server.json`——
  那个文件只由父进程 `tauri ios build` 在构建期间创建。
- **为什么是 Release 而不是 Debug**：Xcode 的 Debug 模式会额外产出
  `SalaryTool.debug.dylib`（80 MB），主二进制变成加载器，真机上没调试
  会话时起不来。Release 只有一个 5 MB 的完整二进制。
- **数据存储**：主存储在 App 沙盒的 `Application Support`，
  `localStorage` 只作首帧缓存。iOS 的 WKWebView 会在存储紧张时清理
  localStorage，沙盒文件不会。
- **与 Windows 互通**：靠导出/导入 JSON。两边 bundle ID 不同，
  是独立的 App，数据不共享。

## 本地开发

```bash
cd ios
npm install
npm run dev      # 浏览器里预览，用 DevTools 切 iPhone 视口
npm test         # 跑 shared/ 的 109 个测试
```

真机调试需要 macOS + Xcode，`npm run tauri ios dev`。
