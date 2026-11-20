//
//  MealAllowance.swift
//  误餐补贴的汇总计算。
//
//  和加班费是两条独立的线：
//  - 加班费 = 工时 × 倍率
//  - 误餐补贴 = 天数 × 餐次 × 单价
//  逻辑与 shared/mealAllowance.ts 一一对应。
//

import Foundation

enum MealAllowanceMath {
    /// 某天属于哪一档。
    ///
    /// 出差优先：标了出差就整套换成出差单价，不再看当天是周几。
    /// 否则按日期类型：工作日归 workday，休息日和法定节假日都归 weekend。
    static func scene(dayType: DayType, isTrip: Bool) -> MealScene {
        if isTrip { return .trip }
        return dayType == .workday ? .workday : .weekend
    }

    /// 手填模式的三档金额。
    static func computeManual(_ input: MealAllowanceInput) -> MealAllowanceResult {
        var result = MealAllowanceResult()
        for scene in MealScene.allCases {
            let counts = input.manualCounts(scene)
            let amount = counts.amount(with: input.rates[scene])
            result.setAmount(amount, meals: counts.total, for: scene)
        }
        return result.finalized()
    }

    /// 日历模式的三档金额：逐天判断档位后累加。
    static func computeCalendar(_ calendar: MealCalendar, rates: MealRates) -> MealAllowanceResult {
        let weeks = HolidayRules.buildMonth(
            year: Int(calendar.year),
            month: Int(calendar.month),
            hours: [:],
            overrides: calendar.overrides
        )

        var result = MealAllowanceResult()
        let days: [CalendarDay] = weeks.flatMap { $0 }.compactMap { $0 }
        for day in days {
            guard let counts = calendar.meals[day.key], counts.total > 0 else { continue }
            let scene = scene(dayType: day.type, isTrip: calendar.trips[day.key] == true)
            result.add(amount: counts.amount(with: rates[scene]), meals: counts.total, to: scene)
        }
        return result.finalized()
    }

    /// 按录入方式取结果。
    static func compute(_ input: MealAllowanceInput) -> MealAllowanceResult {
        input.entryMode == "calendar"
            ? computeCalendar(input.calendar, rates: input.rates)
            : computeManual(input)
    }

    /// 从加班日历补餐次。
    ///
    /// 工作日有加班 -> 勾晚饭；周末 / 节假日有加班 -> 勾午饭和晚饭。
    /// 已经填过的日子跳过，不覆盖手工调整。
    static func suggestFromOvertime(
        overtime: OvertimeCalendar,
        target: MealCalendar
    ) -> [String: MealCounts] {
        let weeks = HolidayRules.buildMonth(
            year: Int(overtime.year),
            month: Int(overtime.month),
            hours: overtime.hours,
            overrides: overtime.overrides
        )

        var meals = target.meals
        let days: [CalendarDay] = weeks.flatMap { $0 }.compactMap { $0 }
        for day in days {
            guard (overtime.hours[day.key] ?? 0) > 0 else { continue }
            if let existing = meals[day.key], existing.total > 0 { continue }
            meals[day.key] = day.type == .workday
                ? MealCounts(breakfast: 0, lunch: 0, dinner: 1)
                : MealCounts(breakfast: 0, lunch: 1, dinner: 1)
        }
        return meals
    }
}

/// 三档的汇总结果。
struct MealAllowanceResult {
    var workday = 0.0
    var weekend = 0.0
    var trip = 0.0
    var workdayMeals = 0.0
    var weekendMeals = 0.0
    var tripMeals = 0.0

    var total: Double { Money.round2(workday + weekend + trip) }
    var totalMeals: Double { workdayMeals + weekendMeals + tripMeals }

    mutating func setAmount(_ amount: Double, meals: Double, for scene: MealScene) {
        switch scene {
        case .workday:
            workday = amount
            workdayMeals = meals
        case .weekend:
            weekend = amount
            weekendMeals = meals
        case .trip:
            trip = amount
            tripMeals = meals
        }
    }

    mutating func add(amount: Double, meals: Double, to scene: MealScene) {
        switch scene {
        case .workday:
            workday += amount
            workdayMeals += meals
        case .weekend:
            weekend += amount
            weekendMeals += meals
        case .trip:
            trip += amount
            tripMeals += meals
        }
    }

    func amount(for scene: MealScene) -> Double {
        switch scene {
        case .workday: workday
        case .weekend: weekend
        case .trip: trip
        }
    }

    func meals(for scene: MealScene) -> Double {
        switch scene {
        case .workday: workdayMeals
        case .weekend: weekendMeals
        case .trip: tripMeals
        }
    }

    /// 把累加值收尾：金额统一保留两位。
    func finalized() -> MealAllowanceResult {
        var copy = self
        copy.workday = Money.round2(workday)
        copy.weekend = Money.round2(weekend)
        copy.trip = Money.round2(trip)
        return copy
    }
}
