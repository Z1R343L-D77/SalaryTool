//
//  OvertimeCalendarView.swift
//  加班日历：按天填工时，自动按日期判断档位。
//
//  桌面版用 HTML 表格，这里用 SwiftUI 的网格。每格：
//  日期 + 档位标签（可点循环）+ 工时输入 + 当日折算金额。
//

import SwiftUI

struct OvertimeCalendarView: View {
    @Environment(SalaryStore.self) private var store

    @State private var year = 0
    @State private var month = 0
    @State private var quickHours: Double = 8

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    private var calendar: OvertimeCalendar {
        store.state.overtime.calendar ?? .empty()
    }

    private var weeks: [[CalendarDay?]] {
        HolidayRules.buildMonth(
            year: year,
            month: month,
            hours: calendar.hours,
            overrides: calendar.overrides
        )
    }

    private var summary: CalendarSummary {
        var result = CalendarSummary()
        let flat: [CalendarDay] = weeks.flatMap { $0 }.compactMap { $0 }
        for day in flat where day.hours > 0 {
            result.workedDays += 1
            switch day.type {
            case .holiday: result.holidayHours += day.hours
            case .rest: result.restHours += day.hours
            case .workday: result.workdayHours += day.hours
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            quickFillRow
            grid
            summaryRow
            hintText
        }
        .onAppear(perform: syncFromState)
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(year) 年 \(month) 月")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 批量填写

    private var quickFillRow: some View {
        HStack(spacing: 8) {
            Text("每天")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("8", value: $quickHours, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.caption)
                .frame(width: 52, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.primary.opacity(0.06))
                }

            Text("小时")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Button("填工作日") { fill(.workday) }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("填休息日") { fill(.rest) }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("清空") { clearMonth() }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
        }
    }

    // MARK: 网格

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Self.weekdayLabels, id: \.self) { label in
                    Text("周\(label)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            Divider().opacity(0.35)

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                        }
                    }
                }
                if week != weeks.last {
                    Divider().opacity(0.18)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                Text("\(day.day)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.accentColor : Color.secondary)
                Spacer(minLength: 0)
                Button {
                    cycleType(day)
                } label: {
                    Text(day.type.short)
                        .font(.system(size: 9))
                        .foregroundStyle(typeColor(day))
                        .frame(width: 15, height: 14)
                        .background {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.overridden ? Color.accentColor.opacity(0.18) : Color.clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            TextField("", value: hoursBinding(day), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 2)
                .frame(height: 20)

            if day.hours > 0 {
                Text(Money.format(dayPay(day)))
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background {
            if day.type == .rest {
                Color.primary.opacity(0.02)
            } else if day.type == .holiday {
                Color.red.opacity(0.06)
            }
        }
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
    }

    // MARK: 汇总

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryCell("工作日", summary.workdayHours, .primary)
            summaryCell("休息日", summary.restHours, .orange)
            summaryCell("节假日", summary.holidayHours, .red)
            summaryCell("合计", summary.totalHours, .green)
        }
    }

    private func summaryCell(_ label: String, _ hours: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(Money.format(hours))")
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text("小时")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }

    private var hintText: some View {
        Text("工作日 1.5 倍、周末 2 倍、法定节假日 3 倍。元旦、劳动节、国庆自动识别；春节 / 清明 / 端午 / 中秋按农历、每年不同，点日期右上角的标签手动设为「假」。调休上班也点标签改成「班」。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 数据操作

    private func syncFromState() {
        let cal = calendar
        year = Int(cal.year)
        month = Int(cal.month)
    }

    private func dayPay(_ day: CalendarDay) -> Double {
        let base = OvertimeMath.hourlyBase(store.state.overtime)
        return Money.round2(day.hours * Money.round4(base * day.type.multiplier))
    }

    private func typeColor(_ day: CalendarDay) -> Color {
        switch day.type {
        case .workday: .secondary
        case .rest: .orange
        case .holiday: .red
        }
    }

    private func hoursBinding(_ day: CalendarDay) -> Binding<Double> {
        Binding(
            get: { calendar.hours[day.key] ?? 0 },
            set: { newValue in
                var cal = calendar
                if newValue <= 0 {
                    cal.hours.removeValue(forKey: day.key)
                } else {
                    cal.hours[day.key] = Money.round2(min(24, newValue))
                }
                store.state.overtime.calendar = cal
                store.syncHoursFromCalendar(entryModeCalendar: true)
            }
        )
    }

    private func shiftMonth(_ delta: Int) {
        var newMonth = month + delta
        var newYear = year
        if newMonth < 1 { newMonth = 12; newYear -= 1 }
        if newMonth > 12 { newMonth = 1; newYear += 1 }
        guard (2025...2045).contains(newYear) else { return }
        year = newYear
        month = newMonth

        var cal = calendar
        cal.year = Double(newYear)
        cal.month = Double(newMonth)
        store.state.overtime.calendar = cal
        // 切月份后，合计立刻按新月份的记录重算
        store.syncHoursFromCalendar(entryModeCalendar: true)
    }

    /// 点档位标签：工作日 → 休息日 → 节假日 → 回到默认判断
    private func cycleType(_ day: CalendarDay) {
        var cal = calendar
        let order = DayType.allCases
        let index = order.firstIndex(of: day.type) ?? 0
        let next = order[(index + 1) % order.count]
        let defaultType = HolidayRules.defaultDayType(
            year: day.year, month: day.month, day: day.day
        )
        if next == defaultType {
            cal.overrides.removeValue(forKey: day.key)
        } else {
            cal.overrides[day.key] = next
        }
        store.state.overtime.calendar = cal
        store.syncHoursFromCalendar(entryModeCalendar: true)
    }

    private func fill(_ type: DayType) {
        var cal = calendar
        let flat: [CalendarDay] = weeks.flatMap { $0 }.compactMap { $0 }
        for day in flat where day.type == type {
            cal.hours[day.key] = Money.round2(min(24, max(0, quickHours)))
        }
        store.state.overtime.calendar = cal
        store.syncHoursFromCalendar(entryModeCalendar: true)
    }

    private func clearMonth() {
        var cal = calendar
        cal.hours = [:]
        cal.overrides = [:]
        store.state.overtime.calendar = cal
        store.syncHoursFromCalendar(entryModeCalendar: true)
    }
}
