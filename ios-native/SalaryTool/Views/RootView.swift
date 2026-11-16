//
//  RootView.swift
//  结构照 iOS 天气 App：
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  ┐
//    │ 上海 · 第 11 月               │  │ 全部在 ScrollView 里，
//    │        ¥9,692.33             │  │ 上下滚动时一起走
//    │        本月实发到手            │  ┘
//    │                              │
//    │   [卡片]  ← 只有这块左右翻页    │
//    │                              │
//    │  ◯        • • • • • •      ◯ │  ← 底部工具栏，永远不动
//    └──────────────────────────────┘
//
//  两个方向的手势严格分开：
//  - 上下滚：标题、金额、卡片一起滚（都在同一个 ScrollView 里）
//  - 左右翻：只有卡片区在翻，标题和金额纹丝不动（它们在 TabView 之外）
//
//  卡片区用 TabView + 实测高度：TabView 嵌在 ScrollView 里必须有确定高度，
//  所以每页用 GeometryReader 量出自身高度，取当前页的那个当 frame。
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

    /// 每页卡片的实测高度。TabView 嵌在 ScrollView 里必须有确定高度。
    @State private var pageHeights: [Section: CGFloat] = [:]

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
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack(alignment: .bottom) {
                WallpaperView()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        headerRow
                        hero
                        cardsPager
                    }
                    .padding(.horizontal, 16)
                    // 底部留出工具栏 + 安全区，滚到底时最后一张卡完整露出
                    .padding(.bottom, dockHeight + safeBottom + 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(safeBottom, 8) + 2)
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
    }

    // MARK: 标题行（标题 + 齿轮，左右对齐）

    private var headerRow: some View {
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
        .padding(.top, 8)
        .padding(.bottom, 4)
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

    private var cardsPager: some View {
        TabView(selection: $section) {
            ForEach(Section.allCases) { item in
                cardContent(item)
                    .background {
                        // 量出每页高度，TabView 才有确定的 frame
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { pageHeights[item] = geo.size.height }
                                .onChange(of: geo.size.height) { _, value in
                                    pageHeights[item] = value
                                }
                        }
                    }
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: pageHeights[section] ?? 620)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: pageHeights[section])
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
