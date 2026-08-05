//
//  StickerDetailView.swift
//  SnapStick
//
//  贴纸详情抽屉：从日历日视图 / 贴纸册 / 主页沙盒贴纸 / 出片卡编辑键点开时，集中展示与管理。
//  以 sheet（可下拉、带 detent）呈现；左右滑动在传入的这组贴纸间快速切换——
//  「这组」的范围跟随打开入口（贴纸册=当前筛选列表、日历=当天、沙盒=散落可见、出片卡=全部历史）。
//  顶部标题/关闭与底部「保存 / 分享 / 删除」固定，中间分页区随手势左右翻；
//  点图或「看原图」在「贴图 / 原图」间就地切换，旁边一枚旋转键每点一次顺时针 90°，
//  下方可换相纸、改分类、看识别信息。
//
//  半屏（medium）档下预览图会自动收窄，让下面的相纸条露出一截并被渐隐切断——
//  「内容没到底」这件事靠看得见的截断来说，不指望用户猜；再加一枚可点的上拉胶囊兜底。
//

import SwiftUI

struct StickerDetailView: View {
    /// 可左右滑动切换的这组贴纸（有序；范围由打开入口决定）
    let photos: [PhotoRecord]
    /// 初始展示的那张
    let selectedID: UUID
    /// 切换相纸（即时更新展示，持久化由上层负责）
    let onPickPaper: (PhotoRecord, PaperStyle) -> Void
    /// 修改一级分类（Vision 原始标签保持不变）
    let onPickCategory: (PhotoRecord, StickerCategory) -> Void
    /// 旋转到指定角度（顺时针 0 / 90 / 180 / 270）；持久化由上层负责
    let onRotate: (PhotoRecord, Int) -> Void
    /// 保存到相册（按当前相纸导出；toast 由上层提示）
    let onDownload: (PhotoRecord) -> Void
    /// 删除（软删除到回收站）；删除后本抽屉自动关闭
    let onDelete: (PhotoRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// 当前翻到的那张 id（左右滑动改变）
    @State private var selection: UUID
    /// 各张的可编辑副本（相纸 / 分类即时改），按 id 索引；分页内编辑与底部操作共享同一份。
    @State private var records: [UUID: PhotoRecord]
    /// 分享面板目标：在抽屉内部弹出，避免与外层 sheet 冲突
    @State private var shareItem: ShareImage?
    /// 删除确认
    @State private var confirmDelete = false
    /// 当前停在哪一档；半屏档要收窄预览、露出下方面板并挂上拉提示
    @State private var detent: PresentationDetent = .medium
    /// 递增一次让上拉胶囊浮动一轮
    @State private var hintPulse = 0

    /// 是否停在半屏档
    private var isCompact: Bool { detent == .medium }

    init(photos: [PhotoRecord],
         selectedID: UUID,
         onPickPaper: @escaping (PhotoRecord, PaperStyle) -> Void,
         onPickCategory: @escaping (PhotoRecord, StickerCategory) -> Void,
         onRotate: @escaping (PhotoRecord, Int) -> Void,
         onDownload: @escaping (PhotoRecord) -> Void,
         onDelete: @escaping (PhotoRecord) -> Void) {
        self.photos = photos
        self.selectedID = selectedID
        self.onPickPaper = onPickPaper
        self.onPickCategory = onPickCategory
        self.onRotate = onRotate
        self.onDownload = onDownload
        self.onDelete = onDelete
        _selection = State(initialValue: selectedID)
        var dict = [UUID: PhotoRecord]()
        for p in photos { dict[p.id] = p }
        _records = State(initialValue: dict)
    }

    /// 当前翻到这张的可编辑副本（含刚切换的相纸 / 分类）
    private var current: PhotoRecord {
        records[selection] ?? photos.first { $0.id == selection } ?? photos[0]
    }
    private var currentIndex: Int { photos.firstIndex { $0.id == selection } ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(white: 0.8)).frame(width: 38, height: 5).padding(.top, 10)
            header
            // 中间分页区：左右滑动在 photos 间切换（范围跟随入口）。
            TabView(selection: $selection) {
                ForEach(photos) { p in
                    StickerDetailPage(record: binding(for: p),
                                      compact: isCompact,
                                      onPickPaper: onPickPaper,
                                      onPickCategory: onPickCategory,
                                      onRotate: onRotate)
                        .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 常驻但按档位淡入淡出：省掉插拔视图，动画触发时机也好控制
            .overlay(alignment: .bottom) {
                pullUpHint
                    .opacity(isCompact ? 1 : 0)
                    .allowsHitTesting(isCompact)
                    .animation(.easeOut(duration: 0.2), value: isCompact)
            }
            actionsBar
        }
        .background(Palette.card)
        .foregroundColor(Palette.label)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .overlay { if confirmDelete { deleteDialog } }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.image]) }
    }

    /// 某一张的可编辑副本绑定：分页内改相纸 / 分类即写回 records，底部操作随之取到最新。
    private func binding(for p: PhotoRecord) -> Binding<PhotoRecord> {
        Binding(get: { records[p.id] ?? p }, set: { records[p.id] = $0 })
    }

    private var header: some View {
        HStack {
            Text("贴纸详情").font(.system(size: 17, weight: .bold))
            // 多于一张时显示「序号 / 总数」，暗示可左右滑动
            if photos.count > 1 {
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 6)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22)).foregroundColor(Color(white: 0.8))
            }
            .accessibilityLabel(Text("关闭"))
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
    }

    /// 半屏档挂在分页区底部的「下面还有」提示：
    /// 一层渐隐把露头的面板柔化切断（比硬切更像「内容延续下去」而不是「排版到此为止」），
    /// 外加一枚可点的上拉胶囊——出现时轻轻浮两个来回就停，点它直接展开到整屏。
    /// 渐隐层不吃手势，内容照样能直接往上滑。
    private var pullUpHint: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Palette.card.opacity(0), Palette.card],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 46)
                .allowsHitTesting(false)
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { detent = .large }
            } label: {
                KeyframeAnimator(initialValue: 0.0, trigger: hintPulse) { y in
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("上拉编辑").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Palette.klein)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(Palette.chip))
                    .offset(y: y)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0,  duration: 0.30)
                        CubicKeyframe(-5, duration: 0.42)
                        CubicKeyframe(0,  duration: 0.42)
                        CubicKeyframe(-5, duration: 0.42)
                        CubicKeyframe(0,  duration: 0.42)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
        }
        // 打开时浮一次；从整屏收回半屏时再浮一次，其余时候安静待着
        .onAppear { hintPulse += 1 }
        .onChange(of: isCompact) { _, compact in if compact { hintPulse += 1 } }
    }

    /// 固定在底部的操作条，作用于「当前翻到这张」。
    private var actionsBar: some View {
        HStack(spacing: 10) {
            actionButton("保存", "square.and.arrow.down", tint: Palette.label) {
                onDownload(current)
            }
            actionButton("分享", "square.and.arrow.up", tint: Palette.klein) {
                if let img = makeShareImage() { shareItem = ShareImage(image: img) }
            }
            actionButton("删除", "trash", tint: .red) { confirmDelete = true }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
    }

    private func actionButton(_ title: LocalizedStringKey, _ icon: String,
                              tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.chip))
        }
        .buttonStyle(.plain)
    }

    private var deleteDialog: some View {
        ConfirmOverlay(title: "删除这张贴纸？",
                       message: "会移到回收站，30 天内可恢复。",
                       confirmLabel: "删除", danger: true, canConfirm: true,
                       onCancel: { confirmDelete = false },
                       onConfirm: { confirmDelete = false; onDelete(current); dismiss() })
    }

    /// 生成分享图：选了相纸→完整卡片（边框+衬纸+日期）；「无相纸」→透明背景贴纸 PNG。
    /// 与 ContentView.exportImage 保持一致。
    private func makeShareImage() -> UIImage? {
        let style = PaperCatalog.style(for: current.paperStyleID)
        if style.isBare { return current.displayImage }
        return PaperRenderer.image(style: style, image: current.displayImage,
                                   date: current.timestamp, locale: locale)
    }
}

/// 详情抽屉里左右分页的一页：成品卡 + 元信息（含旋转键）+ 相纸条 + 分类。
/// 旋转 / 相纸 / 分类的修改写回绑定的 record（即时刷新展示与底部操作），并回调上层持久化。
private struct StickerDetailPage: View {
    @Binding var record: PhotoRecord
    /// 抽屉停在半屏档：预览图收窄，把下面的相纸条顶进可视区
    let compact: Bool
    let onPickPaper: (PhotoRecord, PaperStyle) -> Void
    let onPickCategory: (PhotoRecord, StickerCategory) -> Void
    let onRotate: (PhotoRecord, Int) -> Void

    @Environment(\.locale) private var locale
    /// 贴图 / 原图就地切换（每页独立）
    @State private var showingOriginal = false
    /// 旋转键的视觉补偿角：点一次预置 −90° 再动画回 0，做出「照片转过去」的观感
    @State private var spin: Double = 0

    /// 半屏档下预览之外要留给「metaRow + 间距 + 相纸条露头」的高度
    private static let compactReserve: CGFloat = 132

    private var style: PaperStyle { PaperCatalog.style(for: record.paperStyleID) }

    var body: some View {
        // 分页区高度随机型和档位变，预览尺寸据此算，才能保证「露出一截」在各屏都成立。
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    preview(side: previewSide(in: geo.size.height))
                    metaRow
                    paperStrip
                    categoryPanel
                }
                .padding(.horizontal, 20).padding(.top, 6)
                .padding(.bottom, compact ? 44 : 16)
            }
        }
    }

    /// 整屏档固定 240；半屏档按剩余空间倒推，并夹在 [90, 240] 之间兜住极端屏高。
    private func previewSide(in height: CGFloat) -> CGFloat {
        guard compact else { return 240 }
        return min(240, max(90, (height - Self.compactReserve) / 1.25))
    }

    /// 主展示区：点图在「贴图（套相纸的成品卡）/ 原图」间切换。
    private func preview(side: CGFloat) -> some View {
        ZStack {
            if showingOriginal {
                Image(uiImage: record.original)
                    .resizable().scaledToFit()
                    .frame(maxWidth: side, maxHeight: side)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                PaperFrameView(style: style, image: record.displayImage,
                               date: record.timestamp, width: side)
            }
        }
        .rotationEffect(.degrees(spin))
        .frame(maxWidth: .infinity)
        .frame(height: side * 1.25)
        // 档位切换时跟着缩放，而不是等手势松开后硬跳一下
        .animation(.easeOut(duration: 0.24), value: side)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showingOriginal.toggle() } }
    }

    /// 切换贴图/原图的按钮 + 旋转键 + 日期 + 一级类别
    private var metaRow: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingOriginal.toggle() }
            } label: {
                Label(showingOriginal ? "看贴图" : "看原图",
                      systemImage: showingOriginal ? "square.stack.3d.up.fill" : "photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.klein)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.chip))
            }
            .buttonStyle(.plain)
            Button(action: handleRotate) {
                Image(systemName: "rotate.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Palette.klein)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("旋转"))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(PolaroidStudioView.dateString(record.timestamp, locale: locale))
                    .font(.system(size: 13, weight: .medium))
                if let category = StickerCategory.fromID(record.primaryCategoryID) {
                    Text(category.titleKey)
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
    }

    /// 旋转键：每点一次顺时针 90°（90 → 180 → 270 → 0 循环）。原图 / 贴纸 / 抠图一起转，
    /// 所以看原图、换相纸、导出分享拿到的都是转过之后的画面；先转本页副本立刻出效果，再回调落库。
    /// 观感沿用出片卡那套：图片瞬间转好的同时把视图反向预置 −90°（两者抵消、画面不跳），
    /// 下一帧再动画回 0；两次赋值必须分处不同 transaction，否则会被合并成「没动」。
    private func handleRotate() {
        let target = PhotoRotation.next(after: record.rotation)
        spin = -90          // 不包在 withAnimation 里 → 立即生效、无过渡
        record = record.rotated(to: target)
        onRotate(record, target)
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.32)) { spin = 0 }
        }
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label("分类", systemImage: "tag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(StickerCategory.allCases) { category in
                        Button {
                            record.primaryCategoryID = category.id
                            onPickCategory(record, category)
                        } label: {
                            Label {
                                Text(category.titleKey)
                            } icon: {
                                Image(systemName: category.symbol)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let category = StickerCategory.fromID(record.primaryCategoryID) {
                            Image(systemName: category.symbol)
                            Text(category.titleKey)
                        } else {
                            Image(systemName: "tag")
                            Text("未分类")
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.klein)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(Palette.chip))
                }
                .buttonStyle(.plain)
            }

            if let raw = record.rawVisionLabel {
                Text(rawLabelText(raw))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if !record.visionCandidates.isEmpty {
                Text(candidateText(record.visionCandidates))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.chip.opacity(0.72)))
    }

    /// 横向相纸切换条：点选即时换纸并持久化（内联，不再叠一层选纸 sheet）
    private var paperStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("相纸").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PaperCatalog.all) { s in
                        PaperThumb(style: s, sampleImage: record.displayImage,
                                   selected: s.id == record.paperStyleID) {
                            record.paperStyleID = s.id
                            showingOriginal = false
                            onPickPaper(record, s)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func rawLabelText(_ label: String) -> String {
        let display = SubjectCategory.displayName(label, locale: locale)
        if let confidence = record.rawVisionConfidence {
            return String(format: localizedString("原始识别：%@ · %.0f%%", locale: locale),
                          display, confidence * 100)
        }
        return String(format: localizedString("原始识别：%@", locale: locale), display)
    }

    private func candidateText(_ candidates: [VisionCandidate]) -> String {
        let names = candidates
            .prefix(5)
            .map { SubjectCategory.displayName($0.label, locale: locale) }
            .joined(separator: " / ")
        return String(format: localizedString("候选：%@", locale: locale), names)
    }
}
