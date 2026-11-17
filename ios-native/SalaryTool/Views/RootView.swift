//
//  RootView.swift
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  浮动玻璃条（不进状态栏）
//    ├──────────────────────────────┤
//    │        ¥9,692.33             │  跟卡片一起上下滚
//    │   [卡片]  ← 只有这块左右翻页    │
//    │  ◯        • • • • • •      ◯ │  浮动玻璃，贴底
//    └──────────────────────────────┘
//
//  这一版针对两个问题：
//  1. 顶栏玻璃推进了状态栏，又只有下方圆角 → 看着像个 U 形容器。
//     改成**浮动的圆角玻璃条**：四角同圆、左右留边距、位置在安全区下方，
//     完全不碰状态栏。
//  2. 底部玻璃和顶栏不是同一个构造。顶栏是「一大块玻璃条 + 内嵌圆钮」，
//     底部却是三个散落的玻璃。现在照抄顶栏结构：外面一块玻璃条，
//     三个控件嵌在里面，各自再有一层小玻璃。
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

    @State private var scrollOffset: CGFloat = 0
    /// 顶栏整块（含上下留白）的实测高度
    @State private var headerHeight: CGFloat = 120

    private let dockHeight: CGFloat = 52
    /// 玻璃条的圆角，顶栏和底部统一
    private let glassRadius: CGFloat = 22
    /// 浮动的玻璃条左右各留出的边距
    private let glassInset: CGFloat = 12

    // MARK: 颜色

    private var onWallpaper: Color {
        appearance.prefersWhiteText(system: systemScheme) ? .white : .black
    }

    private var onWallpaperSecondary: Color {
        appearance.prefersWhiteText(system: systemScheme)
            ? Color.white.opacity(0.75)
            : Color.black.opacity(0.55)
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

                // ① 内容：每页自带 ScrollView，尺寸钉死（否则 .page 会居中）
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
                .frame(width: proxy.size.width, height: proxy.size.height)

                // ② 金额：在 TabView 之外 → 翻页不动，随纵向上移
                hero
                    .padding(.top, headerHeight + 6)
                    .offset(y: -scrollOffset)
                    .opacity(heroOpacity)
                    .allowsHitTesting(false)

                // ③ 浮动玻璃顶栏（在安全区下方，不进状态栏）
                headerBlock(topPad: topPad)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                        headerHeight = value
                    }

                bottomBar
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, glassInset)
                    .padding(.bottom, max(safeBottom, 10) + 2)
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

    /// 每页一个 ScrollView。顶部放隐藏的真实视图当占位，
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
                headerBlock(topPad: topPad).hidden()
                hero.hidden()

                cardContent(item)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, dockHeight + safeBottom + 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
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

    private var heroOpacity: Double {
        max(0, 1 - Double(scrollOffset) / 120)
    }

    // MARK: 顶栏（浮动玻璃条）

    /// 顶栏整块：玻璃条 + 上下留白。外层只负责定位，玻璃形状在 headerBar 里。
    private func headerBlock(topPad: CGFloat) -> some View {
        headerBar
            .padding(.horizontal, glassInset)
            .padding(.top, topPad)
            .padding(.bottom, 8)
    }

    /// 浮动玻璃条本身：四角同圆、左右留边距，完全在状态栏下方。
    private var headerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("工资单")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(onWallpaper)
                Text(verbatim: "\(CityRepository.policy(for: store.state.cityId).name) · 第 \(Int(store.state.ytd.monthIndex)) 月")
                    .font(.footnote)
                    .foregroundStyle(onWallpaperSecondary)
            }

            Spacer(minLength: 8)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(onWallpaper)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: glassRadius))
    }

    // MARK: 金额

    private var hero: some View {
        VStack(spacing: 0) {
            Text("¥\(Money.format(store.result.netPay))")
                .font(.system(size: 56, weight: .thin, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.2) : .snappy,
                    value: store.result.netPay
                )
            Text("本月实发到手")
                .font(.footnote)
                .foregroundStyle(onWallpaperSecondary)
        }
        .foregroundStyle(onWallpaper)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: 底部工具栏

    /// 结构与顶栏**完全一致**：一块大玻璃条 + 里面嵌小玻璃控件。
    ///
    /// 之前底部是三个散落的玻璃（还套了 GlassEffectContainer），
    /// 和顶栏「一大块 + 内嵌圆钮」的构造不一样，观感自然也不同。
    /// 顶栏既然没问题，就直接照抄它的结构。
    private var bottomBar: some View {
        HStack(spacing: 10) {
            glassCircleButton(systemName: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            pageDots
                .padding(.horizontal, 12)
                .frame(height: 44)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            glassCircleButton(systemName: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: glassRadius))
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
                .frame(width: 40, height: 40)
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
