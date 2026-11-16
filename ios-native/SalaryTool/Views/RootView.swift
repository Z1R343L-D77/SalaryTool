//
//  RootView.swift
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  固定，Liquid Glass 通栏
//    ├──────────────────────────────┤
//    │        ¥9,692.33             │  跟卡片一起上下滚
//    │   [卡片]  ← 只有这块左右翻页    │
//    │  ◯        • • • • • •      ◯ │  固定，贴底
//    └──────────────────────────────┘
//
//  这一版重点修两件事：
//  1. 玻璃背景是**独立一层**，铺满整条顶栏并延伸到状态栏后面。
//     之前把它挂在 headerBar 的 .background 上，再叠 ignoresSafeArea，
//     量出来的高度会把安全区算两遍，玻璃只覆盖到一半屏幕。
//     —— 你看到的「上面那块灰色横条到此为止」就是这个。
//  2. TabView 必须显式钉死尺寸。ZStack 里不给尺寸它会缩到内容高度，
//     .page 再把内容垂直居中 → 卡片落到屏幕中间。
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

    /// 当前页的滚动偏移（金额层按它上移）
    @State private var scrollOffset: CGFloat = 0
    /// 顶栏内容（含安全区）的实测高度。只量内容，不含量背景。
    @State private var headerHeight: CGFloat = 120

    private let dockHeight: CGFloat = 52

    // MARK: 颜色与材质

    private var onWallpaper: Color {
        appearance.prefersWhiteText(system: systemScheme) ? .white : .black
    }

    private var onWallpaperSecondary: Color {
        appearance.prefersWhiteText(system: systemScheme)
            ? Color.white.opacity(0.75)
            : Color.black.opacity(0.55)
    }

    /// 玻璃上的额外着色：深色壁纸 + 深色玻璃会糊成一片，叠一层黑把边界立住
    private var glassTint: Color {
        systemScheme == .dark ? .black.opacity(0.14) : .black.opacity(0.03)
    }

    enum Section: String, CaseIterable, Identifiable, Hashable {
        case income, special, social, ytd, deduction, overtime

        var id: String { rawValue }

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

    // MARK: 主体

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let topPad = safeTop + 6

            ZStack(alignment: .top) {
                WallpaperView()

                // ① 内容：每页自带 ScrollView，撑满整屏
                TabView(selection: $section) {
                    ForEach(Section.allCases) { item in
                        sectionPage(
                            item,
                            topPad: topPad,
                            safeBottom: safeBottom,
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // 必须钉死，否则 .page 会垂直居中内容
                .frame(width: proxy.size.width, height: proxy.size.height)

                // ② 金额：在 TabView 之外 → 左右翻页不动；
                //    按滚动偏移上移 → 上下滚时跟着走
                hero
                    .padding(.top, headerHeight + 2)
                    .offset(y: -scrollOffset)
                    .opacity(heroOpacity)
                    .allowsHitTesting(false)

                // ③ 玻璃背景：独立一层，通栏、覆盖状态栏
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 0))
                    .overlay { Rectangle().fill(glassTint) }
                    .frame(maxWidth: .infinity)
                    .frame(height: headerHeight)
                    .allowsHitTesting(false)

                // ④ 顶栏内容（标题 + 齿轮）
                headerContent(topPad: topPad)
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

    // MARK: 单页

    /// 每页一个 ScrollView。顶部放**隐藏的真实视图**当占位，
    /// 高度天然和浮动层一致，不需要任何测量相加。
    private func sectionPage(
        _ item: Section,
        topPad: CGFloat,
        safeBottom: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                headerContent(topPad: topPad).hidden()
                hero.hidden()

                cardContent(item)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, dockHeight + safeBottom + 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // 内容从屏幕最顶端开始（被玻璃顶栏盖住），别再叠一次安全区
        .contentMargins(.top, 0, for: .scrollContent)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, value in
            if item == section { scrollOffset = value }
        }
        .frame(width: width, height: height, alignment: .top)
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

    /// 金额随滚动上移并淡出
    private var heroOpacity: Double {
        max(0, 1 - Double(scrollOffset) / 120)
    }

    // MARK: 顶栏内容

    /// 标题 + 齿轮。**不含背景** —— 背景是 ZStack 里的独立一层，
    /// 这样这里量出来的高度不会和安全区互相干扰。
    private func headerContent(topPad: CGFloat) -> some View {
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
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, topPad)
        .padding(.bottom, 10)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .padding(.bottom, 8)
    }

    // MARK: 底部工具栏

    private var bottomBar: some View {
        HStack(spacing: 0) {
            glassCircleButton(systemName: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            Spacer(minLength: 16)

            pageDots
                .padding(.horizontal, 12)
                .frame(height: 52)
                .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 16)

            glassCircleButton(systemName: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
    }

    /// `.glassEffect` 必须挂在 Button 外层，挂在 label 上会吞掉点击
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
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

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
                        .frame(width: 18, height: 44)
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

@Observable
final class SectionJump {
    var target: RootView.Section?
}

extension EnvironmentValues {
    @Entry var sectionJump = SectionJump()
}
