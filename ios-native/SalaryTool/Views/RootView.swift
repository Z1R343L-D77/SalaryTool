//
//  RootView.swift
//  主界面：大标题 + 横向栏目 + 单列内容 + 底部常驻金额。
//
//  布局参照 iOS 自带的「天气」App：
//  - 大标题和小字副标题压在壁纸上（时间/地点那种层级）
//  - 内容是一张张独立的圆角玻璃卡，卡与卡之间留一个手指宽的间距
//  - 底部一条常驻摘要，随时能点开看明细
//
//  材质用 iOS 26 的 `.glassEffect()`，这是系统在 GPU 上算的分层模糊 + 折射，
//  WebView 的 backdrop-filter 做不到。
//

import SwiftUI

struct RootView: View {
    @Environment(SalaryStore.self) private var store
    @State private var section: Section = .income
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showDetail = false

    enum Section: String, CaseIterable, Identifiable {
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
    }

    var body: some View {
        ZStack {
            // 壁纸：和 Windows 版同一张，压暗后铺满
            WallpaperView()

            VStack(spacing: 0) {
                header
                tabBar
                content
                Spacer(minLength: 0)
                dock
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showImport) { ImportView() }
        .sheet(isPresented: $showDetail) { DetailView() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("工资单")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.6)
                Text("\(CityRepository.policy(for: store.state.cityId).name) · 第 \(Int(store.state.ytd.monthIndex)) 月")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                GlassIconButton(systemName: "square.and.arrow.down") {
                    showImport = true
                }
                GlassIconButton(systemName: "gearshape") {
                    showSettings = true
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: 栏目切换

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { section = item }
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                            if let badge = badge(for: item), !badge.isEmpty {
                                Text(badge)
                                    .font(.caption2)
                                    .opacity(0.75)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .foregroundStyle(section == item ? Color.white : Color.primary)
                        .background {
                            if section == item {
                                Capsule().fill(Color.accentColor)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func badge(for section: Section) -> String? {
        let r = store.result
        switch section {
        case .income: return "\(store.state.incomes.count)"
        case .special:
            return r.specialDeductionTotal > 0
                ? Money.formatInteger(r.specialDeductionTotal) : nil
        case .social:
            return r.social.total > 0 ? Money.formatInteger(r.social.total) : nil
        case .ytd: return "第\(Int(store.state.ytd.monthIndex))月"
        case .deduction:
            return store.state.deductions.isEmpty ? nil : "\(store.state.deductions.count)"
        case .overtime: return nil
        }
    }

    // MARK: 内容

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch section {
                case .income: IncomeSectionView()
                case .special: SpecialSectionView()
                case .social: SocialSectionView()
                case .ytd: YtdSectionView()
                case .deduction: DeductionSectionView()
                case .overtime: OvertimeSectionView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: 底部常驻

    private var dock: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("本月实发到手")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("税前 \(Money.format(store.result.grossIncome))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("¥\(Money.format(store.result.netPay))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: store.result.netPay)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if #available(iOS 26, *) {
                    // 26 起：系统材质，随下层内容实时折射
                    Rectangle().fill(.clear).glassEffect(.regular)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 小部件

/// 圆形玻璃图标按钮
struct GlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background {
                    if #available(iOS 26, *) {
                        Circle().fill(.clear).glassEffect(.regular.interactive())
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// 壁纸层：压暗的实景图，让上面的白色文字可读
struct WallpaperView: View {
    var body: some View {
        GeometryReader { geo in
            Image("wallpaper")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.28), .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
        }
    }
}
