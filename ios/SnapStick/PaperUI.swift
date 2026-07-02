//
//  PaperUI.swift
//  SnapStick
//
//  相纸相关的交互 UI：结果页底部相纸选择条。全部相纸免费、随时可切换。
//

import SwiftUI

// MARK: - 相纸选择面板（底部弹层）

/// 从底部弹出的相纸选择面板。全部相纸均可直接选用，选中即套用并关闭。
struct PaperPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let selectedID: String
    /// 用于缩略图预览的贴纸图（当前作品的 displayImage）
    let sampleImage: UIImage
    let onPick: (PaperStyle) -> Void

    private let columns = [GridItem(.adaptive(minimum: 86), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.8)).frame(width: 38, height: 5).padding(.top, 10)

            HStack {
                Text("选择相纸").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22)).foregroundColor(Color(white: 0.8))
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(PaperCatalog.all) { style in
                        PaperThumb(style: style, sampleImage: sampleImage,
                                   selected: style.id == selectedID) {
                            onPick(style)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
        .background(Palette.card)
        .foregroundColor(Palette.label)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - 相纸缩略图（选纸网格 / 详情抽屉横向条复用）

/// 单个相纸缩略图：成品卡预览 + 名称，选中态描克莱因蓝边。点选回调由调用方处理。
struct PaperThumb: View {
    let style: PaperStyle
    /// 缩略图预览用的贴纸图（当前作品的 displayImage）
    let sampleImage: UIImage
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                PaperFrameView(style: style, image: sampleImage, date: Date(), width: 84)
                    .frame(width: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Palette.klein, lineWidth: selected ? 3 : 0)
                    )
                Text(style.displayName)
                    .font(.system(size: 11, weight: selected ? .bold : .regular))
                    .foregroundColor(selected ? Palette.klein : Palette.label.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
