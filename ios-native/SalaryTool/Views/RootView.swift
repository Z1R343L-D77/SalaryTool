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
//  - 横滑不跳：每页自带 ScrollView，页面高度天然等于屏幕
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

    /// 当前滚动偏移，用来让固定标题的背景渐变浮现
    @State private var scrollOffset: CGFloat = 0
    /// 固定标题栏的实测高度，滚动内容顶部要给它让位
    @State private var headerHeight: CGFloat = 0
    /// 金额块的实测高度，同样用于内容占位
    @State private var heroHeight: CGFloat = 96

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

                // 每页自带 ScrollView：内容多长就多长，短页不会留空白，
                // 也不存在「切页时 frame 变高变矮」的问题。
                TabView(selection: $section) {
                    ForEach(Section.allCases) { item in
                        sectionPage(item, safeBottom: safeBottom)
                            .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // 金额：在 TabView 之外，所以左右翻页不动；
                // 按当前页的滚动偏移上移，所以上下滚时跟着走。
                hero
                    .padding(.top, headerHeight + 2)
                    .offset(y: -scrollOffset)
                    .opacity(heroOpacity)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                        heroHeight = value
                    }

                // 固定标题：Liquid Glass 背景，滚动内容从它下面穿过
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

    // MARK: 单页

    /// 每个栏目一页，自带 ScrollView。
    ///
    /// 顶部留出「标题栏 + 金额」的高度当占位，内容不会一上来就压在它们下面；
    /// 滚动偏移会上报给外面的金额层，让它同步上移。
    private func sectionPage(_ item: Section, safeBottom: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // 标题栏 + 金额占的高度
                Color.clear.frame(height: headerHeight + heroHeight + 6)

                cardContent(item)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, dockHeight + safeBottom + 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, value in
            // 只有当前页的偏移参与计算：滑动过程中相邻页也会上报，
            // 全收会让金额来回跳。
            if item == section {
                scrollOffset = max(0, value)
            }
        }
    }

    /// 金额随滚动上移，移出标题栏后淡出
    private var heroOpacity: Double {
        let travelled = Double(scrollOffset)
        return max(0, 1 - travelled / 120)
    }



    // MARK: 固定标题栏（标题 + 齿轮，Liquid Glass 背景）

    /// 标题栏固定在顶部，背景是 iOS 26 的 Liquid Glass。
    ///
    /// 和上一版的区别：之前用 `.ultraThinMaterial`（系统模糊材质，只是把
    /// 后面的内容糊掉），现在用 `.glassEffect` —— 会折射背景、带镜面高光
    /// 和边缘光，滚上来的内容是"透过一块玻璃"看到的。
    ///
    /// 起始位置玻璃完全透明（看见干净壁纸），滚 24pt 内渐变到实心。
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
                .fill(.clear)
                .glassEffect(glassVariant, in: .rect(cornerRadius: 0))
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
    }

    // MARK: 卡片内容

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
