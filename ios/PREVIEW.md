# iOS 界面在 Windows 上怎么验证

真机装一次要 5 分钟，改一行字就得重来，不现实。这里有三层办法，
按「发现问题的时间成本」从低到高排。

## 一、浏览器预览（最快，改代码自动刷新）

```bash
cd ios
npm run preview:ios
```

它做的事：

1. 启动 `vite dev`（1422 端口，和 Tauri 的 devUrl 一致）
2. 拉起 **WebKit** 浏览器（Playwright 自带的那份）
3. 按 iPhone 的视口、DPR、触摸模式打开，注入安全区高度

**为什么是 WebKit**：iOS 上所有浏览器（Safari、Chrome、微信内置）用的都是
WebKit 内核，不是 Chromium。Chrome 里看着正常、真机上排版崩掉的情况很常见。
用 WebKit 预览，排版结果和真机基本一致。

常用参数：

```bash
npm run preview:ios -- --device iphone15      # 换机型
npm run preview:ios -- --device iphonese      # 小屏极限测试
npm run preview:ios -- --no-notch             # 关掉安全区，看纯内容布局
npm run preview:ios:build                     # 用 dist 跑（验最终产物）
```

改 `src/` 下的代码会自动热更新，不需要重启。

## 二、批量截图（无人值守）

```bash
cd ios
npm run build
node tools/shot.mjs                    # 六个栏目 + 明细面板，全部截图
node tools/shot.mjs --theme light      # 浅色主题
node tools/shot.mjs --section overtime # 只截一个
```

输出到 `ios/screenshots/`，文件名带主题后缀：`income-dark.png`。
适合做完改动后一次性看全部页面，也方便前后对比。

## 三、真机（必须做，但只在最后做一次）

下面这些**预览器验证不了**，只能上真机：

| 项目 | 原因 |
| --- | --- |
| 原生分享面板 | 需要 `UIActivityViewController`，WebView 里没有 |
| 写 Documents 目录 | 需要 Rust 侧的 `fs`，浏览器里走的是 Blob 下载 |
| 安全区的真实数值 | 桌面 `env(safe-area-inset-*)` 恒为 0，预览里是手动注入的 |
| Liquid Glass 材质 | 系统级的实时模糊与边缘折射，`backdrop-filter` 模拟不来 |
| 键盘弹出行为 | 真机的 `visualViewport` 才反映键盘高度 |
| 手势（侧滑返回、长按） | 系统手势，浏览器不实现 |

所以流程建议是：**界面调整用预览器快速迭代，攒够一批改动再打一次包上真机验证**。

---

## 为什么不能在 Windows 上跑 iOS 模拟器

- **Xcode 模拟器**：只有 macOS 版 Xcode 才有，没有 Windows 移植。
- **越狱/第三方模拟器**：没有能跑未签名 Tauri App 的。
- **Docker / 虚拟机跑 macOS**：违反 Apple 授权协议（macOS 只允许在 Apple 硬件上虚拟化）。

Playwright 的 WebKit 是**浏览器引擎**，不是模拟器 —— 它跑的是网页，
只是排版引擎和 iOS 是同一套。这正是我们能验证界面的原因，也是它的边界。

---

## 预览器看到的 vs 真机

| | 预览器 | 真机 |
| --- | --- | --- |
| 排版 / 字号 / 间距 | ✅ 一致 | ✅ |
| 触摸热区 | ✅ 一致（`hasTouch`） | ✅ |
| 深浅色（跟随系统） | ✅（`--theme` 参数） | ✅ |
| 安全区 | 手动注入 | 系统真实值 |
| 滚动惯性 | 桌面模拟，手感不同 | 原生减速曲线 |
| 原生能力 | ❌ | ✅ |

最后那条差异不影响「丑不丑」的判断，所以界面设计完全可以在 Windows 上定稿。
