//
//  SettingsView.swift
//  设置面板。按 iOS 系统设置的「分组列表」组织，而不是一堆自定义卡片。
//
//  分组：
//    外观 —— 主题 / 字号 / 壁纸
//    数据 —— 导入 / 导出 / 重置
//    关于 —— 版本 / 链接
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(SalaryStore.self) private var store
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    @State private var showImport = false
    @State private var confirmReset = false
    @State private var exportResult: ExportResult?
    @State private var importError: String?

    private struct ExportResult: Identifiable {
        let id = UUID()
        let fileName: String
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showImport) {
                ImportView()
            }
            .confirmationDialog(
                "重置所有数据？",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("重置，并恢复示例配置", role: .destructive) {
                    store.reset()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会清空收入、扣除、累计记录与加班数据，这一步不能撤销。外观设置不受影响。")
            }
            .alert("导出成功", isPresented: .constant(exportResult != nil)) {
                Button("知道了") { exportResult = nil }
            } message: {
                Text("\(exportResult?.fileName ?? "")\n\n打开「文件」App → 我的 iPhone → SalaryTool 就能找到。")
            }
            .alert("导出失败", isPresented: .constant(importError != nil)) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        Section {
            Picker("主题", selection: $appearance.theme) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("字号", selection: $appearance.fontScale) {
                ForEach(FontScale.allCases) { scale in
                    Text(scale.label).tag(scale)
                }
            }
            .pickerStyle(.segmented)

            Picker("壁纸", selection: $appearance.wallpaper) {
                ForEach(WallpaperChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        } header: {
            Text("外观")
        } footer: {
            Text("跟随系统时会随 iOS 的深浅色设置自动切换。壁纸只影响 iOS 版。")
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section {
            Button {
                showImport = true
            } label: {
                Label("导入配置", systemImage: "square.and.arrow.down")
            }

            Button {
                do {
                    exportResult = ExportResult(fileName: try store.export())
                } catch {
                    importError = error.localizedDescription
                }
            } label: {
                Label("导出备份", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("重置所有数据", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("导出文件保存在 App 的文档目录，打开「文件」App → 我的 iPhone → SalaryTool 可以看到。数据只在本机，不上传。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: appVersion)
            LabeledContent("最低系统", value: "iOS 26.0")
            LabeledContent("数据格式", value: "与 Windows 版通用")

            Link(destination: URL(string: "https://github.com/Z1R343L-D77/SalaryTool")!) {
                LabeledContent("源码", value: "GitHub")
            }
        } header: {
            Text("关于")
        } footer: {
            Text("计算逻辑为纯函数并有单元测试。结果仅供估算，以实际工资条为准。")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }
}

// MARK: - 栏目列表（底部工具栏右侧）

/// 等同于天气 App 里的城市列表：一屏看到全部栏目，点一项直接跳过去。
struct SectionListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SalaryStore.self) private var store
    @Environment(\.sectionJump) private var jump
    @Binding var current: RootView.Section

    var body: some View {
        NavigationStack {
            List {
                ForEach(RootView.Section.allCases) { item in
                    Button {
                        current = item
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 30, height: 30)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if current == item {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("栏目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
