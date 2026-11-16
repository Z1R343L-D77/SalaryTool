//
//  Calendar.swift
//  加班日历：按天填工时，自动按日期判断工作日 / 休息日 / 法定节假日。
//
//  逻辑与 shared/calendar.ts + shared/overtime.ts 一致：
//  - 固定日期节假日（元旦 1/1、劳动节 5/1–5/2、国庆 10/1–10/3）自动识别
//  - 农历节日（春节、清明、端午、中秋）日期每年不同，需要手动点档位
//  - 点档位标签循环切换：工作日 → 休息日 → 节假日 → 回到默认
//

import Foundation

enum DayType: String, Codable, CaseIterable {
    case workday, rest, holiday

    var label: String {
        switch self {
        case .workday: "工作日"
        case .rest: "休息日"
        case .holiday: "法定节假日"
        }
    }

    /// 日历格子上显示的单个字
    var short: String {
        switch self {
        case .workday: "班"
        case .rest: "休"
        case .holiday: "假"
        }
    }

    var multiplier: Double {
        switch self {
        case .workday: 1.5
        case .rest: 2
        case .holiday: 3
        }
    }
}

struct CalendarDay: Identifiable, Hashable {
    var id: String { key }
    let key: String          // 2026-11-14
    let year: Int
    let month: Int
    let day: Int
    /// 周一为 0
    let weekday: Int
    let type: DayType
    /// 是否被用户手动改过档位
    let overridden: Bool
    let hours: Double
    let isToday: Bool
}

enum HolidayRules {
    /// 日期固定的法定节假日，所有年份通用
    static func isFixedStatutory(month: Int, day: Int) -> Bool {
        if month == 1, day == 1 { return true }
        if month == 5, day == 1 || day == 2 { return true }
        if month == 10, 1...3 ~= day { return true }
        return false
    }

    /// 农历节日的法定日期（只收录已正式公布的年份）。
    /// 未收录的年份不自动标记，需要在日历上手动设成「假」。
    private static let lunarStatutory: [Int: [String]] = [
        2025: ["01-28", "01-29", "01-30", "01-31", "04-04", "05-31", "10-06"],
    ]

    static func isLunarStatutory(year: Int, month: Int, day: Int) -> Bool {
        guard let list = lunarStatutory[year] else { return false }
        return list.contains(String(format: "%02d-%02d", month, day))
    }

    static func defaultDayType(year: Int, month: Int, day: Int) -> DayType {
        if isFixedStatutory(month: month, day: day) { return .holiday }
        if isLunarStatutory(year: year, month: month, day: day) { return .holiday }
        return weekdayOf(year: year, month: month, day: day) >= 5 ? .rest : .workday
    }

    static func weekdayOf(year: Int, month: Int, day: Int) -> Int {
        let calendar = Foundation.Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps) else { return 0 }
        // Sunday = 1 ... Saturday = 7，转成 Monday = 0 ... Sunday = 6
        return (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func dayKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 生成一个月的日历，首尾补空格对齐周一到周日
    static func buildMonth(
        year: Int,
        month: Int,
        hours: [String: Double],
        overrides: [String: DayType]
    ) -> [[CalendarDay?]] {
        let cal = Foundation.Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else {
            return []
        }

        let todayKey = {
            let now = Date()
            return dayKey(
                year: cal.component(.year, from: now),
                month: cal.component(.month, from: now),
                day: cal.component(.day, from: now)
            )
        }()

        let leading = weekdayOf(year: year, month: month, day: 1)
        var cells: [CalendarDay?] = Array(repeating: nil, count: leading)

        for day in range {
            let key = dayKey(year: year, month: month, day: day)
            cells.append(
                CalendarDay(
                    key: key,
                    year: year,
                    month: month,
                    day: day,
                    weekday: weekdayOf(year: year, month: month, day: day),
                    type: overrides[key] ?? defaultDayType(year: year, month: month, day: day),
                    overridden: overrides[key] != nil,
                    hours: Money.round2(hours[key] ?? 0),
                    isToday: key == todayKey
                )
            )
        }

        // 补到整周
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }
}

/// 一个月按档位汇总
struct CalendarSummary {
    var workdayHours: Double = 0
    var restHours: Double = 0
    var holidayHours: Double = 0
    var workedDays: Int = 0

    var totalHours: Double { Money.round2(workdayHours + restHours + holidayHours) }
}

enum OvertimeMath {
    /// 月薪模式：月薪 ÷ 月计薪天数 ÷ 日工时
    static func monthlyToHourly(base: Double, monthlyDays: Double, dailyHours: Double) -> Double {
        let days = Money.nonNegative(monthlyDays)
        let hours = Money.nonNegative(dailyHours)
        guard days > 0, hours > 0 else { return 0 }
        return Money.round4(Money.nonNegative(base) / days / hours)
    }

    /// 时薪 → 月薪
    static func hourlyToMonthly(
        hourlyRate: Double,
        monthlyDays: Double,
        dailyHours: Double,
        currentBase: Double?
    ) -> Double {
        let days = Money.nonNegative(monthlyDays)
        let hours = Money.nonNegative(dailyHours)
        guard days > 0, hours > 0 else { return 0 }
        let rate = Money.round4(Money.nonNegative(hourlyRate))
        // 已在同一个值上：保留原月薪，避免两位小数的误差累积
        if let currentBase, currentBase > 0,
           monthlyToHourly(base: currentBase, monthlyDays: days, dailyHours: hours) == rate {
            return Money.round2(currentBase)
        }
        return Money.round2(rate * days * hours)
    }

    /// 参与计算的小时工资（不含倍率）
    static func hourlyBase(_ input: OvertimeInput) -> Double {
        switch input.mode {
        case .hourly:
            return Money.round4(Money.nonNegative(input.hourlyRate))
        case .monthly:
            return monthlyToHourly(
                base: input.base,
                monthlyDays: input.monthlyDays,
                dailyHours: input.dailyHours
            )
        }
    }

    /// 取出参与计算的工时：日历模式按当月汇总，手工模式直接用三档合计
    static func resolveHours(_ input: OvertimeInput) -> (workday: Double, rest: Double, holiday: Double) {
        if input.entryMode == "calendar", let calendar = input.calendar {
            let weeks = HolidayRules.buildMonth(
                year: Int(calendar.year),
                month: Int(calendar.month),
                hours: calendar.hours,
                overrides: calendar.overrides
            )
            var summary = CalendarSummary()
            let flat: [CalendarDay] = weeks.flatMap { $0 }.compactMap { $0 }
            for day in flat where day.hours > 0 {
                summary.workedDays += 1
                switch day.type {
                case .holiday: summary.holidayHours += day.hours
                case .rest: summary.restHours += day.hours
                case .workday: summary.workdayHours += day.hours
                }
            }
            return (
                Money.round2(summary.workdayHours),
                Money.round2(summary.restHours),
                Money.round2(summary.holidayHours)
            )
        }
        return (
            Money.nonNegative(input.weekdayHours),
            Money.nonNegative(input.weekendHours),
            Money.nonNegative(input.holidayHours)
        )
    }

    static func totalPay(_ input: OvertimeInput) -> Double {
        let base = hourlyBase(input)
        let hours = resolveHours(input)
        return Money.round2(
            Money.round4(base * 1.5) * hours.workday
                + Money.round4(base * 2) * hours.rest
                + Money.round4(base * 3) * hours.holiday
        )
    }
}
