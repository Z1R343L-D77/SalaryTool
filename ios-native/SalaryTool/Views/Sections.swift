//
//  Sections.swift
//  六个栏目。共用 GlassCard + InsetPanel 的视觉语言。
//

import SwiftUI

// MARK: - 收入项

struct IncomeSectionView: View {
    @Environment(SalaryStore.self) private var store
    @State private var presetIndex = 0

    private var total: Double {
        Money.round2(store.state.incomes.reduce(0) { $0 + $1.amount })
    }

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "收入项",
                    subtitle: "开关决定计入哪个基数、是否计税",
                    trailing: Money.format(total)
                )

                ForEach($store.state.incomes) { $item in
                    incomeRow(item: $item)
                }

                HStack(spacing: 10) {
                    Picker("类型", selection: $presetIndex) {
                        ForEach(Array(IncomePreset.all.enumerated()), id: \.offset) { index, preset in
                            Text(preset.label).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.addIncome(label: IncomePreset.all[presetIndex].label)
                    } label: {
                        Text("添加")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(ChipButtonStyle())
                }

                if !store.state.incomes.isEmpty {
                    InsetPanel(cornerRadius: 16) {
                        VStack(spacing: 0) {
                            StatRow(
                                label: "计入社保",
                                value: Money.format(
                                    Calculator.suggestSocialBase(store.state.incomes)
                                )
                            )
                            Divider().opacity(0.4)
                            StatRow(
                                label: "计入公积金",
                                value: Money.format(
                                    Calculator.suggestHousingFundBase(store.state.incomes)
                                )
                            )
                            Divider().opacity(0.4)
                            StatRow(label: "计税收入", value: Money.format(store.result.taxableIncome))
                        }
                    }
                }
            }
        }
    }

    private func incomeRow(item: Binding<IncomeItem>) -> some View {
        InsetPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LabelField(text: item.label, placeholder: "收入名称")
                    Spacer(minLength: 8)
                    Button {
                        store.removeIncome(id: item.wrappedValue.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                AmountField(value: item.amount)

                HStack(spacing: 8) {
                    ToggleChip(title: "社保", isOn: item.includeInSocialBase)
                    ToggleChip(title: "公积金", isOn: item.includeInHousingFundBase)
                    ToggleChip(title: "计税", isOn: item.taxable)
                }
            }
        }
    }
}

// MARK: - 专项附加扣除

struct SpecialSectionView: View {
    @Environment(SalaryStore.self) private var store

    private let fields: [(key: WritableKeyPath<SpecialDeductions, Double>, label: String, hint: String)] = [
        (\.childrenEducation, "子女教育", "2000 元/月/子女"),
        (\.continuingEducation, "继续教育", "400 元/月"),
        (\.infantCare, "婴幼儿照护", "2000 元/月/婴幼儿"),
        (\.housingLoanInterest, "住房贷款利息", "1000 元/月"),
        (\.housingRent, "住房租金", "1500 / 1100 / 800 元/月"),
        (\.elderlyCare, "赡养老人", "3000 元/月（独生）"),
        (\.seriousIllness, "大病医疗", "年度汇算，一般填 0"),
    ]

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "专项附加扣除",
                    subtitle: "每月金额，减少应纳税所得额",
                    trailing: Money.format(store.state.special.total)
                )

                InsetPanel(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.label)
                                            .font(.subheadline)
                                        Text(field.hint)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                AmountField(value: Binding(
                                    get: { store.state.special[keyPath: field.key] },
                                    set: { store.state.special[keyPath: field.key] = $0 }
                                ))
                            }
                            .padding(.vertical, 10)

                            if index < fields.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }

                Text("同一项扣除在家庭成员间需按约定分摊，这里只填你本人可享受的金额。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 社保公积金

struct SocialSectionView: View {
    @Environment(SalaryStore.self) private var store

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "社保 / 公积金",
                    subtitle: "个人缴纳部分",
                    trailing: Money.format(store.result.social.total)
                )

                Picker("城市", selection: Binding(
                    get: { store.state.cityId },
                    set: { store.applyCity($0) }
                )) {
                    ForEach(CityRepository.all) { city in
                        Text(city.name).tag(city.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)

                baseBlock(
                    title: "社保基数",
                    base: Binding(
                        get: { store.state.social.socialBase },
                        set: { store.state.social.socialBase = $0 }
                    ),
                    mode: Binding(
                        get: { store.state.socialBaseMode },
                        set: { store.state.socialBaseMode = $0 }
                    ),
                    min: store.state.social.socialBaseMin,
                    max: store.state.social.socialBaseMax,
                    suggested: Calculator.suggestSocialBase(store.state.incomes)
                )

                baseBlock(
                    title: "公积金基数",
                    base: Binding(
                        get: { store.state.social.housingFundBase },
                        set: { store.state.social.housingFundBase = $0 }
                    ),
                    mode: Binding(
                        get: { store.state.housingFundBaseMode },
                        set: { store.state.housingFundBaseMode = $0 }
                    ),
                    min: store.state.social.housingFundBaseMin,
                    max: store.state.social.housingFundBaseMax,
                    suggested: Calculator.suggestHousingFundBase(store.state.incomes)
                )

                InsetPanel(cornerRadius: 18) {
                    VStack(spacing: 0) {
                        rateRow("养老保险", \.pensionRate)
                        Divider().opacity(0.4)
                        rateRow("医疗保险", \.medicalRate)
                        Divider().opacity(0.4)
                        rateRow("失业保险", \.unemploymentRate)
                        Divider().opacity(0.4)
                        rateRow("住房公积金", \.housingFundRate)
                    }
                }

                Text("基数为示例默认值，请以当地人社局最新公布为准；所有比例均可直接修改。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func baseBlock(
        title: String,
        base: Binding<Double>,
        mode: Binding<String>,
        min: Double,
        max: Double,
        suggested: Double
    ) -> some View {
        InsetPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    SegmentedPicker(
                        options: [(value: "auto", label: "自动"), (value: "manual", label: "手动")],
                        selection: mode
                    )
                    .frame(width: 130)
                }

                AmountField(value: base)

                Text(mode.wrappedValue == "auto"
                     ? "按收入推算：\(Money.format(suggested)) 元"
                     : "区间 \(Money.formatInteger(min)) – \(Money.formatInteger(max))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rateRow(
        _ label: String,
        _ key: WritableKeyPath<SocialConfig, Double>
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Money.formatRate(store.state.social[keyPath: key]))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - 累计数据

struct YtdSectionView: View {
    @Environment(SalaryStore.self) private var store

    private let months = Array(1...12)

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "累计数据与年终奖", subtitle: "累计预扣预缴需要本年度已累计的金额")

                InsetPanel(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("当年第几个月")
                                .font(.subheadline)
                            Spacer()
                            Picker("月份", selection: Binding(
                                get: { Int(store.state.ytd.monthIndex) },
                                set: { store.state.ytd.monthIndex = Double($0) }
                            )) {
                                ForEach(months, id: \.self) { Text("\($0) 月").tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                        }

                        Divider().opacity(0.4)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("减除费用口径")
                                    .font(.subheadline)
                                Text(store.state.ytd.deductionMonths > 0
                                     ? "5000 × \(store.state.ytd.deductionMonths) 个月"
                                     : "")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            SegmentedPicker(
                                options: [
                                    (value: BasicDeductionMode.calendarMonth, label: "当年"),
                                    (value: BasicDeductionMode.employedMonth, label: "本单位"),
                                ],
                                selection: Binding(
                                    get: { store.state.ytd.basicDeductionMode ?? .calendarMonth },
                                    set: { store.state.ytd.basicDeductionMode = $0 }
                                )
                            )
                            .frame(width: 150)
                        }
                    }
                }

                SegmentedPicker(
                    options: [(value: "manual", label: "手填累计"), (value: "records", label: "按月记录")],
                    selection: Binding(
                        get: { store.state.ytdMode },
                        set: { store.state.ytdMode = $0 }
                    )
                )

                if store.state.ytdMode == "manual" {
                    manualFields
                } else {
                    recordsList
                }

                bonusBlock
            }
        }
    }

    private var manualFields: some View {
        InsetPanel(cornerRadius: 18) {
            VStack(spacing: 12) {
                cumulativeField(
                    "截至上月累计收入",
                    get: { store.state.ytd.taxableIncome },
                    set: { store.state.ytd.taxableIncome = $0 }
                )
                cumulativeField(
                    "累计社保公积金",
                    get: { store.state.ytd.socialDeduction },
                    set: { store.state.ytd.socialDeduction = $0 }
                )
                cumulativeField(
                    "累计专项附加扣除",
                    get: { store.state.ytd.specialDeduction },
                    set: { store.state.ytd.specialDeduction = $0 }
                )
                cumulativeField(
                    "累计已预缴税额",
                    get: { store.state.ytd.taxPaid },
                    set: { store.state.ytd.taxPaid = $0 }
                )
            }
        }
    }

    private func cumulativeField(
        _ label: String,
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            AmountField(value: Binding(get: get, set: set))
        }
    }

    /// 按月记录列表。
    ///
    /// `@Bindable` 必须在这里再声明一次：`recordsList` 是独立计算属性，
    /// body 里那个 `@Bindable var store` 不在它的作用域内。
    ///
    /// 另外，ForEach 里那串 Picker + Binding 嵌套太深，Swift 的类型检查器
    /// 会超时（"unable to type-check in reasonable time"），所以把每一行
    /// 抽成独立的 `recordRow` 视图。
    private var recordsList: some View {
        @Bindable var store = store

        return VStack(spacing: 10) {
            ForEach($store.state.months) { $record in
                recordRow(record: $record)
            }

            Button {
                store.addMonth()
            } label: {
                Text("+ 添加月份")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    }
            }
            .buttonStyle(.plain)
        }
    }

    /// 单条月度记录
    private func recordRow(record: Binding<MonthRecord>) -> some View {
        InsetPanel(cornerRadius: 16) {
            VStack(spacing: 8) {
                HStack {
                    MonthPicker(month: record.month)
                    Spacer()
                    Button {
                        store.removeMonth(id: record.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                AmountField(value: record.taxableIncome)
                AmountField(value: record.socialDeduction)
                AmountField(value: record.specialDeduction)
                AmountField(value: record.taxPaid)
            }
        }
    }

    private var bonusBlock: some View {
        InsetPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("年终奖（仅在发放当月填写）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                AmountField(value: Binding(
                    get: { store.state.annualBonus },
                    set: { store.state.annualBonus = $0 }
                ))

                SegmentedPicker(
                    options: [
                        (value: "separate", label: "单独计税"),
                        (value: "combined", label: "并入综合所得"),
                    ],
                    selection: Binding(
                        get: { store.state.bonusTaxMode },
                        set: { store.state.bonusTaxMode = $0 }
                    )
                )

                Text("全年一次性奖金单独计税政策目前延续至 2027 年底，每年只能用一次。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 其他扣除

struct DeductionSectionView: View {
    @Environment(SalaryStore.self) private var store
    @State private var presetIndex = 0

    var body: some View {
        @Bindable var store = store

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "其他扣除", subtitle: "税后扣款不影响个税")

                if store.state.deductions.isEmpty {
                    Text("暂无其他扣除项，没有可以留空。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach($store.state.deductions) { $item in
                        InsetPanel(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    LabelField(text: $item.label, placeholder: "扣款名称")
                                    Spacer(minLength: 8)
                                    Button {
                                        store.removeDeduction(id: item.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, height: 32)
                                            .background(Circle().fill(.primary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }

                                AmountField(value: $item.amount)

                                ToggleChip(title: "税前扣除", isOn: $item.preTax)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Picker("类型", selection: $presetIndex) {
                        ForEach(Array(DeductionPreset.all.enumerated()), id: \.offset) { index, preset in
                            Text(preset.label).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.addDeduction(label: DeductionPreset.all[presetIndex].label)
                    } label: {
                        Text("添加")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
        }
    }
}
