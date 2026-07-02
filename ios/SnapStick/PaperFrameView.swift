//
//  PaperFrameView.swift
//  SnapStick
//
//  相纸的可视渲染：衬纸（mat）+ 装饰 + 完整相纸卡（用于结果页预览、选择器缩略图、
//  以及分享时栅格化成图片）。单一渲染逻辑，同时服务屏幕预览与导出。
//

import SwiftUI
import UIKit

// MARK: - 衬纸（照片区背景 + 贴纸 + 装饰）

/// 照片窗口内的衬纸：渐变底 + 居中贴纸 + 可选装饰。复用于结果页相纸窗口与缩略图。
struct PaperMat: View {
    let style: PaperStyle
    let image: UIImage
    /// 贴纸相对衬纸的内边距比例
    var insetRatio: CGFloat = 0.1

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if style.isBare {
                    // 无相纸：棋盘格示意透明背景，仅居中贴纸，无渐变 / 装饰
                    CheckerBackdrop(cell: side * 0.08)
                } else {
                    LinearGradient(colors: style.matColors, startPoint: .top, endPoint: .bottom)
                }
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(side * insetRatio)
                if !style.isBare {
                    PaperDecoView(deco: style.deco)
                }
            }
        }
    }
}

/// 透明背景棋盘格：用于「无相纸」预览 / 缩略图，提示导出为透明 PNG。
struct CheckerBackdrop: View {
    var cell: CGFloat = 12

    var body: some View {
        Canvas { ctx, size in
            let light = Color(white: 0.94)
            let dark = Color(white: 0.84)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for r in 0..<max(rows, 1) {
                for c in 0..<max(cols, 1) where (r + c) % 2 == 1 {
                    let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell,
                                      width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(dark))
                }
            }
        }
    }
}

/// 相纸装饰层
struct PaperDecoView: View {
    let deco: PaperDeco

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch deco {
            case .none:
                Color.clear
            case .perforations:
                // 左右两列胶片齿孔
                HStack {
                    perfColumn(h: h)
                    Spacer()
                    perfColumn(h: h)
                }
                .padding(.horizontal, w * 0.02)
            case .dots:
                // 顶部一排手帐圆点
                HStack(spacing: w * 0.04) {
                    ForEach(0..<6, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(0.5))
                            .frame(width: w * 0.018, height: w * 0.018)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, h * 0.04)
            case .washiTape:
                // 左上角一条仿和纸胶带
                Rectangle()
                    .fill(Palette.klein.opacity(0.35))
                    .frame(width: w * 0.34, height: h * 0.07)
                    .overlay(Rectangle().stroke(.white.opacity(0.4), lineWidth: 1))
                    .rotationEffect(.degrees(-18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: -w * 0.04, y: h * 0.05)
            }
        }
        .allowsHitTesting(false)
    }

    private func perfColumn(h: CGFloat) -> some View {
        VStack(spacing: h * 0.035) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.55))
                    .frame(width: h * 0.035, height: h * 0.05)
            }
        }
    }
}

// MARK: - 完整相纸卡（分享导出 + 选择器缩略图）

/// 一张完整的「相纸」：边框 + 方形衬纸照片 + 底部日期。
struct PaperFrameView: View {
    let style: PaperStyle
    let image: UIImage
    let date: Date
    /// 卡片基准宽度（缩略图传小值，分享传大值）
    var width: CGFloat = 300
    /// 界面 locale：屏幕预览自动继承环境；离屏分享渲染由 PaperRenderer 显式注入。
    @Environment(\.locale) private var locale

    private var pad: CGFloat { width * 0.055 }
    private var inner: CGFloat { width - pad * 2 }
    private var captionH: CGFloat { width * 0.2 }

    var body: some View {
        if style.isBare {
            // 无相纸：仅一张方形棋盘格 + 贴纸，无边框 / 日期（缩略图与导出语义一致）
            PaperMat(style: style, image: image)
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.02))
        } else {
            framedCard
        }
    }

    private var framedCard: some View {
        VStack(spacing: 0) {
            PaperMat(style: style, image: image)
                .frame(width: inner, height: inner)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.012))

            ZStack {
                HStack {
                    Text(PolaroidStudioView.dateString(date, locale: locale))
                        .font(.system(size: width * 0.045, weight: .medium))
                        .foregroundColor(style.captionInk)
                    Spacer()
                }
                .padding(.horizontal, width * 0.01)
            }
            .frame(width: inner, height: captionH)
        }
        .padding(pad)
        .background(
            RoundedRectangle(cornerRadius: width * 0.02)
                .fill(style.border)
        )
    }
}

// MARK: - 栅格化为图片（分享）

enum PaperRenderer {
    /// 把相纸卡渲染成高分辨率 UIImage，供系统分享面板使用。
    @MainActor
    static func image(style: PaperStyle, image: UIImage, date: Date,
                      locale: Locale) -> UIImage? {
        // 离屏渲染不会继承 App 环境，显式注入所选 locale，使日期随界面语言。
        let card = PaperFrameView(style: style, image: image, date: date, width: 360)
            .environment(\.locale, locale)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3   // ~1080px 宽
        return renderer.uiImage
    }
}

// MARK: - 系统分享面板

/// 包一个可识别的图片，配合 .sheet(item:) 弹出系统分享面板。
struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
