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

// MARK: - 误餐补贴

/// 一顿饭。早 / 中 / 晚。
enum MealSlot: String, Codable, CaseIterable {
    case breakfast, lunch, dinner

    var label: String {
        switch self {
        case .breakfast: "早"
        case .lunch: "中"
        case .dinner: "晚"
        }
    }
}

/// 发生误餐的场景，决定用哪套单价。
///
/// 出差独立于日期类型：标了出差就整套换成出差单价，不再看当天是周几。
enum MealScene: String, Codable, CaseIterable {
    case workday, weekend, trip

    var label: String {
        switch self {
        case .workday: "工作日加班"
        case .weekend: "周末 / 节假日"
        case .trip: "出差"
        }
    }
}

/// 一天能领几餐。用 Double 与输入框的绑定类型保持一致。
struct MealCounts: Codable, Hashable {
    var breakfast: Double
    var lunch: Double
    var dinner: Double

    static let zero = MealCounts(breakfast: 0, lunch: 0, dinner: 0)

    var total: Double { breakfast + lunch + dinner }

    subscript(slot: MealSlot) -> Double {
        get {
            switch slot {
            case .breakfast: breakfast
            case .lunch: lunch
            case .dinner: dinner
            }
        }
        set {
            switch slot {
            case .breakfast: breakfast = newValue
            case .lunch: lunch = newValue
            case .dinner: dinner = newValue
            }
        }
    }

    /// 餐次乘以单价。
    func amount(with rates: MealCounts) -> Double {
        Money.round2(
            Money.nonNegative(breakfast) * Money.nonNegative(rates.breakfast)
                + Money.nonNegative(lunch) * Money.nonNegative(rates.lunch)
                + Money.nonNegative(dinner) * Money.nonNegative(rates.dinner)
        )
    }

    init(breakfast: Double, lunch: Double, dinner: Double) {
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        breakfast = Money.round2(Money.nonNegative((try? c.decode(Double.self, forKey: .breakfast)) ?? 0))
        lunch = Money.round2(Money.nonNegative((try? c.decode(Double.self, forKey: .lunch)) ?? 0))
        dinner = Money.round2(Money.nonNegative((try? c.decode(Double.self, forKey: .dinner)) ?? 0))
    }
}

/// 三档的单价。
struct MealRates: Codable, Hashable {
    var workday: MealCounts
    var weekend: MealCounts
    var trip: MealCounts

    /// 默认单价：工作日只有晚饭 20；周末午饭 40 晚饭 20；出差 20 / 40 / 40。
    static let initial = MealRates(
        workday: MealCounts(breakfast: 0, lunch: 0, dinner: 20),
        weekend: MealCounts(breakfast: 0, lunch: 40, dinner: 20),
        trip: MealCounts(breakfast: 20, lunch: 40, dinner: 40)
    )

    subscript(scene: MealScene) -> MealCounts {
        get {
            switch scene {
            case .workday: workday
            case .weekend: weekend
            case .trip: trip
            }
        }
        set {
            switch scene {
            case .workday: workday = newValue
            case .weekend: weekend = newValue
            case .trip: trip = newValue
            }
        }
    }
}

/// 日历模式的数据，按自然月保存。
struct MealCalendar: Codable, Hashable {
    var year: Double
    var month: Double
    /// 日期键 -> 当天领的餐次
    var meals: [String: MealCounts]
    /// 日期键 -> 是否出差
    var trips: [String: Bool]
    /// 日期键 -> 手动改的日期类型
    var overrides: [String: DayType]

    static func empty() -> MealCalendar {
        let now = Date()
        let cal = Foundation.Calendar.current
        return MealCalendar(
            year: Double(cal.component(.year, from: now)),
            month: Double(cal.component(.month, from: now)),
            meals: [:], trips: [:], overrides: [:]
        )
    }

    init(year: Double, month: Double, meals: [String: MealCounts],
         trips: [String: Bool], overrides: [String: DayType]) {
        self.year = year
        self.month = month
        self.meals = meals
        self.trips = trips
        self.overrides = overrides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = (try? c.decode(Double.self, forKey: .year)) ?? MealCalendar.empty().year
        month = (try? c.decode(Double.self, forKey: .month)) ?? MealCalendar.empty().month
        meals = (try? c.decode([String: MealCounts].self, forKey: .meals)) ?? [:]
        trips = (try? c.decode([String: Bool].self, forKey: .trips)) ?? [:]
        overrides = (try? c.decode([String: DayType].self, forKey: .overrides)) ?? [:]
    }
}

struct MealAllowanceInput: Codable, Hashable {
    /// 直接填餐次 / 按日历填写
    var entryMode: String
    var rates: MealRates
    /// 手填模式下三档各自的餐次
    var manual: [String: MealCounts]
    var calendar: MealCalendar

    static let initial = MealAllowanceInput(
        entryMode: "manual",
        rates: .initial,
        manual: [
            MealScene.workday.rawValue: .zero,
            MealScene.weekend.rawValue: .zero,
            MealScene.trip.rawValue: .zero,
        ],
        calendar: .empty()
    )

    func manualCounts(_ scene: MealScene) -> MealCounts {
        manual[scene.rawValue] ?? .zero
    }

    mutating func setManualCounts(_ scene: MealScene, _ counts: MealCounts) {
        manual[scene.rawValue] = counts
    }

    init(entryMode: String, rates: MealRates,
         manual: [String: MealCounts], calendar: MealCalendar) {
        self.entryMode = entryMode
        self.rates = rates
        self.manual = manual
        self.calendar = calendar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryMode = (try? c.decode(String.self, forKey: .entryMode)) ?? "manual"
        rates = (try? c.decode(MealRates.self, forKey: .rates)) ?? .initial
        manual = (try? c.decode([String: MealCounts].self, forKey: .manual)) ?? [:]
        calendar = (try? c.decode(MealCalendar.self, forKey: .calendar)) ?? .empty()
    }
}

struct MealSyncSettings: Codable, Hashable {
    var enabled: Bool
    var incomeId: String?

    static let initial = MealSyncSettings(enabled: false, incomeId: nil)
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
    /// 加班误餐补贴
    var mealAllowance: MealAllowanceInput
    var mealSync: MealSyncSettings

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
        mealAllowance = (try? c.decode(MealAllowanceInput.self, forKey: .mealAllowance)) ?? .initial
        mealSync = (try? c.decode(MealSyncSettings.self, forKey: .mealSync)) ?? .initial

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
        overtimeSync: OvertimeSyncSettings = .initial,
        mealAllowance: MealAllowanceInput = .initial,
        mealSync: MealSyncSettings = .initial
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
        self.mealAllowance = mealAllowance
        self.mealSync = mealSync
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
