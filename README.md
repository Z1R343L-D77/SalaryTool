# 当月薪水到手计算器

<p align="center">
  <img src="docs/screenshots/win-income.jpg" alt="Windows 桌面版" width="76%">
</p>

<p align="center">
  <a href="#下载"><img src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?style=flat-square" alt="Windows"></a>
  <a href="#ios-构建"><img src="https://img.shields.io/badge/platform-iOS%2026%2B-black?style=flat-square" alt="iOS"></a>
  <a href="#许可证"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/tests-109%20passed-brightgreen?style=flat-square" alt="Tests">
</p>

<p align="center">
  把工资条上那些看不懂的数字，拆成能自己算清的一笔一笔。
</p>

<br>

<p align="center">
  <img src="docs/screenshots/ios-overview.jpg" alt="iPhone 版：收入项 / 明细 / 栏目 / 加班日历" width="100%">
</p>
<p align="center">
  <sub>iPhone 版 — 左起：收入项 · 本月明细 · 栏目切换 · 加班日历</sub>
</p>

---

## 这是什么

一个离线的工资计算器。填进去基本工资、各类补贴、五险一金参数，
按国家税务总局的「累计预扣预缴」规则，算出这个月实际到手多少。

和网上那些工资计算器不一样的地方，是它允许你把**每一个口径**都改掉：

- 社保按上年月平均工资、公积金只按基本工资？两个基数可以分开设。
- 餐补计税但不计入社保基数？每个收入项独立开关。
- 年中才申报了子女教育扣除？按月记录工资条，累计值准确还原。
- 年中换过工作，减除费用怎么算？两种口径可以切换。

算完会给出逐项明细：养老交了多少、医疗交了多少、这个月的税是怎么推出来的。

## 两份实现

这个仓库里是**同一个应用的两个版本**，共用一套计算口径：

| | Windows 桌面版 | iPhone 版 |
| --- | --- | --- |
| 技术栈 | Tauri 2 · Vue 3 · TypeScript | SwiftUI（原生） |
| 版本 | `0.2.0` | `0.3.20261117` |
| 特点 | 三列布局，一次看全所有参数 | 天气 App 式布局，玻璃质感 |
| 计算逻辑 | `shared/`（TS） | `Models/Calculator.swift`（Swift 重写） |

两边的数据格式完全一致，导出的 JSON 可以互相导入。

**为什么要写两份**：Windows 版跑在 WebView 里，改一行就热更新，很快。
但 iOS 26 的 Liquid Glass 是系统在 GPU 上实时算的分层模糊加边缘折射，
只有原生视图拿得到（`.glassEffect()`）。WebView 的 `backdrop-filter`
只能做单层高斯模糊，做不出那种「真的隔着一块玻璃」的质感。

计算逻辑在两份实现里各写一遍，靠同一批测试用例保证结果一致 ——
`shared/*.test.ts` 和 `SalaryToolTests.swift` 里是同样的场景和同样的期望值。

## 下载

**Windows** — 到 [Releases](https://github.com/Z1R343L-D77/SalaryTool/releases)
下载 `SalaryTool-0.2.0.exe`，双击即开，单文件免安装。

**iPhone** — 见 [iOS 构建](#ios-构建)。只能自己签名安装，免费账号 7 天续签一次。

## 功能

### 薪水计算

**收入项** — 每一项独立控制三件事：

| 开关 | 作用 |
| --- | --- |
| 社保 | 是否计入社保缴费基数 |
| 公积金 | 是否计入公积金缴费基数（可与社保不同） |
| 计税 | 是否计入应纳税所得额 |

基本工资一般三个都勾；餐补、交通补贴只勾「计税」；报销类一个都不勾。

**社保 / 公积金** — 两个基数各自独立，可以都选自动，也可以一个自动一个手填。
自动模式下取「勾了对应开关的收入项合计」，再按当地上下限 clamp。
养老、医疗、失业、公积金四个比例，加上大额医疗互助固定额，全部可改。

**累计数据** — 这是个税计算准确与否的关键。两种填法：

*手填* —— 直接抄工资条上的「截至上月累计收入 / 累计社保 / 累计专项附加 / 累计已缴税」。

*按月记录* —— 每个月记一条，累计值自动加出来。适合中途才申报专项附加扣除、
或者某几个月收入不同的情况。

**减除费用口径** — 两种，按国家税务总局 2020 年第 13 号公告：

| 口径 | 谁用 | 例子 |
| --- | --- | --- |
| 当年月份数 | 当年首次取得工资薪金 | 10 月发薪 → 扣 5000 × 10 = 50,000 |
| 本单位月数 | 年内已有过工资收入（换工作） | 10 月发薪但在本单位第 4 月 → 扣 20,000 |

这也是应届生入职当年常常一分税都不缴的原因。减除费用从当年 1 月起算，
年收入不到 6 万时累计应纳税所得额始终是负的。**没有「应届生免税」这个政策**，
是这条规则在起作用。

**年终奖** — 单独计税（奖金 ÷ 12 查月度税率表）或并入综合所得，跟着税率跳档走。

### 加班费计算器

<p align="center">
  <img src="docs/screenshots/win-overtime.jpg" alt="Windows 加班费计算器" width="100%">
</p>

| 项目 | 倍率 | 依据 |
| --- | --- | --- |
| 工作日 | 1.5 倍 | 延长工时 |
| 休息日 | 2 倍 | 可用补休替代 |
| 法定节假日 | 3 倍 | 不能用补休替代 |

基数两种填法，**永远双向同步**：填月薪算时薪，填时薪反算月薪。来回切换模式不会
覆盖你手填的值。小时工资保留四位小数——这是折算出来的中间值，留两位误差会被工时放大：
`6700 ÷ 174 = 38.5057`，截成 `38.51` 后乘 1.5 是 `57.77`，实际应该是 `57.7586`。

工时可以填合计，也可以在日历上逐天填。日历会自动识别日期固定的法定节假日
（元旦、劳动节、国庆），农历节日每年日期不同，点日期右上角的标签手动标。

同步方向是**日历 → 合计**，单向。日历是按天记的真实工时，拿模糊的合计反推
只能靠猜，一旦写回就把记录毁了。两边不一致时界面会说明当前以哪边为准。

打开「同步到收入项」后，算出的加班费会实时写进指定的收入项，
工资合计、社保基数、个税跟着重算。

## 计算口径

```text
累计应纳税所得额 = 累计收入
                 − 5000 × 月数
                 − 累计社保公积金
                 − 累计专项附加扣除
                 − 累计其他税前扣除

本月应预扣 = 按年度税率表算出的累计税额 − 截至上月已预缴税额
```

年度税率表七级（3% / 10% / 20% / 25% / 30% / 35% / 45%），从累计应纳税所得额
查级距和速算扣除数。年终奖单独计税时改用月度换算表（奖金 ÷ 12 的商查表）。

## Windows 开发

```bash
cd win
npm install
npm run dev          # 浏览器里调试界面
npm run tauri dev    # 桌面窗口，热更新
npm test             # 运行共享的计算逻辑单测
npm run tauri build  # 打包
```

也可以双击 `win/start.bat`：自动检查环境、按需编译、启动窗口。

### 环境要求

| 依赖 | 说明 |
| --- | --- |
| Node.js 20+ | 前端构建 |
| Rust (stable) | `rustup`，含 `x86_64-pc-windows-msvc` target |
| Visual Studio Build Tools | 勾选「使用 C++ 的桌面开发」 |
| WebView2 Runtime | Win11 自带；Win10 需要装 |

## iOS 构建

iOS 只能在 macOS 上编译 —— Xcode 的授权限制，没有 Windows 移植方案。
所以走 GitHub Actions 的 macOS runner：Windows 上写代码、push、云端编译、下载 `.ipa`。

```bash
# 1. 在 GitHub Actions 页面手动触发 Build iOS (Native)
# 2. 从 Artifacts 下载 SalaryTool-native-ipa
# 3. 用 Sideloadly 签名安装（Windows 上就能做）
```

免费 Apple ID 签的 App 每 7 天过期，重跑一次 Sideloadly 即可续签，数据不丢。

本地开发需要 macOS：

```bash
brew install xcodegen
cd ios-native && xcodegen generate
open SalaryToolNative.xcodeproj
```

## 数据

只存本机，不联网，不上传。

| 平台 | 位置 | 备份方式 |
| --- | --- | --- |
| Windows | `localStorage` | 顶栏「导出」走系统另存为对话框 |
| iOS | App 文档目录 `salarytool-state.json` | 设置 → 数据 → 导出备份 |

iOS 那边配合 `UIFileSharingEnabled`，导出的文件会出现在
「文件 → 我的 iPhone → SalaryTool」，插数据线或走 iCloud 都能取走。

两块都用原子写（临时文件 + rename），中途崩溃不会留下半个文件。

## 目录

```text
shared/                 计算与数据模型（Windows 版直接用）
├── taxTables.ts        个税税率表（年度 / 月度）
├── cityPolicies.ts     各城市社保公积金默认参数
├── calculator.ts       五险一金、累计预扣个税、到手计算
├── history.ts          按月记录与累计值累加
├── overtime.ts         加班费折算
├── calendar.ts         加班日历与节假日识别
├── storage.ts          持久化、导入与字段校验
└── *.test.ts           109 项单元测试

win/                    Windows 桌面版
├── src/                Vue 界面
├── src-tauri/          Tauri Rust 侧
└── start.bat           一键启动

ios-native/             iPhone 版
├── SalaryTool/Models/  计算核心（与 shared/ 一一对照）
├── SalaryTool/State/   @Observable 状态与持久化
├── SalaryTool/Views/   天气 App 式界面
├── SalaryToolTests/    同批测试用例的 Swift 版
└── project.yml         XcodeGen 工程定义

docs/screenshots/       README 用的截图
```

## 注意事项

- 各城市社保基数上下限和比例是**示例默认值**，每年 7 月各地会调整，
  请以当地人社局公布为准。界面上所有数字都能改。
- 大病医疗等按年度汇算的扣除项，按月计算时一般不填。
- 计算结果仅供估算，以实际工资条为准。

## 使用到的开源项目

| | |
| --- | --- |
| [Tauri](https://tauri.app/) | 桌面外壳 |
| [Vue 3](https://vuejs.org/) | Windows 界面 |
| [Inter](https://rsms.me/inter/) · [Noto Sans SC](https://fonts.google.com/noto/specimen/Noto+Sans+SC) | 内嵌字体，SIL OFL 1.1 |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | iOS 工程生成 |

## 许可证

[MIT](LICENSE)
