//
//  Appearance.swift
//  外观设置：主题、壁纸、字号。
//
//  和 Windows 版一样存独立的 key —— 这是「怎么显示」，不是工资数据，
//  导出 JSON 时不该带上。
//

import SwiftUI
import Observation

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case system, dark, light
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "跟随系统"
        case .dark: "深色"
        case .light: "浅色"
        }
    }
}

enum FontScale: String, CaseIterable, Codable, Identifiable {
    case small, standard, large, xlarge
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        case .xlarge: "特大"
        }
    }

    /// 乘在正文基准字号上的系数
    var factor: Double {
        switch self {
        case .small: 0.92
        case .standard: 1.0
        case .large: 1.08
        case .xlarge: 1.16
        }
    }
}

enum WallpaperChoice: String, CaseIterable, Codable, Identifiable {
    case fuji, aurora, dusk, plain
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fuji: "富士山"
        case .aurora: "极光"
        case .dusk: "暮色"
        case .plain: "无壁纸"
        }
    }
}

@MainActor
@Observable
final class AppearanceStore {
    var theme: ThemeMode {
        didSet { save() }
    }
    var fontScale: FontScale {
        didSet { save() }
    }
    var wallpaper: WallpaperChoice {
        didSet { save() }
    }

    private static let key = "salarytool.appearance.v1"

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        let decoded = data.flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
        theme = decoded?.theme ?? .system
        fontScale = decoded?.fontScale ?? .standard
        wallpaper = decoded?.wallpaper ?? .fuji
    }

    private struct Payload: Codable {
        var theme: ThemeMode
        var fontScale: FontScale
        var wallpaper: WallpaperChoice
    }

    private func save() {
        let payload = Payload(theme: theme, fontScale: fontScale, wallpaper: wallpaper)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    var preferredScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }

    func reset() {
        theme = .system
        fontScale = .standard
        wallpaper = .fuji
    }
}

// MARK: - 壁纸

/// 四种壁纸的绘制。图片型用 Assets 里的，其余用渐变。
struct WallpaperView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appearance.wallpaper {
        case .fuji:
            Image("wallpaper")
                .resizable()
                .scaledToFill()
                .overlay(scrim)
        case .aurora:
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(hex: 0x06131F), Color(hex: 0x0B2F3A), Color(hex: 0x12615A), Color(hex: 0x0A2333)]
                    : [Color(hex: 0xDCEAF5), Color(hex: 0xC3E2DE), Color(hex: 0xE6F2FA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(scrim)
        case .dusk:
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(hex: 0x1A1030), Color(hex: 0x3A1A4D), Color(hex: 0x7A2F4A), Color(hex: 0xC2673F), Color(hex: 0x2A1526)]
                    : [Color(hex: 0xF2E6F7), Color(hex: 0xF7DFE6), Color(hex: 0xFBE8D8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(scrim)
        case .plain:
            (scheme == .dark ? Color(hex: 0x0F1216) : Color(hex: 0xEEF1F6))
        }
    }

    /// 压暗（或压亮），保证文字可读
    private var scrim: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [.black.opacity(0.35), .black.opacity(0.62)]
                : [.white.opacity(0.05), .black.opacity(0.18)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
