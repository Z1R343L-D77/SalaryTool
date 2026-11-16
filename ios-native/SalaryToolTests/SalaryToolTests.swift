//
//  SalaryToolTests.swift
//  计算逻辑的单元测试。用例与 shared/*.test.ts 对应，
//  保证原生版和 Windows 版算出来的数字完全一致。
//

import Testing
@testable import SalaryTool

@Suite("金额与取整")
struct MoneyTests {
    @Test("保留两位小数")
    func roundTwo() {
        #expect(Money.round2(1.005) == 1.01)
        #expect(Money.round2(1.004) == 1.0)
        #expect(Money.round2(1234.5678) == 1234.57)
    }

    @Test("保留四位：小时工资用")
    func roundFour() {
        // 6700 ÷ 174 = 38.5057...
        #expect(Money.round4(6700.0 / 174) == 38.5057)
    }

    @Test("非法值归零")
    func nonFinite() {
        #expect(Money.round2(.nan) == 0)
        #expect(Money.round2(.infinity) == 0)
    }

    @Test("格式化带千分位")
    func formatMoney() {
        #expect(Money.format(12345.6) == "12,345.60")
        #expect(Money.format(0) == "0.00")
    }

    @Test("百分比格式化")
    func formatRate() {
        #expect(Money.formatRate(0.0325) == "3.25%")
        #expect(Money.formatRate(0.1) == "10%")
        #expect(Money.formatRate(0) == "0%")
    }
}

@Suite("社保计算")
struct SocialTests {
    private let config = SocialConfig(
        socialBase: 15000, socialBaseMin: 6821, socialBaseMax: 35811,
        housingFundBase: 15000, housingFundBaseMin: 2420, housingFundBaseMax: 35811,
        pensionRate: 0.08, medicalRate: 0.02, unemploymentRate: 0.005,
        housingFundRate: 0.12, medicalExtra: 3
    )

    @Test("按比例计算个人部分")
    func proportional() {
        let r = Calculator.social(config)
        #expect(r.pension == 1200)
        #expect(r.medical == 300)
        #expect(r.unemployment == 75)
        #expect(r.housingFund == 1800)
        #expect(r.medicalExtra == 3)
        #expect(r.total == 3378)
    }

    @Test("低于下限按下限缴纳")
    func clampLower() {
        var c = config
        c.socialBase = 1000
        c.housingFundBase = 1000
        #expect(Calculator.social(c).pension == 545.68)
    }

    @Test("高于上限按上限缴纳")
    func clampUpper() {
        var c = config
        c.socialBase = 100000
        c.housingFundBase = 100000
        #expect(abs(Calculator.social(c).pension - 2864.88) < 0.01)
    }
}

@Suite("个税计算")
struct TaxTests {
    @Test("首月 15000、无专项附加")
    func firstMonth() {
        var state = SalaryState.sample
        state.incomes = [IncomeItem(label: "基本工资", amount: 15000)]
        state.social = SocialConfig(
            socialBase: 15000, socialBaseMin: 6821, socialBaseMax: 35811,
            housingFundBase: 15000, housingFundBaseMin: 2420, housingFundBaseMax: 35811,
            pensionRate: 0.08, medicalRate: 0.02, unemploymentRate: 0.005,
            housingFundRate: 0.12, medicalExtra: 3
        )
        state.special = .zero
        state.ytd = .initial

        let r = Calculator.compute(state)
        #expect(r.grossIncome == 15000)
        // 15000 − 5000 − 3378 = 6622
        #expect(r.cumulativeTaxable == 6622)
        // 3% → 198.66
        #expect(abs(r.taxThisMonth - 198.66) < 0.01)
    }

    @Test("收入不足以覆盖扣除时个税为 0")
    func belowThreshold() {
        var state = SalaryState.sample
        state.incomes = [IncomeItem(label: "基本工资", amount: 7000)]
        state.ytd = .initial
        let r = Calculator.compute(state)
        #expect(r.cumulativeTaxable == 0)
        #expect(r.taxThisMonth == 0)
    }

    @Test("专项附加扣除减少应纳税所得额")
    func withSpecial() {
        var state = SalaryState.sample
        state.incomes = [IncomeItem(label: "基本工资", amount: 15000)]
        state.social = SocialConfig(
            socialBase: 15000, socialBaseMin: 6821, socialBaseMax: 35811,
            housingFundBase: 15000, housingFundBaseMin: 2420, housingFundBaseMax: 35811,
            pensionRate: 0.08, medicalRate: 0.02, unemploymentRate: 0.005,
            housingFundRate: 0.12, medicalExtra: 3
        )
        state.special = SpecialDeductions(
            childrenEducation: 2000, continuingEducation: 0, seriousIllness: 0,
            housingLoanInterest: 0, housingRent: 1500, elderlyCare: 0, infantCare: 0
        )
        state.ytd = .initial

        let r = Calculator.compute(state)
        #expect(r.specialDeductionTotal == 3500)
        #expect(r.cumulativeTaxable == 3122)
        #expect(abs(r.taxThisMonth - 93.66) < 0.01)
    }

    @Test("减除费用口径：当年月份数 vs 本单位月数")
    func deductionModes() {
        var calendar: YtdTotals = .initial
        calendar.monthIndex = 10
        calendar.basicDeductionMode = .calendarMonth
        #expect(calendar.deductionMonths == 10)

        var employed: YtdTotals = .initial
        employed.monthIndex = 10
        employed.basicDeductionMode = .employedMonth
        employed.employedMonthIndex = 4
        #expect(employed.deductionMonths == 4)

        // 本单位月数不能超过当年月份数
        var over: YtdTotals = .initial
        over.monthIndex = 4
        over.basicDeductionMode = .employedMonth
        over.employedMonthIndex = 10
        #expect(over.deductionMonths == 4)
    }
}

@Suite("年终奖")
struct BonusTests {
    @Test("36000 元奖金按 3% 税率")
    func separateFirstBracket() {
        #expect(Calculator.bonusTaxSeparate(36000) == 1080)
    }

    @Test("税率跳档：36001 元进入 10% 档")
    func bracketJump() {
        let tax = Calculator.bonusTaxSeparate(36001)
        #expect(abs(tax - 3390.1) < 0.01)
    }

    @Test("并入综合所得时计入累计应纳税所得额")
    func combined() {
        var state = SalaryState.sample
        state.incomes = [IncomeItem(label: "基本工资", amount: 15000)]
        state.special = .zero
        state.ytd = .initial
        state.annualBonus = 36000
        state.bonusTaxMode = "separate"
        let separate = Calculator.compute(state)

        state.bonusTaxMode = "combined"
        let combined = Calculator.compute(state)

        #expect(separate.bonusTax == 1080)
        #expect(combined.bonusTax == 0)
        #expect(combined.taxThisMonth > separate.taxThisMonth)
    }
}

@Suite("按月记录累加")
struct RecordsTests {
    private func makeState(months: [MonthRecord], monthIndex: Double = 4) -> SalaryState {
        var state = SalaryState.sample
        state.ytdMode = "records"
        state.months = months
        state.ytd.monthIndex = monthIndex
        return state
    }

    @Test("只累加本月之前的记录")
    func onlyPriorMonths() {
        let state = makeState(months: [
            MonthRecord(month: 1, taxableIncome: 8700, socialDeduction: 1261.33, specialDeduction: 1500),
            MonthRecord(month: 2, taxableIncome: 8700, socialDeduction: 1261.33, specialDeduction: 1500),
            MonthRecord(month: 3, taxableIncome: 8700, socialDeduction: 1261.33, specialDeduction: 1500),
            MonthRecord(month: 4, taxableIncome: 11539.76),
        ])
        let ytd = Calculator.resolveYtd(state)
        #expect(ytd.taxableIncome == 26100)
        #expect(abs(ytd.socialDeduction - 3783.99) < 0.01)
        #expect(ytd.specialDeduction == 4500)
    }

    @Test("同一个月有多条时取最后一条")
    func lastRecordWins() {
        let state = makeState(months: [
            MonthRecord(month: 1, taxableIncome: 8000),
            MonthRecord(month: 1, taxableIncome: 8700),
        ], monthIndex: 2)
        #expect(Calculator.resolveYtd(state).taxableIncome == 8700)
    }

    @Test("缺失月份能被找出来")
    func missingMonths() {
        let state = makeState(months: [
            MonthRecord(month: 1, taxableIncome: 8700),
            MonthRecord(month: 3, taxableIncome: 8700),
        ])
        #expect(Calculator.missingMonths(state) == [2])
    }
}

@Suite("双基数模式")
struct DualBaseTests {
    @Test("社保和公积金各自独立推算")
    func independentBases() {
        var state = SalaryState.sample
        state.socialBaseMode = "auto"
        state.housingFundBaseMode = "auto"
        state.incomes = [
            IncomeItem(label: "基本工资", amount: 8000),
            IncomeItem(label: "绩效", amount: 1500, includeInHousingFundBase: false),
        ]
        // 社保 = 8000 + 1500，公积金 = 只有 8000
        #expect(Calculator.suggestSocialBase(state.incomes) == 9500)
        #expect(Calculator.suggestHousingFundBase(state.incomes) == 8000)
    }

    @Test("自动基数受上下限约束")
    func clampedSuggestion() {
        var state = SalaryState.sample
        state.socialBaseMode = "auto"
        state.incomes = [IncomeItem(label: "基本工资", amount: 100000)]
        #expect(Calculator.resolvedSocial(state).socialBase == 35811)
    }
}
