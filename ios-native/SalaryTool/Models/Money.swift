//
//  Money.swift
//  金额取整与格式化，和 shared/money.ts 保持一致。
//

import Foundation

enum Money {
    /// 四舍五入到 n 位小数
    static func round(_ value: Double, digits: Int = 2) -> Double {
        guard value.isFinite else { return 0 }
        let factor = pow(10.0, Double(digits))
        return (value * factor).rounded() / factor
    }

    static func round2(_ value: Double) -> Double { round(value, digits: 2) }

    /// 小时工资这类折算值保留四位，避免误差被工时放大
    static func round4(_ value: Double) -> Double { round(value, digits: 4) }

    static func clamp(_ value: Double, _ min: Double, _ max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    static func nonNegative(_ value: Double) -> Double {
        value.isFinite ? Swift.max(0, value) : 0
    }

    // MARK: - 格式化

    private static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "zh_CN")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let preciseFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "zh_CN")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f
    }()

    /// 12345.6 -> "12,345.60"
    static func format(_ value: Double) -> String {
        moneyFormatter.string(from: NSNumber(value: round2(value))) ?? "0.00"
    }

    /// 小时工资用：22.3250 -> "22.325"
    static func formatPrecise(_ value: Double) -> String {
        preciseFormatter.string(from: NSNumber(value: round4(value))) ?? "0.00"
    }

    /// 0.0325 -> "3.25%"
    static func formatRate(_ rate: Double, digits: Int = 2) -> String {
        let percent = round2(rate * 100)
        if digits == 0 { return "\(Int(percent.rounded()))%" }
        var text = String(format: "%.\(digits)f", percent)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "%"
    }

    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "zh_CN")
        f.maximumFractionDigits = 0
        return f
    }()

    static func formatInteger(_ value: Double) -> String {
        integerFormatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }
}
