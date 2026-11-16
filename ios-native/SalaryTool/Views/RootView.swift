//
//  RootView.swift
//  布局参照 iOS 自带的「天气」App：
//
//    ┌──────────────────────────────┐
//    │ 工资单                    ⚙   │  大标题 + 右上角设置
//    │ 上海 · 第 11 月               │
//    │                              │
//    │        ¥9,692.33             │  金额像气温一样居中放大
//    │        本月实发到手            │  点一下看明细
//    │                              │
//    │   [收入项卡片]                │
//    │   [卡片]                      │  左右滑动切换六个栏目
//    │   [卡片]                      │
//    │                              │
//    │  ┌─────────────────────────┐ │
//    │  │ ⬚   ‹ ● ● ○ ○ ○ ○ ›   ☰ │ │  底部浮动工具栏
//    │  └─────────────────────────┘ │
//    └──────────────────────────────┘
//
//  左：明细    中：圆点翻页    右：栏目列表
//

import SwiftUI

struct RootView: View {
    @Environment(SalaryStore.self) private var store
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
            WallpaperView()

            VStack(spacing: 0) {
                header
                hero

                pager
                    // 给底部工具栏留出空间，内容不会滚到它底下
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 84)
                    }
            }

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showDetail) { DetailView() }
        .sheet(isPresented: $showSectionList) {
            SectionListSheet(current: $section)
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
                    .background {
                        Circle().fill(.white.opacity(0.18))
                            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: 金额（像气温那样居中）

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

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton(symbol: "list.bullet.rectangle", label: "明细") {
                showDetail = true
            }

            Spacer(minLength: 2)

            pageDots

            Spacer(minLength: 2)

            barButton(symbol: "square.grid.2x2", label: "栏目列表") {
                showSectionList = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        }
    }

    private func barButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(.primary.opacity(0.07))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 圆点翻页指示：点任意圆点直接跳过去
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)) {
                        section = item
                    }
                } label: {
                    Capsule()
                        .fill(section == item ? Color.primary : Color.primary.opacity(0.26))
                        .frame(width: section == item ? 18 : 7, height: 7)
                        .frame(width: 20, height: 44)   // 触摸目标够大，视觉上仍是小圆点
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
