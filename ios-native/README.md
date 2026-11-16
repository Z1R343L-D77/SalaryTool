# SalaryTool · 原生 iOS

用 SwiftUI 重写的 iPhone 版。**和 `ios/`（WebView 版）是两条并行的路线**，
它更彻底、观感更接近系统 App，但门槛也更高。

## 为什么另起一个

`ios/` 那套是 Tauri + WebView。它能跑、能用，但有两个天花板：

1. **材质**：iOS 26 的 Liquid Glass 是系统在 GPU 上实时算的分层模糊 + 边缘折射，
   通过 `UIVisualEffectView` / SwiftUI 的 `.glassEffect()` 暴露给原生视图。
   WebView 里的 `backdrop-filter` 只能做单层高斯模糊 —— 没有折射、
   没有随内容变化的着色、没有交互时的材质形变。这就是为什么 WebView 版
   看着「像网页而不像 iOS」。
2. **系统集成**：分享面板、文件 App 集成、触感反馈、Dynamic Type、
   手势返回 —— 原生一行代码，WebView 里要么绕要么没有。

## 目录

```text
ios-native/
├── project.yml                    XcodeGen 工程定义
├── SalaryTool/
│   ├── SalaryToolApp.swift        入口
│   ├── Models/
│   │   ├── Models.swift           数据模型（字段与 shared/*.ts 一一对应）
│   │   ├── Money.swift            金额取整与格式化
│   │   ├── City.swift             各城市社保参数
│   │   └── Calculator.swift       计算核心（对照 shared/calculator.ts）
│   ├── State/
│   │   └── SalaryStore.swift      Observable 状态 + 持久化 + 导入导出
│   ├── Views/
│   │   ├── RootView.swift         主界面
│   │   ├── DesignSystem.swift     玻璃卡、胶囊开关、金额输入
│   │   ├── Sections.swift         六个栏目
│   │   └── Sheets.swift           明细 / 设置 / 导入
│   ├── Assets.xcassets            图标与壁纸
│   └── Info.plist
└── SalaryToolTests/
    └── SalaryToolTests.swift      计算逻辑单测（用例与 TS 版一致）
```

## 关键决定

| 项目 | 选择 | 原因 |
| --- | --- | --- |
| 最低系统 | **iOS 26.0** | Liquid Glass 的 `.glassEffect()` 从 26 才开始有 |
| 并发模型 | Swift 6 strict concurrency | 全量检查，编译期抓数据竞争 |
| UI 框架 | SwiftUI（不是 UIKit） | 玻璃材质、动画、布局系统更新更快 |
| 工程文件 | XcodeGen（`project.yml`） | `.xcodeproj` 是生成物，不提交；改结构只改 YAML |
| 数据存储 | Documents 里的 JSON | 和 Windows 版格式完全一致，可互相导入 |
| 计算逻辑 | Swift 重写一份 | WebView 版用 TS，两边各有单测保证数字一致 |

**计算逻辑为什么要写两份**：WebView 版可以直接复用 `shared/*.ts`，
但原生版没法在 Swift 里跑 JS（除非再嵌一个 JS 引擎，那等于又回到 WebView）。
所以 `Calculator.swift` 逐行对照 `calculator.ts`，用同一批测试用例校验。

## 构建

iOS 只能在 macOS 上编译。走 GitHub Actions（和 WebView 版同一套思路）：

```bash
# 本地（需要 macOS）
brew install xcodegen
cd ios-native && xcodegen generate
open SalaryToolNative.xcodeproj
```

CI 见 `.github/workflows/ios-native-build.yml`。

## 和 `ios/` 的关系

两条路线会长期并存：

- `ios/` 简单、改一行就生效、和 `shared/` 共享逻辑
- `ios-native/` 视觉和手感更好，但每个改动都要重新编译

界面设计一旦在某一版定稿，另一版照着抄是很快的；真正难的是「怎么长得像 iOS」，
所以这里先把原生版的骨架搭起来，作为视觉基准。
