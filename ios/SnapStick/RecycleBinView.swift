//
//  RecycleBinView.swift
//  SnapStick
//
//  回收站：被删除的贴纸暂存在这里，满 30 天由 PhotoStore.load() 自动清理。
//  从底部弹出的抽屉式面板（与历史记录一致），上滑可放大；每条可恢复 / 彻底删除，
//  底部可清空回收站（需输入「我确认」，这是真正不可恢复的操作）。
//

import SwiftUI

struct RecycleBinView: View {
    let photos: [PhotoRecord]
    let onRestore: (PhotoRecord) -> Void
    let onPurge: (PhotoRecord) -> Void
    let onEmpty: () -> Void
    /// 关闭抽屉
    @Environment(\.dismiss) private var dismiss
    /// 当前界面 locale（由根视图按所选语言注入），驱动日期/确认词本地化。
    @Environment(\.locale) private var locale

    @State private var purgeTarget: PhotoRecord?
    @State private var emptyOpen = false
    @State private var emptyText = ""

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.8)).frame(width: 38, height: 5).padding(.top, 10)
            page
        }
        .background(Palette.card)
        .foregroundColor(Palette.label)
        .overlay { dialogs }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var page: some View {
        VStack(spacing: 0) {
            navBar
            Divider()

            ScrollView {
                if photos.isEmpty {
                    Text("回收站是空的\n删除的贴纸会先放在这里")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text("删除的贴纸保留 30 天，到期自动清空")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        ForEach(photos) { photo in row(photo) }
                    }
                    .padding(16)
                }
            }

            if !photos.isEmpty {
                Divider()
                Button { emptyOpen = true } label: {
                    Text("清空回收站").font(.system(size: 13)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
    }

    /// 顶栏：标题 + 数量 + 关闭按钮（抽屉式）
    private var navBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("回收站").font(.system(size: 18, weight: .bold)).tracking(1)
                Text("共 \(photos.count) 张").font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22)).foregroundColor(Color(white: 0.8))
            }
            .accessibilityLabel(Text("关闭"))
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private func row(_ photo: PhotoRecord) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: photo.displayImage)
                .resizable().scaledToFit()
                .frame(width: 56, height: 56)
                .padding(photo.cutout != nil ? 4 : 0)
                .background(Palette.chip)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text("贴纸快照").font(.system(size: 14, weight: .medium))
                Text(remainingText(photo))
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()

            Button { onRestore(photo) } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14)).foregroundColor(Palette.klein)
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.chip))
            }.buttonStyle(.plain)
            .accessibilityLabel(Text("恢复"))

            Button { purgeTarget = photo } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14)).foregroundColor(.red.opacity(0.85))
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.chip))
            }.buttonStyle(.plain)
            .accessibilityLabel(Text("彻底删除"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card).shadow(color: .black.opacity(0.05), radius: 2))
    }

    @ViewBuilder private var dialogs: some View {
        if purgeTarget != nil {
            ConfirmOverlay(title: "彻底删除这张贴纸？",
                           message: "删除后无法恢复。",
                           confirmLabel: "彻底删除", danger: true,
                           canConfirm: true,
                           onCancel: { purgeTarget = nil },
                           onConfirm: { if let t = purgeTarget { onPurge(t) }; purgeTarget = nil })
        }
        if emptyOpen {
            ConfirmOverlay(title: "清空回收站？",
                           message: "这个操作会永久删除回收站里的全部贴纸，无法撤销。输入「我确认」继续。",
                           confirmLabel: "清空", danger: true,
                           canConfirm: emptyText.trimmingCharacters(in: .whitespaces) == localizedString("我确认", locale: locale),
                           input: $emptyText,
                           onCancel: { emptyOpen = false; emptyText = "" },
                           onConfirm: { onEmpty(); emptyOpen = false; emptyText = "" })
        }
    }

    /// 「X 天后自动清空」——剩余天数向上取整；不足一天显示「即将清空」。
    private func remainingText(_ photo: PhotoRecord) -> LocalizedStringKey {
        guard let deletedAt = photo.deletedAt else { return "" }
        let remain = PhotoStore.trashRetention - Date().timeIntervalSince(deletedAt)
        let days = Int(ceil(remain / 86_400))
        if days <= 0 { return "即将自动清空" }
        return "\(days) 天后自动清空"
    }
}
