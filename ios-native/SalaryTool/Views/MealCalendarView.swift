//
//  MealCalendarView.swift
//  误餐补贴日历。
//
//  和加班日历长得像，但每格填的不是小时数，而是「早 / 中 / 晚」三个开关；
//  另外多一个「出」标记：标了出差就整套换成出差单价，不再看当天是周几。
//

import SwiftUI

struct MealCalendarView: View {
    /// 直接绑定到 store，所有编辑立刻持久化
    @Binding var calendar: MealCalendar
    let rates: MealRates

    @State private var year: Int = 0
    @State private var month: Int = 0

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    private var current: MealCalendar { calendar }

    private var weeks: [[CalendarDay?]] {
        HolidayRules.buildMonth(
            year: year,
            month: month,
            hours: [:],
            overrides: current.overrides
        )
    }

    private var allDays: [CalendarDay] {
        weeks.flatMap { $0 }.compactMap { $0 }
    }

    private var monthTotal: Double {
        allDays.reduce(0) { sum, day in
            sum + dayAmount(key: day.key, type: day.type)
        }
    }

    private var summary: (workday: Double, weekend: Double, trip: Double, total: Double) {
        var workday = 0.0, weekend = 0.0, trip = 0.0
        for day in allDays {
            guard let counts = current.meals[day.key], counts.total > 0 else { continue }
            let scene = MealAllowanceMath.scene(
                dayType: day.type,
                isTrip: current.trips[day.key] == true
            )
            switch scene {
            case .trip: trip += counts.total
            case .weekend: weekend += counts.total
            case .workday: workday += counts.total
            }
        }
        return (workday, weekend, trip, workday + weekend + trip)
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            grid
            summaryRow
            hintText
        }
        .onAppear(perform: syncFromCalendar)
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
            .disabled(!canPrev)

            Text(verbatim: "\(year) 年 \(month) 月")
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
            .disabled(!canNext)
        }
    }

    private var canPrev: Bool {
        !(year == 2025 && month == 1)
    }

    private var canNext: Bool {
        !(year == 2045 && month == 12)
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

            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, maybeDay in
                        if let day = maybeDay {
                            dayCell(day)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 78)
                        }
                    }
                }
                if weekIndex != weeks.count - 1 {
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
        let isTrip = current.trips[day.key] == true
        let counts = current.meals[day.key] ?? .zero
        let amount = dayAmount(key: day.key, type: day.type)

        return VStack(spacing: 2) {
            // 日期 + 档位标签 + 出差标记
            HStack(spacing: 1) {
                Text("\(day.day)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.accentColor : Color.secondary)
                Spacer(minLength: 0)

                Button {
                    toggleTrip(day.key)
                } label: {
                    Text("出")
                        .font(.system(size: 9))
                        .foregroundStyle(isTrip ? Color.white : Color.secondary)
                        .frame(width: 15, height: 14)
                        .background {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isTrip ? Color.accentColor : Color.clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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

            // 早 / 中 / 晚 三个开关
            HStack(spacing: 2) {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    Button {
                        toggleMeal(day.key, slot)
                    } label: {
                        Text(slot.label)
                            .font(.system(size: 9))
                            .foregroundStyle(counts[slot] > 0 ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                            .background {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(counts[slot] > 0
                                          ? Color.accentColor.opacity(0.18)
                                          : Color.primary.opacity(0.04))
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if amount > 0 {
                Text(Money.format(amount))
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            if isTrip {
                Color.accentColor.opacity(0.09)
            } else if day.type == .rest {
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
            summaryCell("工作日", summary.workday)
            summaryCell("周末 / 节假日", summary.weekend)
            summaryCell("出差", summary.trip)
            summaryCell("合计 ¥", Money.round2(monthTotal) == 0 ? 0 : monthTotal, isMoney: true)
        }
    }

    private func summaryCell(_ label: String, _ value: Double, isMoney: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(isMoney ? Money.format(value) : "\(Money.format(value)) 餐")
                .font(.caption.weight(.medium))
                .foregroundStyle(isMoney ? .green : .primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.05))
        }
    }

    private var hintText: some View {
        Text("点格子里的「早 / 中 / 晚」勾选当天领到的餐次；点「出」标记出差，当天三餐按出差单价计算。工作日加班默认只有晚饭，周末和法定节假日默认午饭 + 晚饭。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 数据

    private func syncFromCalendar() {
        year = Int(calendar.year)
        month = Int(calendar.month)
    }

    private func typeColor(_ day: CalendarDay) -> Color {
        switch day.type {
        case .workday: .secondary
        case .rest: .orange
        case .holiday: .red
        }
    }

    private func dayAmount(key: String, type: DayType) -> Double {
        guard let counts = current.meals[key] else { return 0 }
        let scene = MealAllowanceMath.scene(
            dayType: type,
            isTrip: current.trips[key] == true
        )
        return counts.amount(with: rates[scene])
    }

    private func toggleMeal(_ key: String, _ slot: MealSlot) {
        var next = calendar
        var counts = next.meals[key] ?? .zero
        counts[slot] = counts[slot] > 0 ? 0 : 1
        if counts.total <= 0 {
            next.meals.removeValue(forKey: key)
        } else {
            next.meals[key] = counts
        }
        calendar = next
    }

    private func toggleTrip(_ key: String) {
        var next = calendar
        if next.trips[key] == true {
            next.trips.removeValue(forKey: key)
        } else {
            next.trips[key] = true
        }
        calendar = next
    }

    private func cycleType(_ day: CalendarDay) {
        var next = calendar
        let order: [DayType] = [.workday, .rest, .holiday]
        let index = order.firstIndex(of: day.type) ?? 0
        let candidate = order[(index + 1) % order.count]
        let defaultType = HolidayRules.defaultDayType(
            year: day.year, month: day.month, day: day.day
        )
        if candidate == defaultType {
            next.overrides.removeValue(forKey: day.key)
        } else {
            next.overrides[day.key] = candidate
        }
        calendar = next
    }

    private func shiftMonth(_ delta: Int) {
        var newMonth = month + delta
        var newYear = year
        if newMonth < 1 { newMonth = 12; newYear -= 1 }
        if newMonth > 12 { newMonth = 1; newYear += 1 }
        guard (2025...2045).contains(newYear) else { return }
        year = newYear
        month = newMonth
        var next = calendar
        next.year = Double(newYear)
        next.month = Double(newMonth)
        calendar = next
    }
}
