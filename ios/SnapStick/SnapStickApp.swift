//
//  SnapStickApp.swift
//  SnapStick
//
//  对准、按下快门，让 AI 把此刻冲印成一张专属贴纸。
//

import SwiftUI

@main
struct SnapStickApp: App {
    @StateObject private var store = PhotoStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            // 主题/语言相关的根级修饰符放进一个会观察 settings 的 View（RootView）里。
            // 若直接写在 WindowGroup 的 ContentView 上，App 级 @StateObject 变化不会可靠地
            // 重新应用这些修饰符（设置能写回并持久化，但实时不生效）——这正是主题/语言切不动的根因。
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}

/// 根视图：通过 @EnvironmentObject 观察 settings，settings 变化时 body 重算，
/// 主题外观与界面语言便会实时应用（无需重启）。
private struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ContentView()
            .preferredColorScheme(settings.appearance.colorScheme)
            // App 内语言切换：注入所选 locale，SwiftUI Text 即时按该语言查表（无需重启）。
            .environment(\.locale, settings.language.locale)
            .statusBarHidden()
    }
}
