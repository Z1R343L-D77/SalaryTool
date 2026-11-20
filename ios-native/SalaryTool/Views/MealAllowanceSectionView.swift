//
//  MealAllowanceSectionView.swift
//  加班误餐补贴。
//
//  和加班费是两条独立的线：
//  - 加班费 = 工时 × 倍率，受劳动法约束
//  - 误餐补贴 = 天数 × 餐次 × 单价，纯粹看公司制度
//
//  所以这里没有基数、没有倍率，只有一张单价表和一台按天记录的小日历。
//  九个单价都能改，改完所有已记录的餐次立刻按新价重算。
//

import SwiftUI

struct MealAllowanceSectionView: View {
    @Environment(SalaryStore.self) private var store

    private var input: MealAllowanceInput { store.state.mealAllowance }
    private var result: MealAllowanceResult { MealAllowanceMath.compute(input) }
    private var isCalendar: Bool { input.entryMode == "calendar" }
    private var syncEnabled: Bool { store.state.mealSync.enabled }
    private var boundIncome: IncomeItem? { store.findMealIncome() }

    /// 加班日历里是否有工时（决定「按加班记录补餐次」按钮是否可用）
    private var overtimeHoursTotal: Double {
        (store.state.overtime.calendar?.hours ?? [:]).values.reduce(0, +)
    }

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "误餐补贴",
                    subtitle: "按天记录，工作日 / 周末 / 出差三套单价",
                    trailing: "¥" + Money.format(result.total)
                )

                // 录入方式
                SegmentedPicker(
                    options: [
                        (value: "manual", label: "直接填餐次"),
                        (value: "calendar", label: "按日历填写"),
                    ],
                    selection: Binding(
                        get: { store.state.mealAllowance.entryMode },
                        set: { store.state.mealAllowance.entryMode = $0 }
                    )
                )

                ratesBlock

                if isCalendar {
                    calendarBlock
                } else {
                    manualBlock
                }

                totalBlock
                syncBlock
            }
        }
    }

    // MARK: 单价表

    private var ratesBlock: some View {
        InsetPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("单价（元/餐）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("改完立即重算")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // 表头
                HStack(spacing: 6) {
                    Text("")
                        .frame(width: 82, alignment: .leading)
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        Text(slot.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(MealScene.allCases, id: \.self) { scene in
                    HStack(spacing: 6) {
                        Text(scene.label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(width: 82, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            AmountField(
                                value: Binding(
                                    get: { store.state.mealAllowance.rates[scene][slot] },
                                    set: { store.state.mealAllowance.rates[scene][slot] = $0 }
                                ),
                                suffix: ""
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: 手填模式

    private var manualBlock: some View {
        InsetPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // 表头
                HStack(spacing: 6) {
                    Text("场景")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .leading)
                    ForEach(MealSlot.allCases, id: \.self) { slot in
                        Text(slot.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    Text("金额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }

                ForEach(MealScene.allCases, id: \.self) { scene in
                    HStack(spacing: 6) {
                        Text(scene.label)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(width: 82, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            AmountField(
                                value: Binding(
                                    get: { store.state.mealAllowance.manualCounts(scene)[slot] },
                                    set: { newValue in
                                        var counts = store.state.mealAllowance.manualCounts(scene)
                                        counts[slot] = newValue
                                        store.state.mealAllowance.setManualCounts(scene, counts)
                                    }
                                ),
                                suffix: ""
                            )
                        }

                        Text(Money.format(
                            store.state.mealAllowance.manualCounts(scene)
                                .amount(with: store.state.mealAllowance.rates[scene])
                        ))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: 日历模式

    private var calendarBlock: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button {
                    store.suggestMealsFromOvertime()
                } label: {
                    Text("按加班记录补餐次")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(overtimeHoursTotal <= 0)
            }

            MealCalendarView(
                calendar: $store.state.mealAllowance.calendar,
                rates: store.state.mealAllowance.rates
            )
        }
    }

    // MARK: 合计

    private var totalBlock: some View {
        InsetPanel(cornerRadius: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("误餐补贴合计")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("\(Money.format(result.totalMeals)) 餐 · 工作日 \(Money.format(result.meals(for: .workday))) · 周末 \(Money.format(result.meals(for: .weekend))) · 出差 \(Money.format(result.meals(for: .trip)))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("¥" + Money.format(result.total))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    // MARK: 同步

    private var syncBlock: some View {
        InsetPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToggleChip(
                        title: "同步到收入项",
                        isOn: Binding(
                            get: { store.state.mealSync.enabled },
                            set: { store.setMealSyncEnabled($0) }
                        )
                    )

                    Spacer(minLength: 8)

                    Button("清零餐次") {
                        store.resetMealCounts()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }

                if syncEnabled, let bound = boundIncome {
                    HStack(spacing: 6) {
                        Text("已写入「\(bound.label)」")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.format(bound.amount) + " 元")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                    }
                } else if !syncEnabled {
                    Text("关闭时只计算，不改动工资单")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
