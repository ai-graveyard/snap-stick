//
//  Palette.swift
//  SnapStick
//
//  全局品牌调色板（单一来源）。
//  设计方向：克莱因蓝作「签名色」点缀，整体走温暖纸面 / 手帐质感 —— 冷蓝 + 暖纸，
//  既保留高级感又有手帐的温度。所有第三方商标元素一概不用。
//

import SwiftUI
import UIKit

enum Palette {
    /// 主题签名色：克莱因蓝 #002FA7
    static let klein     = Color(red: 0.0,   green: 0.184, blue: 0.655)
    /// 克莱因蓝深一档，用于渐变
    static let kleinDeep = Color(red: 0.0,   green: 0.122, blue: 0.467)
    /// 暖琥珀（蓝的互补色），用于快门等点缀
    static let amber     = Color(red: 0.96,  green: 0.66,  blue: 0.27)
    /// 镉黄 #FDD835，偏柠檬的清新黄，用于快门圆点（与克莱因蓝形成蓝黄撞色）
    static let cadmium   = Color(red: 0.99,  green: 0.85,  blue: 0.21)
    /// 暖墨色，用于浅色纸面上的文字 / 图标（用作阴影色，固定不随主题变）
    static let ink       = Color(red: 0.24,  green: 0.20,  blue: 0.15)
    /// 奶油纸（机身 / 相纸高光）
    static let cream     = Color(red: 0.965, green: 0.937, blue: 0.875)
    /// 牛皮纸（背景深处 / 暖光边缘）
    static let kraft     = Color(red: 0.835, green: 0.769, blue: 0.659)
    /// 顶部取景面板炭灰
    static let faceplate = Color(red: 0.16,  green: 0.165, blue: 0.18)

    // MARK: - 随主题自适应的语义色（白天 / 黑夜）

    /// 页面整屏背景：白天暖米白（手帐纸感，并与纯白卡片拉开层次），黑夜近黑
    static let surface = dynamic(light: UIColor(red: 0.97, green: 0.955, blue: 0.925, alpha: 1),
                                 dark:  UIColor(white: 0.08, alpha: 1))
    /// 卡片 / 面板填充：白天纯白，黑夜深灰
    static let card    = dynamic(light: .white,
                                 dark:  UIColor(white: 0.17, alpha: 1))
    /// 次级填充（占位块 / 小圆钮 / 浅底）：白天浅灰，黑夜中灰
    static let chip    = dynamic(light: UIColor(white: 0.93, alpha: 1),
                                 dark:  UIColor(white: 0.27, alpha: 1))
    /// 主文字 / 图标：白天暖墨，黑夜近白
    static let label   = dynamic(light: UIColor(red: 0.24, green: 0.20, blue: 0.15, alpha: 1),
                                 dark:  UIColor(white: 0.92, alpha: 1))

    /// 构造一个随 userInterfaceStyle 切换的动态 Color
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}
