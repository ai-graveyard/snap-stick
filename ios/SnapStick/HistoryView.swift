//
//  HistoryView.swift
//  SnapStick
//
//  历史记录：从底部弹出的抽屉式面板（与相纸切换一致），上滑可放大。
//  按日期分组（今天 / 昨天 / 具体日期），每条可回看、隐藏/展示、删除；
//  顶部可调「显示贴纸数量」，底部可清空（需输入「我确认」）。
//

import SwiftUI

struct HistoryView: View {
    let photos: [PhotoRecord]
    @Binding var visibleCount: Int
    let hiddenIds: Set<UUID>
    /// 在详情抽屉里切换相纸（持久化由上层负责）
    let onPickPaper: (PhotoRecord, PaperStyle) -> Void
    /// 在详情抽屉里修改一级分类（Vision 原始标签保持不变）
    let onPickCategory: (PhotoRecord, StickerCategory) -> Void
    let onDownload: (PhotoRecord) -> Void
    let onDelete: (PhotoRecord) -> Void
    let onToggleVisibility: (PhotoRecord) -> Void
    let onClear: () -> Void
    /// 关闭抽屉
    @Environment(\.dismiss) private var dismiss
    /// 当前界面 locale（由根视图按所选语言注入），驱动日期分组与确认词本地化。
    @Environment(\.locale) private var locale

    @State private var deleteTarget: PhotoRecord?
    /// 点条目打开的详情抽屉目标（在贴纸册内部弹出，关闭后回到贴纸册）
    @State private var detailTarget: PhotoRecord?
    @State private var clearOpen = false
    @State private var clearText = ""
    /// 当前类别筛选：全部 / 某个一级分类 / 未分类
    @State private var filter: CategoryFilter = .all

    /// 类别筛选项
    enum CategoryFilter: Equatable { case all, category(String), uncategorized }

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
        // 点条目在贴纸册之上弹出详情抽屉（关闭后回到贴纸册，不跳回拍照界面）。
        // 左右滑动范围 = 当前筛选后的列表（与时间线同序，最新在前）。
        .sheet(item: $detailTarget) { p in
            StickerDetailView(photos: filtered.sorted { $0.timestamp > $1.timestamp },
                              selectedID: p.id,
                              onPickPaper: onPickPaper,
                              onPickCategory: onPickCategory,
                              onDownload: onDownload,
                              onDelete: onDelete)
                .environment(\.locale, locale)
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            navBar
            Divider()

            // 显示数量
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("显示贴纸").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(visibleCount) / 20").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                }
                Slider(value: Binding(get: { Double(visibleCount) },
                                      set: { visibleCount = Int($0) }), in: 1...20, step: 1)
            }
            .padding()
            Divider()

            // 类别筛选条（仅当有已识别类别的贴纸时出现）
            categoryBar

            // 时间线
            ScrollView {
                if photos.isEmpty {
                    Text("还没有贴纸\n按下快门拍一张吧")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(grouped, id: \.label) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.label)
                                    .font(.system(size: 11, weight: .semibold)).tracking(1)
                                    .foregroundColor(.secondary)
                                ForEach(group.photos) { photo in row(photo) }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            if !photos.isEmpty {
                Divider()
                Button { clearOpen = true } label: {
                    Text("清空所有记录").font(.system(size: 13)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
        }
    }

    /// 顶栏：标题 + 数量 + 关闭按钮（抽屉式）
    private var navBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("贴纸册").font(.system(size: 18, weight: .bold)).tracking(1)
                Text("共 \(filtered.count) 张").font(.system(size: 12)).foregroundColor(.secondary)
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
        let hidden = hiddenIds.contains(photo.id)
        return HStack(spacing: 12) {
            Button { detailTarget = photo } label: {
                HStack(spacing: 12) {
                    Image(uiImage: photo.displayImage)
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 56)
                        .padding(photo.cutout != nil ? 4 : 0)
                        .background(Palette.chip)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(hidden ? 0.35 : 1)
                        .grayscale(hidden ? 1 : 0)
                    VStack(alignment: .leading, spacing: 4) {
                        // 有一级分类就显示用户友好的分类名，否则回落到通用「贴纸快照」
                        if let category = photo.primaryCategory {
                            Text(category.titleKey)
                                .font(.system(size: 14, weight: .medium))
                        } else {
                            Text("贴纸快照").font(.system(size: 14, weight: .medium))
                        }
                        Text(Self.timeString(photo.timestamp, locale: locale))
                            .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button { onToggleVisibility(photo) } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 14)).foregroundColor(hidden ? Color(white: 0.7) : .secondary)
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.chip))
            }.buttonStyle(.plain)

            Button { onDownload(photo) } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.chip))
            }.buttonStyle(.plain)
            .accessibilityLabel(Text("保存"))

            Button { deleteTarget = photo } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14)).foregroundColor(Color(white: 0.7))
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.chip))
            }.buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card).shadow(color: .black.opacity(0.05), radius: 2))
    }

    @ViewBuilder private var dialogs: some View {
        if deleteTarget != nil {
            ConfirmOverlay(title: "删除这张贴纸？",
                           message: "会移到回收站，30 天内可恢复。",
                           confirmLabel: "删除", danger: true,
                           canConfirm: true,
                           onCancel: { deleteTarget = nil },
                           onConfirm: { if let t = deleteTarget { onDelete(t) }; deleteTarget = nil })
        }
        if clearOpen {
            ConfirmOverlay(title: "清空所有记录？",
                           message: "全部贴纸会移到回收站，30 天内可恢复。",
                           confirmLabel: "清空", danger: true,
                           canConfirm: true,
                           onCancel: { clearOpen = false; clearText = "" },
                           onConfirm: { onClear(); clearOpen = false; clearText = "" })
        }
    }

    // MARK: - 类别筛选

    /// 出现过的一级类别，按最近一次出现排序
    private var categories: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for p in photos.sorted(by: { $0.timestamp > $1.timestamp }) {
            if let c = p.primaryCategoryID, !seen.contains(c) { seen.insert(c); order.append(c) }
        }
        return order
    }

    private var hasUncategorized: Bool { photos.contains { $0.primaryCategoryID == nil } }

    /// 按当前筛选过滤后的贴纸
    private var filtered: [PhotoRecord] {
        switch filter {
        case .all: return photos
        case .category(let c):
            let hit = photos.filter { $0.primaryCategoryID == c }
            return hit.isEmpty ? photos : hit   // 该类已被删空时回落到全部
        case .uncategorized:
            return hasUncategorized ? photos.filter { $0.primaryCategoryID == nil } : photos
        }
    }

    /// 类别筛选条：全部 + 各类别 +（有未识别贴纸时）未分类。无任何类别时整条隐藏。
    @ViewBuilder private var categoryBar: some View {
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(.all, Text("全部"))
                    ForEach(categories, id: \.self) { c in
                        chip(.category(c), categoryChipText(c))
                    }
                    if hasUncategorized { chip(.uncategorized, Text("未分类")) }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            Divider()
        }
    }

    private func chip(_ value: CategoryFilter, _ text: Text) -> some View {
        let selected = filter == value
        return Button { filter = value } label: {
            text
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? .white : Palette.label.opacity(0.75))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Palette.klein : Palette.chip))
        }
        .buttonStyle(.plain)
    }

    private func categoryChipText(_ id: String) -> Text {
        if let category = StickerCategory.fromID(id) {
            return Text(category.titleKey)
        }
        return Text("其他")
    }

    // MARK: - 分组与格式

    private struct Group { let label: String; let photos: [PhotoRecord] }

    private var grouped: [Group] {
        let sorted = filtered.sorted { $0.timestamp > $1.timestamp }
        var result: [Group] = []
        for p in sorted {
            let label = Self.dateGroup(p.timestamp, locale: locale)
            if result.last?.label == label {
                result[result.count - 1] = Group(label: label, photos: result.last!.photos + [p])
            } else {
                result.append(Group(label: label, photos: [p]))
            }
        }
        return result
    }

    static func dateGroup(_ ts: Date, locale: Locale) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(ts) { return localizedString("今天", locale: locale) }
        if cal.isDateInYesterday(ts) { return localizedString("昨天", locale: locale) }
        let f = DateFormatter(); f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMMd")
        return f.string(from: ts)
    }

    static func timeString(_ ts: Date, locale: Locale) -> String {
        let f = DateFormatter(); f.locale = locale; f.dateFormat = "HH:mm"
        return f.string(from: ts)
    }
}

/// 通用确认弹窗（可选文本输入门槛）
struct ConfirmOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    let danger: Bool
    let canConfirm: Bool
    var input: Binding<String>? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(message).font(.system(size: 14)).foregroundColor(.secondary)
                if let input {
                    TextField("我确认", text: input)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                HStack {
                    Spacer()
                    Button("取消", action: onCancel).foregroundColor(.secondary)
                    Button(confirmLabel, action: onConfirm)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(canConfirm ? (danger ? Color.red : Color(white: 0.18)) : Color(white: 0.8)))
                        .disabled(!canConfirm)
                }
            }
            .padding(18)
            .frame(maxWidth: 300)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
            .foregroundColor(Palette.label)
            .padding(40)
        }
    }

}
