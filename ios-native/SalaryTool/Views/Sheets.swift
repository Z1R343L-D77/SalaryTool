//
//  Sheets.swift
//  明细、设置、导入三个面板。
//

import SwiftUI
import UIKit

// MARK: - 明细

struct DetailView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exportName: String?
    @State private var errorText: String?
    @State private var copied = false

    private var r: SalaryResult { store.result }

    /// 明细四组的分项数据（和 Windows 版 ResultPanel 的展开区对齐）
    private var incomeRows: [(String, Double, String?)] {
        var rows: [(String, Double, String?)] = store.state.incomes
            .filter { $0.amount > 0 }
            .map { ($0.label, $0.amount, flags($0)) }
        if r.bonusGross > 0 {
            rows.append((
                "年终奖",
                r.bonusGross,
                store.state.bonusTaxMode == "separate" ? "单独计税" : "并入综合所得"
            ))
        }
        return rows
    }

    private func flags(_ item: IncomeItem) -> String {
        var parts: [String] = []
        if item.includeInSocialBase { parts.append("社保") }
        if item.includeInHousingFundBase { parts.append("公积金") }
        if item.taxable { parts.append("计税") }
        return parts.isEmpty ? "不计入任何基数" : parts.joined(separator: " · ")
    }

    private var socialRows: [(String, Double)] {
        var rows: [(String, Double)] = [
            ("养老保险", r.social.pension),
            ("医疗保险", r.social.medical),
            ("失业保险", r.social.unemployment),
        ]
        if r.social.medicalExtra > 0 {
            rows.append(("大额医疗互助", r.social.medicalExtra))
        }
        rows.append(("住房公积金", r.social.housingFund))
        return rows
    }

    private var deductionRows: [(String, Double, String)] {
        store.state.deductions
            .filter { $0.amount > 0 }
            .map { ($0.label, $0.amount, $0.preTax ? "税前扣除" : "税后扣除") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(spacing: 4) {
                            Text("本月实发到手")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("¥\(Money.format(r.netPay))")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            StatRow(label: "税前收入", value: Money.format(r.grossIncome))
                            Divider().opacity(0.4)
                            StatRow(label: "社保 / 公积金", value: "−" + Money.format(r.social.total))
                            Divider().opacity(0.4)
                            StatRow(label: "本月个税", value: "−" + Money.format(r.taxThisMonth))
                            Divider().opacity(0.4)
                            StatRow(label: "实际税负率", value: Money.formatRate(r.effectiveTaxRate))
                            Divider().opacity(0.4)
                            StatRow(label: "累计应纳税所得额", value: Money.format(r.cumulativeTaxable))
                            Divider().opacity(0.4)
                            StatRow(label: "累计应纳个税", value: Money.format(r.cumulativeTax))
                        }
                    }

                    // —— 收入 ——
                    breakdownCard(
                        title: "收入",
                        total: Money.format(r.grossIncome),
                        rows: incomeRows.map { ($0.0, $0.1, $0.2) }
                    )

                    // —— 社保 / 公积金（分项）——
                    breakdownCard(
                        title: "社保 / 公积金",
                        total: "−" + Money.format(r.social.total),
                        rows: socialRows.map { ($0.0, $0.1, nil) },
                        footer: "缴费基数 社保 \(Money.format(r.socialBaseUsed)) / 公积金 \(Money.format(r.housingFundBaseUsed))"
                    )

                    // —— 其他扣除 ——
                    if !deductionRows.isEmpty {
                        breakdownCard(
                            title: "其他扣除",
                            total: "−" + Money.format(
                                deductionRows.reduce(0) { $0 + $1.1 }
                            ),
                            rows: deductionRows.map { ($0.0, $0.1, $0.2) }
                        )
                    }

                    // —— 个人所得税 ——
                    breakdownCard(
                        title: "个人所得税",
                        total: "−" + Money.format(r.taxThisMonth),
                        rows: [("本月个人所得税", r.taxThisMonth, nil)],
                        footer: "专项附加扣除（每月）\(Money.format(r.specialDeductionTotal))"
                    )

                    if !store.hints.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(store.hints, id: \.self) { hint in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text(hint)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        // 复制摘要：纯文本，方便粘到微信/备忘录
                        Button {
                            copySummary()
                        } label: {
                            Label(
                                copied ? "已复制" : "复制摘要",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .controlSize(.large)

                        Button {
                            do {
                                exportName = try store.export()
                            } catch {
                                errorText = error.localizedDescription
                            }
                        } label: {
                            Text("导出备份")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                        .controlSize(.large)
                    }
                }
                .padding(16)
            }
            .navigationTitle("本月明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("已导出", isPresented: .constant(exportName != nil)) {
                Button("知道了") { exportName = nil }
            } message: {
                Text("\(exportName ?? "")\n\n打开「文件」App → 我的 iPhone → SalaryTool 就能找到。")
            }
            .alert("导出失败", isPresented: .constant(errorText != nil)) {
                Button("好") { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: 分组卡片

    private func breakdownCard(
        title: String,
        total: String,
        rows: [(String, Double, String?)],
        footer: String? = nil
    ) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(total)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.bottom, 8)

                BreakdownDivider()

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.0)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                            if let hint = row.2 {
                                Text(hint)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 12)
                        Text(Money.format(row.1))
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }

                if let footer {
                    BreakdownDivider()
                    Text(footer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: 复制摘要

    private func copySummary() {
        let lines = [
            "税前收入：\(Money.format(r.grossIncome)) 元",
            "社保公积金（个人）：\(Money.format(r.social.total)) 元",
            "本月个税：\(Money.format(r.taxThisMonth)) 元",
            "实发到手：\(Money.format(r.netPay)) 元",
        ]
        let city = CityRepository.policy(for: store.state.cityId).name
        let text = "【工资到手计算】\n"
            + lines.joined(separator: "\n")
            + "\n（城市：\(city)，第 \(Int(store.state.ytd.monthIndex)) 月）"

        UIPasteboard.general.string = text
        withAnimation(.snappy(duration: 0.2)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy(duration: 0.2)) { copied = false }
        }
    }
}

/// 细分隔线，和 StatRow 之间的视觉节奏一致
private struct BreakdownDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

// MARK: - 导入

struct ImportView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var errorText: String?
    @State private var showPicker = false
    @State private var pickedFileName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("粘贴配置内容，或者从「文件」里选一个 .json。导入后会覆盖当前所有输入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text(pickedFileName ?? "选择文件…")
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))

                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 220)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.primary.opacity(0.055))
                        }
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("{ \"cityId\": \"shanghai\", \"incomes\": [ … ] }")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .navigationTitle("导入配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do {
                            try store.importJSON(text)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // 沙盒外的文件要先申请访问权限
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        text = try String(contentsOf: url, encoding: .utf8)
                        pickedFileName = url.lastPathComponent
                        errorText = nil
                    } catch {
                        errorText = "读取文件失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
