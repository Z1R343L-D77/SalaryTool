//
//  SalaryToolApp.swift
//  原生 SwiftUI 版本。iOS 26 起 SwiftUI 提供系统级 Liquid Glass，
//  这是 WebView 里做不到的部分（见 Calculator.swift 顶部注释）。
//

import SwiftUI

@main
struct SalaryToolApp: App {
    @State private var store = SalaryStore()
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(appearance)
                .preferredColorScheme(appearance.preferredScheme)
                // 字号档位作用在整棵视图树上，系统控件也会跟着缩放
                .dynamicTypeSize(appearance.dynamicTypeSize)
        }
    }
}
