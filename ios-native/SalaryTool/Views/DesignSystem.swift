//
//  DesignSystem.swift
//  iOS 26 的视觉语言：玻璃卡、分组、胶囊开关。
//
//  三条规则，和桌面版刻意区分开：
//  1. 卡片是「独立的一块」——圆角 26，卡与卡之间留 12pt，不是连续的分组条
//  2. 不画描边。层次靠材质的厚度和明度差，不靠 1px 线
//  3. 可点区域一律 ≥44pt，按下有轻微缩放
//

import SwiftUI

// MARK: - 卡片

/// 内容卡。
///
/// 用 `.glassEffect` 而不是 `.regularMaterial`。
///
/// 材质（Material）是「在颜色上叠一层模糊」，本身带相当高的白/黑底色，
/// 浅色模式下几乎是不透明的浅灰 —— 壁纸完全被盖住。
/// 玻璃（glassEffect）是采样背后内容再折射，底子更薄，壁纸能透上来。
///
/// 顶栏和底部用的就是 glassEffect，卡片换成同一种材质后
/// 整个界面才是同一个层的观感。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
    }
}

/// 卡片里的小块：比卡片再亮一档的填充。
/// 用很低的透明度，不挡住下面已经透上来的壁纸。
struct InsetPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(scheme == .dark ? 0.055 : 0.045))
            }
    }
}

// MARK: - 标题

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 开关胶囊

/// 替代 Toggle：一排胶囊，点亮即生效。
/// 比 Switch 更适合「三项里任意组合」这种语义。
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { isOn.toggle() }
        } label: {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background {
                    Capsule()
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.07))
                }
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// 按下时轻微缩小。
/// HIG：减弱动态效果时不做缩放，只保留颜色反馈。
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.95 : 1))
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.14),
                value: configuration.isPressed
            )
    }
}

// MARK: - 金额输入

/// 金额输入框：右侧对齐、等宽数字、点进去全选
struct AmountField: View {
    @Binding var value: Double
    var suffix: String = "元"
    var precision: Int = 2

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .focused($focused)
                .onAppear { text = display }
                .onChange(of: value) { _, _ in
                    if !focused { text = display }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        text = plain
                    } else {
                        commit()
                    }
                }

            Text(suffix)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(focused ? 0.09 : 0.055))
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    private var display: String {
        precision == 2 ? Money.format(value) : Money.formatPrecise(value)
    }

    private var plain: String {
        let scaled = Money.round(value, digits: precision)
        return scaled == scaled.rounded()
            ? String(Int(scaled))
            : String(format: "%.\(precision)f", scaled)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let parsed = Double(cleaned) ?? value
        value = Money.round(max(0, parsed), digits: precision)
        text = display
    }
}

// MARK: - 百分比输入

/// 百分比输入框。内部值是小数字（0.08），界面显示 8 %。
///
/// 和 AmountField 分开，是因为换算方式不同：这里要 ×100 显示、
/// ÷100 存回，而且小数位要允许 4 位（社保比例有时精确到万分位）。
struct PercentField: View {
    @Binding var value: Double
    var max: Double = 1

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
                .focused($focused)
                .onAppear { text = display }
                .onChange(of: value) { _, _ in
                    if !focused { text = display }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused { text = plain } else { commit() }
                }

            Text("%")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(focused ? 0.09 : 0.055))
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    private var display: String {
        let percent = Money.round(value * 100, digits: 4)
        return percent == percent.rounded()
            ? String(Int(percent))
            : String(format: "%.4f", percent)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private var plain: String { display }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: "%", with: "")
        let parsed = Double(cleaned) ?? (value * 100)
        let clamped = min(max * 100, max(0, parsed))
        value = Money.round(clamped / 100, digits: 6)
        text = display
    }
}

// MARK: - 命名输入

struct LabelField: View {
    @Binding var text: String
    var placeholder: String = "名称"

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 17, weight: .medium))
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.vertical, 4)
    }
}

// MARK: - 分段控件

struct SegmentedPicker<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.primary.opacity(0.055))
        }
    }
}

// MARK: - 行

/// 键值行：左边标签，右边数值
struct StatRow: View {
    let label: String
    let value: String
    var emphasis: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(emphasis ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(emphasis ? .primary : .primary)
        }
        .padding(.vertical, 9)
    }
}
