//
//  RootView.swift
//  完全照 iOS 天气 App 的结构：
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  ← 这些都在滚动内容里，
//    │ 上海 · 第 11 月               │     往下滑会一起滑走
//    │        ¥9,692.33             │
//    │        本月实发到手            │
//    │                              │
//    │   [卡片]                      │
//    │   [卡片]                      │
//    │                              │
//    │  ◯        • • • • • •      ◯ │  ← 浮动玻璃工具栏，始终可见
//    └──────────────────────────────┘
//
//  几个关键点：
//  1. TabView 铺满整屏（忽略安全区），卡片滚到状态栏底下也不会被裁出硬边。
//  2. 标题和金额**不在 TabView 里**，所以左右翻页时它们不动；
//     但它们按当前页的滚动偏移整体上移，所以**上下滚动时会跟着走**
//     —— 这正是天气 App 的行为。
//  3. 每页的 ScrollView 顶部留出「安全区 + 头部高度」的空白，
//     内容滚动时才不会一上来就压在标题下面。
//  4. 底部三个控件都是透明 Liquid Glass：左右 52pt 圆形 + 中间胶囊。
//

import SwiftUI

struct RootView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.sectionJump) private var jump

    @State private var section: Section = .income
    @State private var showSettings = false
    @State private var showDetail = false
    @State private var showSectionList = false

    /// 底部工具栏本体高度（52）加上下留白，用于计算滚动内容的底部余量
    private let dockHeight: CGFloat = 52

    /// 当前页的垂直滚动偏移。头部按它上移，所以「上下滚时金额跟着走，
    /// 左右翻页时不动」—— 这是天气 App 的行为。
    @State private var scrollOffset: CGFloat = 0
    /// 头部（标题 + 金额）的实际高度，用来算首屏内容的起始位置
    @State private var headerHeight: CGFloat = 0

    /// 压在壁纸上的文字该用白色还是深色。
    /// 无壁纸 + 浅色主题时壁纸是白底，白字会看不见 —— 见 AppearanceStore 里的说明。
    private var onWallpaper: Color {
        appearance.prefersWhiteText(system: systemScheme) ? .white : .black
    }

    /// 玻璃材质的厚度。
    /// 浅色主题下 `.regular` 是一块发白的不透明板，压在白底上很重；
    /// `.clear` 更通透，配合深色文字反而清楚。
    private var glassVariant: Glass {
        systemScheme == .dark ? .regular : .clear
    }

    private var onWallpaperSecondary: Color {
        appearance.prefersWhiteText(system: systemScheme)
            ? Color.white.opacity(0.75)
            : Color.black.opacity(0.55)
    }

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case income, special, social, ytd, deduction, overtime

        var id: String { rawValue }

        var label: String {
            switch self {
            case .income: "收入"
            case .special: "专项"
            case .social: "社保"
            case .ytd: "累计"
            case .deduction: "扣除"
            case .overtime: "加班"
            }
        }

        var title: String {
            switch self {
            case .income: "收入项"
            case .special: "专项附加扣除"
            case .social: "社保 / 公积金"
            case .ytd: "累计数据与年终奖"
            case .deduction: "其他扣除"
            case .overtime: "加班费"
            }
        }

        var symbol: String {
            switch self {
            case .income: "banknote"
            case .special: "heart.text.square"
            case .social: "building.columns"
            case .ytd: "chart.line.uptrend.xyaxis"
            case .deduction: "minus.circle"
            case .overtime: "clock.badge.checkmark"
            }
        }

        var subtitle: String {
            switch self {
            case .income: "工资 · 补贴 · 绩效"
            case .special: "租房 · 教育 · 赡养"
            case .social: "基数 · 比例"
            case .ytd: "按月记录 · 年终奖"
            case .deduction: "年金 · 请假扣款"
            case .overtime: "1.5 / 2 / 3 倍"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let topPad = safeTop + 4

            ZStack(alignment: .top) {
                WallpaperView()
                    .ignoresSafeArea()

                // 只有卡片区参与上下滚 / 左右翻页
                TabView(selection: $section) {
                    ForEach(Section.allCases) { item in
                        page(
                            item,
                            topInset: topPad + headerHeight,
                            safeBottom: safeBottom
                        )
                        .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // 标题与金额：不在 TabView 里，所以左右翻页时不动；
                // 但会按当前页的滚动偏移整体上移，所以上下滚时会跟着走。
                VStack(spacing: 0) {
                    headerText
                    hero
                }
                .padding(.top, topPad)
                .offset(y: -scrollOffset)
                // 文字层不接收触摸，否则会挡住下面 ScrollView 的拖拽
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { view in
                    view.size.height - topPad
                } action: { value in
                    headerHeight = value
                }

                bottomBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(safeBottom, 8) + 2)
            }
            .ignoresSafeArea()
            // 齿轮单独一层：文字层已关闭触摸，按钮得自己挂着才点得到
            .overlay(alignment: .topTrailing) {
                gearButton
                    .padding(.trailing, 20)
                    .padding(.top, topPad)
                    .offset(y: -scrollOffset)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .preferredColorScheme(appearance.preferredScheme)
                .dynamicTypeSize(appearance.dynamicTypeSize)
        }
        .sheet(isPresented: $showDetail) {
            DetailView()
                .preferredColorScheme(appearance.preferredScheme)
                .dynamicTypeSize(appearance.dynamicTypeSize)
        }
        .sheet(isPresented: $showSectionList) {
            SectionListSheet(current: $section)
                .preferredColorScheme(appearance.preferredScheme)
                .dynamicTypeSize(appearance.dynamicTypeSize)
        }
        .onChange(of: jump.target) { _, newValue in
            guard let newValue else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) {
                section = newValue
            }
            jump.target = nil
        }
        .onChange(of: section) { _, _ in
            // 换页时新页从顶部开始，头部要跟着复位
            scrollOffset = 0
        }
    }

    // MARK: 单页内容

    /// 每个栏目一页，只承载卡片。
    ///
    /// 顶部留出 `topInset`（安全区 + 头部高度）作为空白，
    /// 刚打开时内容正好从头部下方开始；往上滚时内容滑到头部底下，
    /// 而头部自己也同步上移，看起来就是「一起滚走的」。
    private func page(_ item: Section, topInset: CGFloat, safeBottom: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Color.clear.frame(height: max(0, topInset))

                switch item {
                case .income: IncomeSectionView()
                case .special: SpecialSectionView()
                case .social: SocialSectionView()
                case .ytd: YtdSectionView()
                case .deduction: DeductionSectionView()
                case .overtime: OvertimeSectionView()
                }
            }
            .padding(.horizontal, 16)
            // 底部留出工具栏 + 安全区，滚到底时最后一张卡完整露出
            .padding(.bottom, dockHeight + safeBottom + 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // 把当前页的垂直偏移报给外面的头部用
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, value in
            scrollOffset = max(0, value)
        }
    }

    // MARK: 顶部

    /// 标题文字。齿轮按钮不在这里 —— 文字层要关闭触摸，
    /// 否则会挡住下面 ScrollView 的拖拽；按钮单独叠一层。
    private var headerText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("工资单")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(onWallpaper)
            Text(verbatim: "\(CityRepository.policy(for: store.state.cityId).name) · 第 \(Int(store.state.ytd.monthIndex)) 月")
                .font(.subheadline)
                .foregroundStyle(onWallpaperSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var gearButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(onWallpaper)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(glassVariant.interactive(), in: .circle)
        .accessibilityLabel("设置")
    }

    // MARK: 金额

    private var hero: some View {
        VStack(spacing: 0) {
            Text("¥\(Money.format(store.result.netPay))")
                .font(.system(size: 58, weight: .thin, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.2) : .snappy,
                    value: store.result.netPay
                )
            Text("本月实发到手")
                .font(.subheadline)
                .foregroundStyle(onWallpaperSecondary)
        }
        .foregroundStyle(onWallpaper)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .padding(.bottom, 6)
    }

    // MARK: 底部浮动工具栏
    //
    // 三个控件全是透明玻璃：
    //   左 / 右 —— 52pt 圆形
    //   中间   —— 52pt 高胶囊，里面是圆点
    // 间距 18pt，比之前松一些，和天气 App 那一排的呼吸感一致。

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // 左侧圆形贴边
            glassCircleButton(systemName: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            Spacer(minLength: 16)

            // 中间胶囊居中
            pageDots
                .padding(.horizontal, 12)
                .frame(height: 52)
                .glassEffect(glassVariant, in: .capsule)

            Spacer(minLength: 16)

            // 右侧圆形贴边
            glassCircleButton(systemName: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
    }

    /// 圆形玻璃按钮。
    ///
    /// 注意 `.glassEffect` 挂在 Button **外层**：挂在 label 上时，
    /// 玻璃层会自己接管命中测试，按钮收不到点击（左右两个"失效"就是这个原因）。
    /// 同时用 `.contentShape(Circle())` 明确命中区域。
    private func glassCircleButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(onWallpaper)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(glassVariant.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    /// 圆点：点任意一个直接跳过去；选中的拉长成短横线
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) {
                        section = item
                    }
                } label: {
                    Capsule()
                        .fill(section == item ? onWallpaper : onWallpaper.opacity(0.45))
                        .frame(width: section == item ? 20 : 7, height: 7)
                        .frame(width: 18, height: 44)   // 触摸目标够大，视觉上仍是小圆点
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(section == item ? [.isSelected] : [])
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: section)
    }
}

// MARK: - 栏目跳转

/// 栏目列表里点某一项时，通过 environment 把目标传回 RootView。
@Observable
final class SectionJump {
    var target: RootView.Section?
}

extension EnvironmentValues {
    @Entry var sectionJump = SectionJump()
}
