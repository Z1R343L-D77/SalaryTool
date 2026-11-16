//
//  Sheets.swift
//  明细、设置、导入三个面板。
//

import SwiftUI

// MARK: - 明细

struct DetailView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exportName: String?
    @State private var errorText: String?

    private var r: SalaryResult { store.result }

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
