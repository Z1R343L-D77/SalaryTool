//
//  RootView.swift
//  布局参照 iOS 自带的「天气」App：
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  大标题压在壁纸上
//    │ 上海 · 第 11 月               │
//    │        ¥9,692.33             │  金额像气温一样居中放大
//    │        本月实发到手            │
//    │                              │
//    │   [内容卡片，可上下滑]         │
//    │   [卡片]                      │
//    │                              │
//    │  ◯        • • • • • •      ◯ │  底部浮动玻璃工具栏
//    └──────────────────────────────┘
//
//  三个要点：
//  1. 壁纸与内容都铺满到状态栏 / Home 指示条底下，没有任何硬边界；
//     只有文字和控件按安全区内缩。
//  2. 底部三个控件是**透明 Liquid Glass**：左右两个圆形 + 中间胶囊，
//     尺寸对齐天气 App 那一排。
//  3. 深浅色切换必须作用到弹出的 sheet —— sheet 是独立的呈现上下文，
//     不会继承根视图的 preferredColorScheme，要在每个 sheet 内容上再挂一次。
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
        ZStack(alignment: .bottom) {
            // 壁纸铺满整屏（含状态栏与 Home 指示条区域）
            WallpaperView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                hero

                pager
                    // 底部工具栏是浮动的，内容要能滚到它底下
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 72)
                    }
            }

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
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
        .padding(.top, 2)
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
    }

    // MARK: 翻页内容

    private var pager: some View {
        TabView(selection: $section) {
            ForEach(Section.allCases) { item in
                sectionContent(item)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func sectionContent(_ item: Section) -> some View {
        ScrollView {
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
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 底部浮动工具栏
    //
    // 三个控件全是**透明玻璃**，尺寸对齐天气 App 那一排：
    //   左 / 右 —— 52pt 圆形（.glassEffect 的 circle 形状）
    //   中间   —— 52pt 高的胶囊，里面是圆点
    // 玻璃会随下方壁纸实时折射，不是一块半透明灰。

    private var bottomBar: some View {
        HStack(spacing: 12) {
            glassCircleButton(systemName: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            pageDots
                .padding(.horizontal, 4)
                .frame(height: 52)
                .glassEffect(.regular, in: .capsule)

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
