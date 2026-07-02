//
//  PaperStyle.swift
//  SnapStick
//
//  「相纸」目录（单一来源，类比 Palette）。相纸只决定最终产出的边框 / 衬纸 /
//  版式外观，不影响 Vision 抠图，也不影响沙盒物理与音效。全部相纸均免费、随时可切换。
//

import SwiftUI

/// 相纸上的装饰元素（均为通用素材，规避任何拍立得商标元素）
enum PaperDeco: Equatable {
    case none
    case perforations   // 35mm 胶片齿孔（通用胶片元素）
    case washiTape      // 仿和纸胶带角贴
    case dots           // 手帐圆点
}

/// 一种相纸样式。视觉参数全部在此声明，由 `PaperFrameView` / `PaperMat` 解释渲染。
struct PaperStyle: Identifiable, Equatable {
    let id: String
    /// 中文名（同时作为本地化 key，英文译文见 Localizable.xcstrings）
    let name: String
    /// 本地化显示名：按界面 locale 查表（走 `Text` 时用它，而非裸 `name`）
    var displayName: LocalizedStringKey { LocalizedStringKey(name) }
    /// 照片衬纸（mat）渐变上 / 下色；纯色时两者相同
    let matTop: Color
    let matBottom: Color
    /// 相纸边框 / 底部白边色
    let border: Color
    /// 日期等文字色
    let captionInk: Color
    /// 装饰
    let deco: PaperDeco
    /// 「无相纸」：不套相纸，仅保留透明背景的模切贴纸（导出为透明 PNG，无边框 / 日期）。
    /// 预览与缩略图以棋盘格示意透明背景。
    var isBare: Bool = false

    var matColors: [Color] { [matTop, matBottom] }
}

/// 相纸目录。新增 / 调整相纸只改这里。
enum PaperCatalog {
    static let defaultID = "cream"

    static let all: [PaperStyle] = [
        PaperStyle(id: "none", name: "无相纸",
                   matTop: .clear, matBottom: .clear,
                   border: .clear, captionInk: .clear,
                   deco: .none, isBare: true),
        PaperStyle(id: "cream", name: "经典奶油白",
                   matTop: Palette.cream, matBottom: Color(red: 0.953, green: 0.929, blue: 0.882),
                   border: Color(red: 0.99, green: 0.988, blue: 0.973),
                   captionInk: Color(white: 0.4), deco: .none),
        PaperStyle(id: "kraft", name: "牛皮手帐",
                   matTop: Palette.kraft, matBottom: Color(red: 0.78, green: 0.70, blue: 0.59),
                   border: Color(red: 0.72, green: 0.64, blue: 0.52),
                   captionInk: Palette.ink, deco: .dots),
        PaperStyle(id: "klein", name: "克莱因蓝",
                   matTop: Palette.cream, matBottom: Palette.cream,
                   border: Palette.klein,
                   captionInk: Palette.klein, deco: .none),
        PaperStyle(id: "amber-glow", name: "琥珀暖光",
                   matTop: Palette.amber, matBottom: Color(red: 0.82, green: 0.52, blue: 0.16),
                   border: Color(red: 0.86, green: 0.58, blue: 0.22),
                   captionInk: .white, deco: .none),
        PaperStyle(id: "deep-sea", name: "深海渐变",
                   matTop: Palette.klein, matBottom: Palette.kleinDeep,
                   border: Palette.kleinDeep,
                   captionInk: .white, deco: .none),
        PaperStyle(id: "film-charcoal", name: "炭灰胶片",
                   matTop: Color(white: 0.13), matBottom: Color(white: 0.06),
                   border: Palette.faceplate,
                   captionInk: .white, deco: .perforations),
        PaperStyle(id: "journal-washi", name: "手帐胶带",
                   matTop: Palette.cream, matBottom: Palette.cream,
                   border: Color(red: 0.97, green: 0.95, blue: 0.91),
                   captionInk: Palette.ink, deco: .washiTape),
    ]

    static func style(for id: String) -> PaperStyle {
        all.first { $0.id == id } ?? all[0]
    }
}
