//
//  FullCalendarScreen.swift
//  全屏日历 + 每日编辑弹层 + 入口卡片。
//
//  为什么要有这一层：
//  主界面里一行要放 7 个格子，屏宽 402pt 时每格只有 55pt 宽，而格子里要塞
//  日期、档位、工时输入（或三餐按钮）、金额 —— 每个可点区域只有 16pt 左右，
//  远低于 iOS HIG 的 44pt 最小触摸目标。误触是必然的。
//
//  所以把日历做成一个入口：主界面只显示「月份 + 已填天数 + 本月金额」，
//  点进去是全屏日历（每格约 100pt 高），点某一天再弹半屏编辑层。
//  参考 iOS 自带「照片」App 的日历视图。
//

import SwiftUI

// MARK: - 通用外壳

/// 全屏日历的外壳：月份标题、星期表头、网格、底部「今天」。
///
/// 单元格内容由调用方提供（加班显示工时、误餐显示餐次），
/// 外壳只负责布局、月份切换和尺寸。
struct FullCalendarShell<Cell: View>: View {
    @Binding var year: Int
    @Binding var month: Int
    /// 本月所有格子；null 表示月初月末的占位
    let weeks: [[CalendarDay?]]
    /// 每格内容
    @ViewBuilder let cell: (CalendarDay) -> Cell

    @Environment(\.dismiss) private var dismiss

    private static var weekdayLabels: [String] { ["一", "二", "三", "四", "五", "六", "日"] }
    private static var monthNames: [String] {
        ["一月", "二月", "三月", "四月", "五月", "六月",
         "七月", "八月", "九月", "十月", "十一月", "十二月"]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            monthTitle
            weekdayHeader
            grid
            Spacer(minLength: 0)
        }
        .background(Color(.systemBackground))
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                shift(-1)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text(verbatim: "\(year)年")
                        .font(.system(size: 16, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(Color(.secondarySystemBackground))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canPrev)
            .opacity(canPrev ? 1 : 0.35)

            Spacer(minLength: 0)

            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(Color(.secondarySystemBackground))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canNext)
            .opacity(canNext ? 1 : 0.35)

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(Color(.secondarySystemBackground))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: 大标题

    private var monthTitle: some View {
        HStack {
            Text(Self.monthNames[max(0, min(11, month - 1))])
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: 星期表头

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.quaternary).frame(height: 0.5)
        }
    }

    // MARK: 网格

    /// 每格高度按可用空间均分：一周 7 列，最多 6 行。
    private var grid: some View {
        GeometryReader { geo in
            let rows = max(1, weeks.count)
            let cellHeight = geo.size.height / CGFloat(rows)

            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, maybeDay in
                            if let day = maybeDay {
                                cell(day)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellHeight)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellHeight)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: 月份切换

    private var canPrev: Bool { !(year == 2025 && month == 1) }
    private var canNext: Bool { !(year == 2045 && month == 12) }

    private func shift(_ delta: Int) {
        var newMonth = month + delta
        var newYear = year
        if newMonth < 1 { newMonth = 12; newYear -= 1 }
        if newMonth > 12 { newMonth = 1; newYear += 1 }
        guard (2025...2045).contains(newYear) else { return }
        year = newYear
        month = newMonth
    }
}

// MARK: - 加班：全屏日历

struct OvertimeCalendarScreen: View {
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var year = 0
    @State private var month = 0
    @State private var editingDay: CalendarDay?

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

    private var hourlyBase: Double {
        OvertimeMath.hourlyBase(store.state.overtime)
    }

    var body: some View {
        let y = $year
        let m = $month

        return FullCalendarShell(year: y, month: m, weeks: weeks) { day in
            dayCell(day)
        }
        .onAppear(perform: syncFromState)
        .sheet(item: $editingDay) { day in
            OvertimeDayEditor(day: day)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
    }

    private func syncFromState() {
        year = Int(calendar.year)
        month = Int(calendar.month)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let amount = dayPay(day)
        let hasData = day.hours > 0

        return Button {
            editingDay = day
        } label: {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 19, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.white : day.type == .holiday ? .red : .primary)
                    .frame(width: 30, height: 30)
                    .background {
                        if day.isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }

                if hasData {
                    Text("\(String(format: "%g", day.hours))h")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(Money.format(amount))
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(day.type.short)
                        .font(.system(size: 11))
                        .foregroundStyle(typeColor(day))
                }

                Spacer(minLength: 0)

                // 底部彩条：有数据才显示
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(hasData ? barColor(day) : Color.clear)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if day.overridden {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private func dayPay(_ day: CalendarDay) -> Double {
        guard day.hours > 0 else { return 0 }
        return Money.round2(day.hours * Money.round4(hourlyBase * day.type.multiplier))
    }

    private func typeColor(_ day: CalendarDay) -> Color {
        switch day.type {
        case .workday: .secondary
        case .rest: .orange
        case .holiday: .red
        }
    }

    private func barColor(_ day: CalendarDay) -> Color {
        switch day.type {
        case .workday: .blue
        case .rest: .orange
        case .holiday: .red
        }
    }
}

// MARK: - 加班：某一天的编辑弹层

struct OvertimeDayEditor: View {
    let day: CalendarDay
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var hours: Double = 0

    private var hourlyBase: Double {
        OvertimeMath.hourlyBase(store.state.overtime)
    }

    private var amount: Double {
        guard hours > 0 else { return 0 }
        return Money.round2(hours * Money.round4(hourlyBase * day.type.multiplier))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                // 日期 + 档位
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(day.month) 月 \(day.day) 日")
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                    Text(weekdayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // 档位切换
                VStack(alignment: .leading, spacing: 6) {
                    Text("档位")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SegmentedPicker(
                        options: [
                            (value: DayType.workday, label: "工作日 1.5×"),
                            (value: .rest, label: "休息日 2×"),
                            (value: .holiday, label: "节假日 3×"),
                        ],
                        selection: Binding(
                            get: { day.type },
                            set: { setType($0) }
                        )
                    )
                }

                // 工时
                VStack(alignment: .leading, spacing: 8) {
                    Text("加班工时")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        AmountField(value: $hours, suffix: "小时", precision: 1)
                    }

                    HStack(spacing: 8) {
                        ForEach([2.0, 3.0, 4.0, 8.0], id: \.self) { value in
                            Button {
                                hours = value
                            } label: {
                                Text("\(Int(value))h")
                                    .font(.system(size: 14, weight: .medium))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(Color(.secondarySystemBackground))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 金额
                HStack {
                    Text("当日加班费")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("¥" + Money.format(amount))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("编辑加班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") {
                        commit(0)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        commit(hours)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                hours = store.state.overtime.calendar?.hours[day.key] ?? 0
            }
        }
    }

    private var weekdayLabel: String {
        let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return labels[max(0, min(6, day.weekday))]
    }

    /// 改档位：写进 overrides（与默认一致时则删除）
    private func setType(_ type: DayType) {
        var calendar = store.state.overtime.calendar ?? .empty()
        let defaultType = HolidayRules.defaultDayType(
            year: day.year, month: day.month, day: day.day
        )
        if type == defaultType {
            calendar.overrides.removeValue(forKey: day.key)
        } else {
            calendar.overrides[day.key] = type
        }
        store.state.overtime.calendar = calendar
    }

    private func commit(_ value: Double) {
        var calendar = store.state.overtime.calendar ?? .empty()
        let rounded = Money.round2(max(0, value))
        if rounded <= 0 {
            calendar.hours.removeValue(forKey: day.key)
        } else {
            calendar.hours[day.key] = rounded
        }
        store.state.overtime.calendar = calendar
        // 日历 → 三档合计
        store.syncHoursFromCalendar(entryModeCalendar: true)
    }
}

// MARK: - 误餐：全屏日历

struct MealCalendarScreen: View {
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var year = 0
    @State private var month = 0
    @State private var editingDay: CalendarDay?

    private var calendar: MealCalendar {
        store.state.mealAllowance.calendar
    }

    private var rates: MealRates {
        store.state.mealAllowance.rates
    }

    private var weeks: [[CalendarDay?]] {
        HolidayRules.buildMonth(
            year: year,
            month: month,
            hours: [:],
            overrides: calendar.overrides
        )
    }

    var body: some View {
        let y = $year
        let m = $month

        return FullCalendarShell(year: y, month: m, weeks: weeks) { day in
            dayCell(day)
        }
        .onAppear(perform: syncFromState)
        .sheet(item: $editingDay) { day in
            MealDayEditor(day: day)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
    }

    private func syncFromState() {
        year = Int(calendar.year)
        month = Int(calendar.month)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let counts = calendar.meals[day.key] ?? .zero
        let isTrip = calendar.trips[day.key] == true
        let amount = dayAmount(day)
        let hasData = counts.total > 0

        return Button {
            editingDay = day
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text("\(day.day)")
                        .font(.system(size: 19, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(day.isToday ? Color.white : day.type == .holiday ? .red : .primary)
                        .frame(width: 30, height: 30)
                        .background {
                            if day.isToday {
                                Circle().fill(Color.accentColor)
                            }
                        }

                    if isTrip {
                        Text("出")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.accentColor))
                    }
                }

                if hasData {
                    Text(mealSummary(counts))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(Money.format(amount))
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(day.type.short)
                        .font(.system(size: 11))
                        .foregroundStyle(typeColor(day))
                }

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(hasData ? (isTrip ? Color.accentColor : .green) : Color.clear)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mealSummary(_ counts: MealCounts) -> String {
        var parts: [String] = []
        if counts.breakfast > 0 { parts.append("早") }
        if counts.lunch > 0 { parts.append("中") }
        if counts.dinner > 0 { parts.append("晚") }
        return parts.joined(separator: " ")
    }

    private func dayAmount(_ day: CalendarDay) -> Double {
        guard let counts = calendar.meals[day.key], counts.total > 0 else { return 0 }
        let scene = MealAllowanceMath.scene(
            dayType: day.type,
            isTrip: calendar.trips[day.key] == true
        )
        return counts.amount(with: rates[scene])
    }

    private func typeColor(_ day: CalendarDay) -> Color {
        switch day.type {
        case .workday: .secondary
        case .rest: .orange
        case .holiday: .red
        }
    }
}

// MARK: - 误餐：某一天的编辑弹层

struct MealDayEditor: View {
    let day: CalendarDay
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var counts: MealCounts = .zero
    @State private var isTrip = false

    private var rates: MealRates { store.state.mealAllowance.rates }

    private var scene: MealScene {
        MealAllowanceMath.scene(dayType: day.type, isTrip: isTrip)
    }

    private var amount: Double {
        counts.amount(with: rates[scene])
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(day.month) 月 \(day.day) 日")
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                    Text(weekdayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // 出差开关
                Toggle(isOn: $isTrip) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("出差")
                            .font(.subheadline)
                        Text("打开后当天三餐按出差单价计算")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.accentColor)

                // 三餐
                VStack(alignment: .leading, spacing: 8) {
                    Text("领到的餐次")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Button {
                                counts[slot] = counts[slot] > 0 ? 0 : 1
                            } label: {
                                VStack(spacing: 4) {
                                    Text(slot.label)
                                        .font(.system(size: 18, weight: .medium))
                                    Text("¥" + Money.format(rates[scene][slot]))
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 68)
                                .foregroundStyle(counts[slot] > 0 ? .white : .secondary)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(counts[slot] > 0
                                              ? Color.accentColor
                                              : Color(.secondarySystemBackground))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Text("当日误餐补贴")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("¥" + Money.format(amount))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("编辑误餐补贴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") {
                        commit(.zero, trip: isTrip)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        commit(counts, trip: isTrip)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                counts = store.state.mealAllowance.calendar.meals[day.key] ?? .zero
                isTrip = store.state.mealAllowance.calendar.trips[day.key] == true
            }
        }
    }

    private var weekdayLabel: String {
        let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return labels[max(0, min(6, day.weekday))]
    }

    private func commit(_ newCounts: MealCounts, trip: Bool) {
        var calendar = store.state.mealAllowance.calendar
        if newCounts.total > 0 {
            calendar.meals[day.key] = newCounts
        } else {
            calendar.meals.removeValue(forKey: day.key)
        }
        if trip {
            calendar.trips[day.key] = true
        } else {
            calendar.trips.removeValue(forKey: day.key)
        }
        store.state.mealAllowance.calendar = calendar
    }
}

// MARK: - 入口卡片

/// 主界面上的日历入口：只显示月份、已填天数和本月金额。
struct CalendarEntryCard: View {
    let monthLabel: String
    /// 已填天数
    let filledDays: Int
    /// 本月合计金额
    let amount: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(monthLabel)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("已填 \(filledDays) 天 · ¥\(Money.format(amount))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("编辑")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            }
        }
        .buttonStyle(.plain)
    }
}
