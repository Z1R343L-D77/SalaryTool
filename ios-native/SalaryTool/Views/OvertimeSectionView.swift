//
//  OvertimeSectionView.swift
//  加班费：基数（月薪 ↔ 时薪双向同步）+ 两种工时录入方式（合计 / 日历）。
//
//  与 Windows 版的行为对齐：
//  - 改月薪，时薪跟着反算；改时薪，月薪跟着反算
//  - 日历改了，三档合计跟着更新（反过来不动日历，避免覆盖真实记录）
//

import SwiftUI

struct OvertimeSectionView: View {
    @Environment(SalaryStore.self) private var store

    private static let tiers: [(key: String, label: String, rate: Double, hint: String)] = [
        ("weekday", "工作日", 1.5, "延长工时 1.5 倍"),
        ("weekend", "周末", 2.0, "休息日 2 倍"),
        ("holiday", "节假日", 3.0, "法定节假日 3 倍"),
    ]

    private var overtime: OvertimeInput { store.state.overtime }
    private var hourlyBase: Double { OvertimeMath.hourlyBase(overtime) }
    private var totalPay: Double { OvertimeMath.totalPay(overtime) }
    private var isCalendar: Bool { overtime.entryMode == "calendar" }

    private var resolvedHours: (workday: Double, rest: Double, holiday: Double) {
        OvertimeMath.resolveHours(overtime)
    }

    private var totalHours: Double {
        let h = resolvedHours
        return Money.round2(h.workday + h.rest + h.holiday)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "加班费",
                    subtitle: "工作日 1.5 倍 · 周末 2 倍 · 节假日 3 倍",
                    trailing: "¥" + Money.format(totalPay)
                )

                SegmentedPicker(
                    options: [
                        (value: OvertimeBaseMode.monthly, label: "按月薪折算"),
                        (value: .hourly, label: "直接填时薪"),
                    ],
                    selection: Binding(
                        get: { store.state.overtime.mode },
                        set: { store.state.overtime.mode = $0 }
                    )
                )

                baseBlock
                entryModePicker

                if isCalendar {
                    OvertimeCalendarView()
                } else {
                    tierCards
                }

                totalBlock
            }
        }
    }

    // MARK: 基数

    private var baseBlock: some View {
        InsetPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(overtime.mode == .hourly ? "加班费基数（元/小时）" : "加班费基数（元/月）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                AmountField(
                    value: Binding(
                        get: {
                            store.state.overtime.mode == .hourly
                                ? store.state.overtime.hourlyRate
                                : store.state.overtime.base
                        },
                        set: { newValue in
                            if store.state.overtime.mode == .hourly {
                                // 改时薪 → 月薪跟着反算
                                store.state.overtime.hourlyRate = newValue
                                store.state.overtime.base = OvertimeMath.hourlyToMonthly(
                                    hourlyRate: newValue,
                                    monthlyDays: store.state.overtime.monthlyDays,
                                    dailyHours: store.state.overtime.dailyHours,
                                    currentBase: store.state.overtime.base
                                )
                            } else {
                                // 改月薪 → 时薪跟着反算
                                store.state.overtime.base = newValue
                                store.state.overtime.hourlyRate = OvertimeMath.monthlyToHourly(
                                    base: newValue,
                                    monthlyDays: store.state.overtime.monthlyDays,
                                    dailyHours: store.state.overtime.dailyHours
                                )
                            }
                        }
                    ),
                    suffix: overtime.mode == .hourly ? "元/时" : "元",
                    precision: 4
                )

                Text("折算小时工资 \(Money.formatPrecise(hourlyBase)) 元/小时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 录入方式

    private var entryModePicker: some View {
        SegmentedPicker(
            options: [
                (value: "manual", label: "直接填合计"),
                (value: "calendar", label: "按日历填写"),
            ],
            selection: Binding(
                get: { store.state.overtime.entryMode },
                set: { store.state.overtime.entryMode = $0 }
            )
        )
    }

    // MARK: 三档合计

    private var tierCards: some View {
        VStack(spacing: 10) {
            ForEach(Self.tiers, id: \.key) { tier in
                InsetPanel(cornerRadius: 16) {
                    VStack(spacing: 10) {
                        HStack {
                            Text(tier.label)
                                .font(.subheadline.weight(.semibold))
                            Text(Money.formatRate(tier.rate, digits: 0))
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            Spacer()
                        }

                        AmountField(value: binding(for: tier.key), suffix: "小时")

                        HStack {
                            Text(Money.formatPrecise(Money.round4(hourlyBase * tier.rate)) + " 元/小时")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(
                                Money.format(
                                    Money.round2(
                                        Money.round4(hourlyBase * tier.rate)
                                            * binding(for: tier.key).wrappedValue
                                    )
                                ) + " 元"
                            )
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                        }

                        HStack {
                            Text(tier.hint)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Double> {
        switch key {
        case "weekday":
            return Binding(
                get: { store.state.overtime.weekdayHours },
                set: { store.state.overtime.weekdayHours = $0 }
            )
        case "weekend":
            return Binding(
                get: { store.state.overtime.weekendHours },
                set: { store.state.overtime.weekendHours = $0 }
            )
        default:
            return Binding(
                get: { store.state.overtime.holidayHours },
                set: { store.state.overtime.holidayHours = $0 }
            )
        }
    }

    // MARK: 合计

    private var totalBlock: some View {
        InsetPanel(cornerRadius: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("加班费合计")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(Money.format(totalHours)) 小时 · 折合 \(Money.format(totalHours / max(1, overtime.dailyHours))) 个工作日")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("¥" + Money.format(totalPay))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }
}
