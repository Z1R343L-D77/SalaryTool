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
/// HIG 里 Liquid Glass 是**控件层**的材质（工具栏、标签栏、浮动按钮），
/// 明确不建议用作内容背景或大面积容器。所以内容卡用系统的语义材质
/// `.regularMaterial` —— 它会随「增强对比度」「降低透明度」自动调整，
/// 而玻璃不会。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
    }
}

/// 卡片里的小块：比外层亮一档的填充，不透明、不模糊
struct InsetPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.primary.opacity(0.055))
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
