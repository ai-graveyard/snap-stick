//
//  Localization.swift
//  SnapStick
//
//  国际化（中英文）基础设施。源语言是中文（zh-Hans），UI 字符串以中文原文为 key，
//  英文译文放在 Localizable.xcstrings / InfoPlist.xcstrings 里。
//
//  显示层全部走 SwiftUI 的 LocalizedStringKey + 环境 locale：
//  根视图把 `settings.language.locale` 注入 `\.environment(\.locale)`，
//  这样 App 内切换语言时，所有 `Text("中文")` 会即时按所选语言查表（无需重启）。
//  少数「拿到运行期 String 才能用」的场景（日期分组比较、清空记录的确认词），
//  用 `localizedString(_:locale:)` 显式按所选语言的 .lproj 取值，保证与界面一致。
//

import Foundation
import SwiftUI

/// App 语言：跟随系统 / 中文 / English。和「主题外观」并列，存 UserDefaults。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh = "zh-Hans"
    case en

    var id: String { rawValue }

    /// 选择器里的标签（自身就用各语言原文，跟随系统项随界面语言走）
    var labelKey: LocalizedStringKey {
        switch self {
        case .system: return "跟随系统"
        case .zh:     return "中文"
        case .en:     return "English"
        }
    }

    /// 注入 SwiftUI 环境的 locale；跟随系统用 autoupdatingCurrent。
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .zh:     return Locale(identifier: "zh-Hans")
        case .en:     return Locale(identifier: "en")
        }
    }
}

/// 按指定 locale 显式取本地化字符串（用于无法走 `Text` 的运行期 String 场景）。
/// 直接定位语言对应的 `.lproj` bundle 查表，从而与 App 内语言覆盖保持一致，
/// 而不是回退到系统语言（`String(localized:)` 默认行为）。
func localizedString(_ key: String, locale: Locale) -> String {
    let candidates = [locale.identifier, locale.language.languageCode?.identifier].compactMap { $0 }
    for code in candidates {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
    return NSLocalizedString(key, comment: "")
}
