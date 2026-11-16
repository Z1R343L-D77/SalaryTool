//
//  Models.swift
//  与 shared/*.ts 的数据结构一一对应。
//
//  为什么要求严格对应：Windows 版导出的 JSON 要能直接导进 iOS 版，
//  字段名、类型、默认值都必须一致。这里用 CodingKeys 显式写出字段名，
//  不依赖 Swift 的自动转换（它会 camelCase 化，正好和 TS 撞上，
//  但显式写更保险，也能带默认值容错）。
//

import Foundation

// MARK: - 收入项

struct IncomeItem: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var amount: Double
    /// 是否计入社保缴费基数
    var includeInSocialBase: Bool
    /// 是否计入公积金缴费基数
    var includeInHousingFundBase: Bool
    /// 是否计入个税应纳税所得额
    var taxable: Bool

    /// 缺字段时的默认值：计入社保、计入公积金、计税
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? "收入"
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        let social = (try? c.decode(Bool.self, forKey: .includeInSocialBase)) ?? true
        includeInSocialBase = social
        includeInHousingFundBase =
            (try? c.decode(Bool.self, forKey: .includeInHousingFundBase)) ?? social
        taxable = (try? c.decode(Bool.self, forKey: .taxable)) ?? true
    }

    init(
        id: String = UUID().uuidString,
        label: String,
        amount: Double,
        includeInSocialBase: Bool = true,
        includeInHousingFundBase: Bool = true,
        taxable: Bool = true
    ) {
        self.id = id
        self.label = label
        self.amount = amount
        self.includeInSocialBase = includeInSocialBase
        self.includeInHousingFundBase = includeInHousingFundBase
        self.taxable = taxable
    }
}

// MARK: - 其他扣除

struct DeductionItem: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var amount: Double
    /// 是否可税前扣除（企业年金、商业健康险等）
    var preTax: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? "扣除"
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        preTax = (try? c.decode(Bool.self, forKey: .preTax)) ?? false
    }

    init(
        id: String = UUID().uuidString,
        label: String,
        amount: Double,
        preTax: Bool = false
    ) {
        self.id = id
        self.label = label
        self.amount = amount
        self.preTax = preTax
    }
}

// MARK: - 社保公积金

struct SocialConfig: Codable, Hashable {
    var socialBase: Double
    var socialBaseMin: Double
    var socialBaseMax: Double
    var housingFundBase: Double
    var housingFundBaseMin: Double
    var housingFundBaseMax: Double
    var pensionRate: Double
    var medicalRate: Double
    var unemploymentRate: Double
    var housingFundRate: Double
    var medicalExtra: Double

    static let fallback = SocialConfig(
        socialBase: 0, socialBaseMin: 0, socialBaseMax: 0,
        housingFundBase: 0, housingFundBaseMin: 0, housingFundBaseMax: 0,
        pensionRate: 0.08, medicalRate: 0.02, unemploymentRate: 0.005,
        housingFundRate: 0.12, medicalExtra: 0
    )
}

// MARK: - 专项附加扣除

struct SpecialDeductions: Codable, Hashable {
    var childrenEducation: Double
    var continuingEducation: Double
    var seriousIllness: Double
    var housingLoanInterest: Double
    var housingRent: Double
    var elderlyCare: Double
    var infantCare: Double

    var total: Double {
        Money.round2(
            childrenEducation + continuingEducation + seriousIllness
                + housingLoanInterest + housingRent + elderlyCare + infantCare
        )
    }

    static let zero = SpecialDeductions(
        childrenEducation: 0, continuingEducation: 0, seriousIllness: 0,
        housingLoanInterest: 0, housingRent: 0, elderlyCare: 0, infantCare: 0
    )
}

// MARK: - 累计数据

/// 基本减除费用的累计口径（国家税务总局 2020 年第 13 号公告）
enum BasicDeductionMode: String, Codable {
    /// 当年第几个月：7 月首次取得工资薪金的人可追溯
    case calendarMonth
    /// 在本单位第几个月：年内换过工作时用
    case employedMonth
}

struct YtdTotals: Codable, Hashable {
    var monthIndex: Double
    var taxableIncome: Double
    var socialDeduction: Double
    var specialDeduction: Double
    var taxPaid: Double
    var basicDeductionMode: BasicDeductionMode?
    var employedMonthIndex: Double?
    /// 记录模式下累计值是精确的，即使是 0 也不该被「每月金额 × 月数」补上
    var specialDeductionExact: Bool?

    static let initial = YtdTotals(
        monthIndex: 1, taxableIncome: 0, socialDeduction: 0,
        specialDeduction: 0, taxPaid: 0
    )

    /// 减除费用要乘的月数
    var deductionMonths: Int {
        let calendar = min(12, max(1, Int(monthIndex.rounded())))
        guard basicDeductionMode == .employedMonth else { return calendar }
        let employed = Int((employedMonthIndex ?? 0).rounded())
        guard employed > 0 else { return calendar }
        return min(calendar, max(1, employed))
    }
}

// MARK: - 按月记录

struct MonthRecord: Codable, Identifiable, Hashable {
    var id: String
    var month: Double
    var taxableIncome: Double
    var socialDeduction: Double
    var specialDeduction: Double
    /// 该月实际被扣的个税（工资条上的数，不是算出来的）
    var taxPaid: Double
    var note: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        month = (try? c.decode(Double.self, forKey: .month)) ?? 1
        taxableIncome = (try? c.decode(Double.self, forKey: .taxableIncome)) ?? 0
        socialDeduction = (try? c.decode(Double.self, forKey: .socialDeduction)) ?? 0
        specialDeduction = (try? c.decode(Double.self, forKey: .specialDeduction)) ?? 0
        taxPaid = (try? c.decode(Double.self, forKey: .taxPaid)) ?? 0
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }

    init(
        id: String = UUID().uuidString,
        month: Double,
        taxableIncome: Double = 0,
        socialDeduction: Double = 0,
        specialDeduction: Double = 0,
        taxPaid: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.month = month
        self.taxableIncome = taxableIncome
        self.socialDeduction = socialDeduction
        self.specialDeduction = specialDeduction
        self.taxPaid = taxPaid
        self.note = note
    }
}

// MARK: - 加班费

enum OvertimeBaseMode: String, Codable {
    case monthly, hourly
}

struct OvertimeInput: Codable, Hashable {
    var mode: OvertimeBaseMode
    /// 工时录入方式：直接填三档合计 / 按日历逐天填
    var entryMode: String
    var base: Double
    var followBasicSalary: Bool
    var hourlyRate: Double
    var monthlyDays: Double
    var dailyHours: Double
    var weekdayHours: Double
    var weekendHours: Double
    var holidayHours: Double
    var calendar: OvertimeCalendar?

    static let initial = OvertimeInput(
        mode: .monthly, entryMode: "manual", base: 0, followBasicSalary: true,
        hourlyRate: 0, monthlyDays: 21.75, dailyHours: 8,
        weekdayHours: 0, weekendHours: 0, holidayHours: 0, calendar: nil
    )
}

struct OvertimeCalendar: Codable, Hashable {
    var year: Double
    var month: Double
    var hours: [String: Double]
    var overrides: [String: DayType]

    static func empty() -> OvertimeCalendar {
        let now = Date()
        let cal = Foundation.Calendar.current
        return OvertimeCalendar(
            year: Double(cal.component(.year, from: now)),
            month: Double(cal.component(.month, from: now)),
            hours: [:], overrides: [:]
        )
    }
}

struct OvertimeSyncSettings: Codable, Hashable {
    var enabled: Bool
    var incomeId: String?

    static let initial = OvertimeSyncSettings(enabled: false, incomeId: nil)
}

// MARK: - 整个 App 的状态

struct SalaryState: Codable {
    var cityId: String
    var socialBaseMode: String
    var housingFundBaseMode: String
    var incomes: [IncomeItem]
    var deductions: [DeductionItem]
    var social: SocialConfig
    var special: SpecialDeductions
    var ytdMode: String
    var ytd: YtdTotals
    var months: [MonthRecord]
    var annualBonus: Double
    var bonusTaxMode: String
    var overtime: OvertimeInput
    var overtimeSync: OvertimeSyncSettings

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cityId = (try? c.decode(String.self, forKey: .cityId)) ?? "beijing"
        socialBaseMode = (try? c.decode(String.self, forKey: .socialBaseMode)) ?? "auto"
        housingFundBaseMode =
            (try? c.decode(String.self, forKey: .housingFundBaseMode)) ?? socialBaseMode
        incomes = (try? c.decode([IncomeItem].self, forKey: .incomes)) ?? []
        deductions = (try? c.decode([DeductionItem].self, forKey: .deductions)) ?? []
        social = (try? c.decode(SocialConfig.self, forKey: .social)) ?? .fallback
        special = (try? c.decode(SpecialDeductions.self, forKey: .special)) ?? .zero
        ytdMode = (try? c.decode(String.self, forKey: .ytdMode)) ?? "manual"
        ytd = (try? c.decode(YtdTotals.self, forKey: .ytd)) ?? .initial
        months = (try? c.decode([MonthRecord].self, forKey: .months)) ?? []
        annualBonus = (try? c.decode(Double.self, forKey: .annualBonus)) ?? 0
        bonusTaxMode = (try? c.decode(String.self, forKey: .bonusTaxMode)) ?? "separate"
        overtime = (try? c.decode(OvertimeInput.self, forKey: .overtime)) ?? .initial
        overtimeSync = (try? c.decode(OvertimeSyncSettings.self, forKey: .overtimeSync)) ?? .initial

        if incomes.isEmpty { incomes = SalaryState.sample.incomes }
    }

    init(
        cityId: String, socialBaseMode: String, housingFundBaseMode: String,
        incomes: [IncomeItem], deductions: [DeductionItem] = [],
        social: SocialConfig, special: SpecialDeductions,
        ytdMode: String = "manual", ytd: YtdTotals = .initial,
        months: [MonthRecord] = [], annualBonus: Double = 0,
        bonusTaxMode: String = "separate",
        overtime: OvertimeInput = .initial,
        overtimeSync: OvertimeSyncSettings = .initial
    ) {
        self.cityId = cityId
        self.socialBaseMode = socialBaseMode
        self.housingFundBaseMode = housingFundBaseMode
        self.incomes = incomes
        self.deductions = deductions
        self.social = social
        self.special = special
        self.ytdMode = ytdMode
        self.ytd = ytd
        self.months = months
        self.annualBonus = annualBonus
        self.bonusTaxMode = bonusTaxMode
        self.overtime = overtime
        self.overtimeSync = overtimeSync
    }

    /// 首次启动 / 重置时的示例数据，与 TS 版的 createDefaultState 对齐
    static let sample = SalaryState(
        cityId: "beijing",
        socialBaseMode: "auto",
        housingFundBaseMode: "auto",
        incomes: [
            IncomeItem(label: "基本工资", amount: 15000),
            IncomeItem(
                label: "租房补贴", amount: 2000,
                includeInSocialBase: false, includeInHousingFundBase: false
            ),
            IncomeItem(
                label: "餐补", amount: 660,
                includeInSocialBase: false, includeInHousingFundBase: false
            ),
        ],
        social: CityRepository.policy(for: "beijing").socialConfig,
        special: SpecialDeductions(
            childrenEducation: 0, continuingEducation: 0, seriousIllness: 0,
            housingLoanInterest: 0, housingRent: 1500, elderlyCare: 0, infantCare: 0
        )
    )
}
