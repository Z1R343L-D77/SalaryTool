//
//  Calculator.swift
//  薪水计算核心，逐行对照 shared/calculator.ts 与 shared/taxTables.ts。
//
//  为什么要在 Swift 里重写一遍而不是继续用 WebView：
//  只有原生视图才能拿到系统的 Liquid Glass 材质（iOS 26 起 SwiftUI 提供
//  `.glassEffect()` / `GlassEffectContainer`），那是 GPU 上实时计算的分层模糊
//  —— WebView 里的 backdrop-filter 只能做单层高斯模糊，没有折射、没有
//  随内容变化的着色，做不出 iOS 26 那种「真的是一块玻璃」的感觉。
//
//  重写风险的控制方式：算法逻辑与 TS 版一一对应，关键注释标明出处；
//  iOS 端有单元测试覆盖同样的用例（见 SalaryToolTests）。
//

import Foundation

// MARK: - 税率表

struct TaxBracket {
    let level: Int
    let lower: Double
    /// nil 表示无上限
    let upper: Double?
    let rate: Double
    let quickDeduction: Double
}

enum TaxTable {
    /// 综合所得年度税率表（累计预扣预缴使用）
    static let annual: [TaxBracket] = [
        .init(level: 1, lower: 0, upper: 36_000, rate: 0.03, quickDeduction: 0),
        .init(level: 2, lower: 36_000, upper: 144_000, rate: 0.10, quickDeduction: 2_520),
        .init(level: 3, lower: 144_000, upper: 300_000, rate: 0.20, quickDeduction: 16_920),
        .init(level: 4, lower: 300_000, upper: 420_000, rate: 0.25, quickDeduction: 31_920),
        .init(level: 5, lower: 420_000, upper: 660_000, rate: 0.30, quickDeduction: 52_920),
        .init(level: 6, lower: 660_000, upper: 960_000, rate: 0.35, quickDeduction: 85_920),
        .init(level: 7, lower: 960_000, upper: nil, rate: 0.45, quickDeduction: 181_920),
    ]

    /// 按月换算后的综合所得税率表（年终奖单独计税使用）
    static let monthly: [TaxBracket] = [
        .init(level: 1, lower: 0, upper: 3_000, rate: 0.03, quickDeduction: 0),
        .init(level: 2, lower: 3_000, upper: 12_000, rate: 0.10, quickDeduction: 210),
        .init(level: 3, lower: 12_000, upper: 25_000, rate: 0.20, quickDeduction: 1_410),
        .init(level: 4, lower: 25_000, upper: 35_000, rate: 0.25, quickDeduction: 2_660),
        .init(level: 5, lower: 35_000, upper: 55_000, rate: 0.30, quickDeduction: 4_410),
        .init(level: 6, lower: 55_000, upper: 80_000, rate: 0.35, quickDeduction: 7_160),
        .init(level: 7, lower: 80_000, upper: nil, rate: 0.45, quickDeduction: 15_160),
    ]

    /// 每月基本减除费用
    static let basicDeductionPerMonth: Double = 5_000

    static func bracket(for amount: Double, in table: [TaxBracket]) -> TaxBracket {
        let value = max(0, amount)
        for b in table {
            if b.upper == nil || value <= b.upper! { return b }
        }
        return table[table.count - 1]
    }

    /// 应纳税额 = 应纳税所得额 × 税率 − 速算扣除数
    static func tax(_ taxable: Double, in table: [TaxBracket]) -> Double {
        let amount = max(0, taxable)
        guard amount > 0 else { return 0 }
        let b = bracket(for: amount, in: table)
        return Money.round2(max(0, amount * b.rate - b.quickDeduction))
    }
}

// MARK: - 计算结果

struct SocialBreakdown {
    var pension: Double
    var medical: Double
    var unemployment: Double
    var housingFund: Double
    var medicalExtra: Double
    var total: Double
}

struct SalaryResult {
    // 收入
    var grossIncome: Double
    var taxableIncome: Double
    var socialBaseUsed: Double
    var housingFundBaseUsed: Double

    // 社保公积金
    var social: SocialBreakdown

    // 个税
    var specialDeductionTotal: Double
    var cumulativeTaxable: Double
    var cumulativeTax: Double
    var taxThisMonth: Double
    var effectiveTaxRate: Double

    // 年终奖
    var bonusGross: Double
    var bonusTax: Double

    // 到手
    var netPay: Double
}

// MARK: - 计算器

enum Calculator {
    /// 某项收入是否计入基数
    private static func sumIncomes(
        _ list: [IncomeItem],
        where predicate: (IncomeItem) -> Bool
    ) -> Double {
        Money.round2(
            list
                .filter { $0.amount > 0 && predicate($0) }
                .reduce(0) { $0 + Money.nonNegative($1.amount) }
        )
    }

    /// 参数名不能叫 min / max —— 会把 Swift 的同名函数遮蔽掉
    static func clampBase(_ base: Double, lower lowerBound: Double, upper upperBound: Double) -> Double {
        let value = Money.nonNegative(base)
        let lower = Money.nonNegative(lowerBound)
        let upper = upperBound > 0 ? Money.nonNegative(upperBound) : Double.infinity
        return Money.round2(Swift.min(Swift.max(value, lower), upper))
    }

    static func social(_ config: SocialConfig) -> SocialBreakdown {
        let socialBase = clampBase(config.socialBase, lower: config.socialBaseMin, upper: config.socialBaseMax)
        let fundBase = clampBase(
            config.housingFundBase,
            lower: config.housingFundBaseMin,
            upper: config.housingFundBaseMax
        )

        let pension = Money.round2(socialBase * Money.nonNegative(config.pensionRate))
        let medical = Money.round2(socialBase * Money.nonNegative(config.medicalRate))
        let unemployment =
            Money.round2(socialBase * Money.nonNegative(config.unemploymentRate))
        let housingFund = Money.round2(fundBase * Money.nonNegative(config.housingFundRate))
        let medicalExtra = Money.round2(Money.nonNegative(config.medicalExtra))

        return SocialBreakdown(
            pension: pension,
            medical: medical,
            unemployment: unemployment,
            housingFund: housingFund,
            medicalExtra: medicalExtra,
            total: Money.round2(pension + medical + unemployment + housingFund + medicalExtra)
        )
    }

    /// 年终奖单独计税：奖金 ÷ 12 查月度税率表
    static func bonusTaxSeparate(_ bonus: Double) -> Double {
        let amount = Money.nonNegative(bonus)
        guard amount > 0 else { return 0 }
        let b = TaxTable.bracket(for: amount / 12, in: TaxTable.monthly)
        return Money.round2(max(0, amount * b.rate - b.quickDeduction))
    }

    static func suggestSocialBase(_ incomes: [IncomeItem]) -> Double {
        sumIncomes(incomes) { $0.includeInSocialBase }
    }

    static func suggestHousingFundBase(_ incomes: [IncomeItem]) -> Double {
        sumIncomes(incomes) { $0.includeInHousingFundBase }
    }

    /// 把状态转换成参与计算的社会保险配置（自动模式下按收入推算基数）
    static func resolvedSocial(_ state: SalaryState) -> SocialConfig {
        var config = state.social
        if state.socialBaseMode == "auto" {
            config.socialBase = clampBase(
                suggestSocialBase(state.incomes),
                lower: state.social.socialBaseMin,
                upper: state.social.socialBaseMax
            )
        }
        if state.housingFundBaseMode == "auto" {
            config.housingFundBase = clampBase(
                suggestHousingFundBase(state.incomes),
                lower: state.social.housingFundBaseMin,
                upper: state.social.housingFundBaseMax
            )
        }
        return config
    }

    /// 取出真正参与计算的累计数据。
    ///
    /// 手填模式直接用 ytd；按月记录模式把 monthIndex 之前的记录加总。
    /// 「减除费用口径」和「在职月数」跟数据来源无关，两种模式都带上。
    static func resolveYtd(_ state: SalaryState) -> YtdTotals {
        guard state.ytdMode == "records" else { return state.ytd }

        let current = Int(min(12, max(1, state.ytd.monthIndex.rounded())))
        var latest: [Int: MonthRecord] = [:]
        for record in state.months {
            let month = Int(min(12, max(1, record.month.rounded())))
            guard month < current else { continue }
            latest[month] = record   // 同一个月只留最后一条
        }

        var income = 0.0, social = 0.0, special = 0.0, tax = 0.0
        for month in latest.keys.sorted() {
            let r = latest[month]!
            income += Money.nonNegative(r.taxableIncome)
            social += Money.nonNegative(r.socialDeduction)
            special += Money.nonNegative(r.specialDeduction)
            tax += Money.nonNegative(r.taxPaid)
        }

        return YtdTotals(
            monthIndex: Double(current),
            taxableIncome: Money.round2(income),
            socialDeduction: Money.round2(social),
            specialDeduction: Money.round2(special),
            taxPaid: Money.round2(tax),
            basicDeductionMode: state.ytd.basicDeductionMode,
            employedMonthIndex: state.ytd.employedMonthIndex,
            specialDeductionExact: true
        )
    }

    /// 本月之前缺记录的月份
    static func missingMonths(_ state: SalaryState) -> [Int] {
        guard state.ytdMode == "records" else { return [] }
        let current = Int(min(12, max(1, state.ytd.monthIndex.rounded())))
        let recorded = Set(state.months.map { Int($0.month.rounded()) })
        return (1..<current).filter { !recorded.contains($0) }
    }

    /// 计算当月到手。
    ///
    /// 累计预扣预缴：
    /// 累计应纳税所得额 = 累计收入 − 累计减除费用 − 累计社保公积金 − 累计专项附加 − 累计其他税前扣除
    /// 本月应预扣 = 累计应纳税额 − 截至上月已预缴税额
    static func compute(_ state: SalaryState) -> SalaryResult {
        let incomes = state.incomes
        let grossIncome = sumIncomes(incomes) { _ in true }
        let taxableIncome = sumIncomes(incomes) { $0.taxable }

        let socialConfig = resolvedSocial(state)
        let socialResult = social(socialConfig)
        let specialTotal = Money.round2(state.special.total)

        let preTax = Money.round2(
            state.deductions
                .filter { $0.preTax && $0.amount > 0 }
                .reduce(0) { $0 + Money.nonNegative($1.amount) }
        )
        let afterTax = Money.round2(
            state.deductions
                .filter { !$0.preTax && $0.amount > 0 }
                .reduce(0) { $0 + Money.nonNegative($1.amount) }
        )

        let ytd = resolveYtd(state)
        let monthIndex = min(12, max(1, Int(ytd.monthIndex.rounded())))

        let cumulativeIncome = Money.round2(Money.nonNegative(ytd.taxableIncome) + taxableIncome)
        let deductionMonths = ytd.deductionMonths
        let cumulativeBasicDeduction =
            Money.round2(TaxTable.basicDeductionPerMonth * Double(deductionMonths))
        let cumulativeSocial =
            Money.round2(Money.nonNegative(ytd.socialDeduction) + socialResult.total + preTax)

        // 累计专项附加：记录模式下是精确值，手填模式在没填时按「每月 × 月数」推算
        let priorSpecial: Double =
            (ytd.specialDeductionExact == true || ytd.specialDeduction > 0)
                ? Money.nonNegative(ytd.specialDeduction)
                : Money.round2(specialTotal * Double(monthIndex - 1))
        let cumulativeSpecial = Money.round2(priorSpecial + specialTotal)

        var cumulativeTaxable = Money.round2(
            cumulativeIncome - cumulativeBasicDeduction - cumulativeSocial - cumulativeSpecial
        )
        if cumulativeTaxable < 0 { cumulativeTaxable = 0 }

        var cumulativeTax = TaxTable.tax(cumulativeTaxable, in: TaxTable.annual)

        // 年终奖
        let bonusGross = Money.round2(Money.nonNegative(state.annualBonus))
        var bonusTax = 0.0
        var bonusCombinedTaxable = 0.0
        if bonusGross > 0 {
            if state.bonusTaxMode == "separate" {
                bonusTax = bonusTaxSeparate(bonusGross)
            } else {
                bonusCombinedTaxable = bonusGross
                cumulativeTaxable = Money.round2(cumulativeTaxable + bonusGross)
                cumulativeTax = TaxTable.tax(cumulativeTaxable, in: TaxTable.annual)
            }
        }

        let taxPaid = Money.nonNegative(ytd.taxPaid)
        let taxThisMonth = max(0, Money.round2(cumulativeTax - taxPaid)) + bonusTax

        let netPay = Money.round2(
            grossIncome + bonusGross - socialResult.total - preTax - afterTax - taxThisMonth
        )

        let base = taxableIncome + bonusCombinedTaxable
        let effectiveTaxRate = base > 0 ? taxThisMonth / base : 0

        return SalaryResult(
            grossIncome: grossIncome,
            taxableIncome: taxableIncome,
            socialBaseUsed: socialConfig.socialBase,
            housingFundBaseUsed: socialConfig.housingFundBase,
            social: socialResult,
            specialDeductionTotal: specialTotal,
            cumulativeTaxable: cumulativeTaxable,
            cumulativeTax: cumulativeTax,
            taxThisMonth: taxThisMonth,
            effectiveTaxRate: effectiveTaxRate,
            bonusGross: bonusGross,
            bonusTax: bonusTax,
            netPay: netPay
        )
    }
}
