//
//  RootView.swift
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  ← 固定，毛玻璃背景
//    ├──────────────────────────────┤
//    │        ¥9,692.33             │  ┐
//    │        本月实发到手            │  │ 跟着卡片一起滚
//    │   [卡片]                      │  │
//    │   [卡片]  ← 只有这块左右翻页    │  ┘
//    │                              │
//    │  ◯        • • • • • •      ◯ │  ← 固定，贴底
//    └──────────────────────────────┘
//
//  三个方向的行为严格分开：
//  - 上下滚：标题不动（毛玻璃浮起），金额和卡片一起滚
//  - 左右翻：只有卡片区在翻，金额不动（它在 TabView 之外）
//  - 横滑不跳：五页共用最大高度 + 顶部对齐，见 cardsPager
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

    /// 每页卡片的实测高度。TabView 嵌在 ScrollView 里必须有确定高度，
    /// 而且五页共用最大高度，否则横滑时高度跳动。
    @State private var pageHeights: [Section: CGFloat] = [:]

    /// 当前滚动偏移，用来让固定标题的背景渐变浮现
    @State private var scrollOffset: CGFloat = 0
    /// 固定标题栏的实测高度，滚动内容顶部要给它让位
    @State private var headerHeight: CGFloat = 0

    private let dockHeight: CGFloat = 52

    /// 压在壁纸上的文字该用白色还是深色（见 AppearanceStore）
    private var onWallpaper: Color {
        appearance.prefersWhiteText(system: systemScheme) ? .white : .black
    }

    private var onWallpaperSecondary: Color {
        appearance.prefersWhiteText(system: systemScheme)
            ? Color.white.opacity(0.75)
            : Color.black.opacity(0.55)
    }

    /// 玻璃材质厚度：浅色主题下 .regular 太实，用 .clear
    private var glassVariant: Glass {
        systemScheme == .dark ? .regular : .clear
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

            ZStack(alignment: .top) {
                WallpaperView()

                // 内容可以滚到状态栏底下（被固定标题的毛玻璃盖住）
                ScrollView {
                    VStack(spacing: 0) {
                        // 给固定标题让位
                        Color.clear.frame(height: headerHeight)
                        hero
                        cardsPager
                    }
                    .padding(.horizontal, 16)
                    // 底部留出工具栏 + 安全区，滚到底时最后一张卡完整露出
                    .padding(.bottom, dockHeight + safeBottom + 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, value in
                    scrollOffset = max(0, value)
                }

                // 固定标题：上下滚不动，左右翻也不动（在 TabView 之外）
                headerBar(topPad: safeTop + 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                        headerHeight = value
                    }

                bottomBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeBottom > 0 ? safeBottom + 2 : 10)
            }
            .ignoresSafeArea()
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
    }

    // MARK: 固定标题栏（标题 + 齿轮，毛玻璃背景）

    /// 标题栏固定在顶部。背景是毛玻璃，滚动时内容从它下面穿过。
    ///
    /// 背景透明度跟随滚动偏移：起始位置完全透明，滚动 24pt 后变实。
    /// 这样一打开看见的是干净的壁纸，滚起来才有「导航栏浮上来」的感觉。
    private func headerBar(topPad: CGFloat) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("工资单")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(onWallpaper)
                Text(verbatim: "\(CityRepository.policy(for: store.state.cityId).name) · 第 \(Int(store.state.ytd.monthIndex)) 月")
                    .font(.subheadline)
                    .foregroundStyle(onWallpaperSecondary)
            }

            Spacer(minLength: 12)

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
        .padding(.horizontal, 16)
        .padding(.top, topPad)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(backgroundOpacity)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// 滚动 24pt 内背景由透明变实
    private var backgroundOpacity: Double {
        min(1, Double(scrollOffset) / 24)
    }

    // MARK: 金额

    private var hero: some View {
        Button {
            showDetail = true
        } label: {
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
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 14)
    }

    // MARK: 卡片区（只有这块左右翻页）

    /// 左右翻页的高度必须**稳定**，否则每页高度不同会导致：
    /// TabView 换 frame → 内容垂直居中 → 短页看起来「更低」，
    /// 横滑时就是从下面往上冒出来。
    ///
    /// 所以取所有页的最大高度当固定 frame，并让每页顶部对齐。
    private var cardsPagerHeight: CGFloat {
        pageHeights.values.max() ?? 620
    }

    private var cardsPager: some View {
        TabView(selection: $section) {
            ForEach(Section.allCases) { item in
                cardContent(item)
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { pageHeights[item] = geo.size.height }
                                .onChange(of: geo.size.height) { _, value in
                                    pageHeights[item] = value
                                }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: cardsPagerHeight)
    }

    @ViewBuilder
    private func cardContent(_ item: Section) -> some View {
        VStack(spacing: 12) {
            switch item {
            case .income: IncomeSectionView()
            case .special: SpecialSectionView()
            case .social: SocialSectionView()
            case .ytd: YtdSectionView()
            case .deduction: DeductionSectionView()
            case .overtime: OvertimeSectionView()
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: 底部浮动工具栏

    private var bottomBar: some View {
        HStack(spacing: 0) {
            glassCircleButton(systemName: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            Spacer(minLength: 16)

            pageDots
                .padding(.horizontal, 12)
                .frame(height: 52)
                .glassEffect(glassVariant, in: .capsule)

            Spacer(minLength: 16)

            glassCircleButton(systemName: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
    }

    /// 圆形玻璃按钮。
    ///
    /// `.glassEffect` 必须挂在 Button **外层**：挂在 label 上时玻璃层会
    /// 接管命中测试，按钮收不到点击。同时用 contentShape 明确命中区域。
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
