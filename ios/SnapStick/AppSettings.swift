//
//  AppSettings.swift
//  SnapStick
//
//  应用设置：贴纸物理沙盒的移动速度与倾斜灵敏度（存 UserDefaults）。
//

import Foundation
import Combine
import SwiftUI

/// 外观主题：跟随系统 / 白天 / 黑夜
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// 本地化标签
    var labelKey: LocalizedStringKey {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "白天"
        case .dark:   return "黑夜"
        }
    }

    /// 应用到视图的 colorScheme，跟随系统时为 nil
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultSpeed = 3.6
    static let defaultSensitivity = 2.2
    static let defaultAppearance = AppearanceMode.system
    static let defaultDoubaoModelID = "doubao-seed-2-0-mini-260428"
    static let defaultDoubaoBaseURL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
    static let doubaoAPIKeyKey = "doubao.apiKey"
    /// 显影时间默认 5s，可调范围 3~8s
    static let defaultDevelopTime = 5.0
    static let developTimeRange = 3.0...8.0

    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: "sticker.speed") }
    }
    @Published var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sticker.sensitivity") }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "app.appearance") }
    }
    /// 不摇晃时照片的整体显影时间（秒）；摇一摇仍可加速。
    @Published var developTime: Double {
        didSet { UserDefaults.standard.set(developTime, forKey: "develop.time") }
    }
    /// 拍照出纸时的马达声音（快门「咔」不受影响，默认开启）。
    @Published var motorSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(motorSoundEnabled, forKey: "sound.motor") }
    }
    /// 快门拍照声音（出纸马达声不受影响，默认开启）。
    @Published var shutterSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(shutterSoundEnabled, forKey: "sound.shutter") }
    }
    /// 贴纸以足够速度砸到屏幕边缘时是否触发一次震动（默认开启）。
    @Published var wallHitHaptic: Bool {
        didSet { UserDefaults.standard.set(wallHitHaptic, forKey: "haptic.wallHit") }
    }
    /// 界面语言：跟随系统 / 中文 / English（注入到根视图的 environment locale）。
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app.language") }
    }
    /// 用户自己的火山方舟 API Key，只保存在本机钥匙串。
    @Published var doubaoAPIKey: String {
        didSet { KeychainStore.set(doubaoAPIKey, forKey: Self.doubaoAPIKeyKey) }
    }
    /// 豆包视觉模型 ID 或火山方舟 Endpoint ID。
    @Published var doubaoModelID: String {
        didSet { UserDefaults.standard.set(doubaoModelID, forKey: "doubao.modelID") }
    }
    /// 火山方舟 Chat Completions 地址，默认北京区公共地址。
    @Published var doubaoBaseURL: String {
        didSet { UserDefaults.standard.set(doubaoBaseURL, forKey: "doubao.baseURL") }
    }

    var doubaoConfigured: Bool {
        !doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !doubaoModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: doubaoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    init() {
        let d = UserDefaults.standard
        speed = d.object(forKey: "sticker.speed") as? Double ?? Self.defaultSpeed
        sensitivity = d.object(forKey: "sticker.sensitivity") as? Double ?? Self.defaultSensitivity
        appearance = (d.string(forKey: "app.appearance")
            .flatMap(AppearanceMode.init(rawValue:))) ?? Self.defaultAppearance
        developTime = d.object(forKey: "develop.time") as? Double ?? Self.defaultDevelopTime
        motorSoundEnabled = d.object(forKey: "sound.motor") as? Bool ?? true     // 默认 true（开启）
        shutterSoundEnabled = d.object(forKey: "sound.shutter") as? Bool ?? true // 默认 true（开启）
        wallHitHaptic = d.object(forKey: "haptic.wallHit") as? Bool ?? true // 默认 true（开启）
        language = (d.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:))) ?? .system
        doubaoAPIKey = KeychainStore.string(forKey: Self.doubaoAPIKeyKey) ?? ""
        doubaoModelID = d.string(forKey: "doubao.modelID") ?? Self.defaultDoubaoModelID
        doubaoBaseURL = d.string(forKey: "doubao.baseURL") ?? Self.defaultDoubaoBaseURL
    }
}
