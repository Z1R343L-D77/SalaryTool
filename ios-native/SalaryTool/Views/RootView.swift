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
//  1. TabView 铺满整屏（忽略安全区）。之前它只占「标题下方」那块，
//     于是滚动内容被裁在一条硬边线上 —— 卡片顶部的圆角被切掉，
//     看起来就是一个「四四方方的框」。铺满后裁切线落在屏幕外，看不见。
//  2. 标题和金额放进每一页的滚动内容里，所以往下滑它们会自然滑走，
//     不会像之前那样压在内容上方、还留一块空白。
//  3. 内容底部留出工具栏高度 + 安全区，滚到底时最后一张卡完整露出，
//     不会被玻璃挡住。
//  4. 底部三个控件都是透明 Liquid Glass：左右 52pt 圆形 + 中间胶囊。
//

import SwiftUI

struct RootView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sectionJump) private var jump

    @State private var section: Section = .income
    @State private var showSettings = false
    @State private var showDetail = false
    @State private var showSectionList = false

    /// 底部工具栏本体高度（52）加上下留白，用于计算滚动内容的底部余量
    private let dockHeight: CGFloat = 52

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

            ZStack(alignment: .bottom) {
                WallpaperView()

                TabView(selection: $section) {
                    ForEach(Section.allCases) { item in
                        page(item, safeTop: safeTop, safeBottom: safeBottom)
                            .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // 内容可以一直滑到状态栏和 Home 指示条底下
                .ignoresSafeArea()

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(safeBottom, 8) + 2)
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

    // MARK: 单页：标题 + 金额 + 内容，整体一起滚动

    private func page(_ item: Section, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                hero

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
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            // 顶部留出状态栏高度：刚打开时标题在刘海下面
            .padding(.top, safeTop + 4)
            // 底部留出工具栏 + 安全区，滚到底时最后一张卡完整可见
            .padding(.bottom, dockHeight + safeBottom + 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("工资单")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                Text("\(CityRepository.policy(for: store.state.cityId).name) · 第 \(Int(store.state.ytd.monthIndex)) 月")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
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
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
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
                .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 16)

            // 右侧圆形贴边
            glassCircleButton(systemName: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
    }

    private func glassCircleButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
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
                        .fill(section == item ? Color.white : Color.white.opacity(0.45))
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
