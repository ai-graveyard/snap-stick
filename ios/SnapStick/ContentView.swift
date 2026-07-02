//
//  ContentView.swift
//  SnapStick
//
//  主页面：状态机（idle → ejecting → developing → done）、相机、拍照、
//  Vision 抠图编排，串起拍立得相机、物理沙盒、历史抽屉、设置。
//

import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject private var store: PhotoStore
    @EnvironmentObject private var settings: AppSettings
    /// 当前界面 locale（由根视图按所选语言注入），供日期格式化与分享图渲染使用。
    @Environment(\.locale) private var locale
    /// 前后台状态：进入后台时停掉相机/陀螺仪/物理循环，避免空转发热。
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var camera = CameraController()
    @StateObject private var motion = MotionManager()
    @StateObject private var sandbox = SandboxEngine()
    @StateObject private var quota = DailyQuota()
    @State private var sound = SoundPlayer()

    private let ejectDuration = 2.0
    /// 显影揭晓（模糊→清晰）动画时长；摇晃加速后从此刻起 ≈1s 出片
    private let developReveal = 1.0
    /// 不摇晃时的显影等待 = 用户设定的总显影时间 − 揭晓动画时长（下限 0）。
    /// 总时间在 设置 里可调（3~8s，默认 5s）；摇一摇仍可跳过等待立即揭晓。
    private var developWait: Double { max(0, settings.developTime - developReveal) }

    @State private var phase: StudioPhase = .idle
    @State private var photo: PhotoRecord?
    @State private var animateReveal = true
    @State private var ejectDone = false
    @State private var cutoutReady = false
    /// 显影揭晓已触发（开始模糊→清晰动画）
    @State private var reveal = false
    /// 本次显影是否已被摇晃加速（去重，避免重复触发）
    @State private var developShaken = false
    /// 显影等待计时任务（摇晃时取消，立即揭晓）
    @State private var developTask: Task<Void, Never>?
    @State private var freshId: UUID?
    @State private var pendingPhoto: PhotoRecord?
    /// 撕纸连拍：上一张成品正在脱离（落入沙盒）的过渡，期间锁快门并播放退场动画
    @State private var tearing = false

    @State private var hiddenIds: Set<UUID> = []
    @State private var visibleCount = 6
    /// 相机机身在屏幕中的全局位置（由出片视图上报）：用作沙盒贴纸的地板，
    /// 让悬浮贴纸只在机身上方的空白区域里活动。
    @State private var cameraRect: CGRect = .zero

    /// 底栏三个 Tab：左日历、中主页（拍照）、右用户中心
    /// （命名为 Screen 以避开 SwiftUI 的 Tab 类型）
    enum Screen: Hashable { case calendar, home, profile }
    @State private var tab: Screen = .home

    @State private var sidebarOpen = false
    @State private var trashOpen = false
    @State private var settingsOpen = false
    @State private var errorMsg: LocalizedStringKey?
    /// 贴纸详情抽屉的目标（从日历日视图 / 主页沙盒贴纸 / 出片卡编辑键点开；贴纸册在其内部自行弹出）
    @State private var detailPhoto: PhotoRecord?
    /// 详情抽屉内可左右滑动切换的这组贴纸（范围跟随打开入口；起点是 detailPhoto）
    @State private var detailList: [PhotoRecord] = []
    @State private var toast: LocalizedStringKey?
    /// 出片卡上「删除」按钮的确认弹窗（删除当前展示的作品）
    @State private var deleteStudioConfirm = false

    // 相纸：当前选中样式、分享
    @State private var selectedPaperID = PaperCatalog.defaultID
    @State private var shareItem: ShareImage?
    @State private var paperSheetOpen = false

    private static let lastStyleKey = "paper.lastStyle"

    private var visiblePhotos: [PhotoRecord] {
        store.photos.filter { !hiddenIds.contains($0.id) }.prefix(visibleCount).map { $0 }
    }
    private var busy: Bool { phase == .ejecting || phase == .developing }

    /// 当前选中的相纸样式
    private var paperStyle: PaperStyle { PaperCatalog.style(for: selectedPaperID) }

    /// 相机是否应处于取景运行状态：仅当停在主页且无任何弹框/整页遮挡时。
    /// 切到日历/设置 Tab，或被分享、相纸、历史、原图预览等覆盖时，
    /// 关闭会话以免相机长时间空转发热、拖累性能。
    private var cameraActive: Bool {
        scenePhase == .active
            && tab == .home
            && !sidebarOpen && !trashOpen && !settingsOpen
            && !paperSheetOpen && shareItem == nil && detailPhoto == nil
    }

    /// 物理沙盒是否应运行：仅当停在主页且在前台。切到日历/设置 Tab 或进后台时
    /// 停掉 CADisplayLink，避免在看不见沙盒时还满帧空转。
    private var sandboxActive: Bool { scenePhase == .active && tab == .home }

    /// 贴纸 id → 展示图的查表，传给沙盒做 O(1) 取图（替代每帧逐贴纸的线性 first 查找）。
    /// 仅在本视图重算时重建（photos 变化等），不在每帧物理循环里。
    private var stickerImages: [UUID: UIImage] {
        Dictionary(store.photos.map { ($0.id, $0.displayImage) }, uniquingKeysWith: { a, _ in a })
    }

    /// 陀螺仪是否应运行：前台且不在设置 Tab（主页驱动沙盒+甩照片，日历驱动「撒一把」游乐场）。
    /// 设置 Tab 与后台都用不到，停掉以省电。
    private var motionActive: Bool { scenePhase == .active && tab != .profile }

    var body: some View {
        ZStack {
            // iOS 26 原生 Liquid Glass 悬浮底栏：用 Tab{} 写法即自动获得玻璃栏与滑动 morph。
            // 相机会话由 ContentView 持有，切 Tab 不会丢失会话。
            TabView(selection: $tab) {
                Tab(value: Screen.calendar) {
                    calendarLayer
                } label: {
                    Image(systemName: "calendar").accessibilityLabel(Text("日历"))
                }
                Tab(value: Screen.home) {
                    studioLayer
                } label: {
                    Image(systemName: "camera.fill").accessibilityLabel(Text("拍照"))
                }
                Tab(value: Screen.profile) {
                    profileLayer
                } label: {
                    Image(systemName: "gearshape.fill").accessibilityLabel(Text("设置"))
                }
            }
            // 底栏选中项统一用克莱因蓝
            .tint(Palette.klein)

            cameraPermissionOverlay
            deleteStudioOverlay
        }
        // 历史记录：从底部弹出的抽屉式面板（与相纸切换一致），上滑可放大
        .sheet(isPresented: $sidebarOpen) {
            HistoryView(photos: store.photos, visibleCount: $visibleCount,
                        hiddenIds: hiddenIds,
                        onPickPaper: handleDetailPickPaper,
                        onPickCategory: handleDetailPickCategory,
                        onDownload: handleDownloadHistory,
                        onDelete: handleDeleteHistory,
                        onToggleVisibility: toggleVisibility,
                        onClear: handleClearHistory)
                .environment(\.locale, locale)
        }
        // 贴纸详情：从日历日视图 / 主页沙盒贴纸 / 出片卡编辑键点开（贴纸册在其内部自行弹出，避免 sheet 叠 sheet）。
        // detailList 是可左右滑动的这组（范围跟随入口）；保险起见若不含起点则退化为单张。
        .sheet(item: $detailPhoto) { p in
            let list = detailList.contains(where: { $0.id == p.id }) ? detailList : [p]
            StickerDetailView(photos: list,
                              selectedID: p.id,
                              onPickPaper: handleDetailPickPaper,
                              onPickCategory: handleDetailPickCategory,
                              onDownload: handleDownloadHistory,
                              onDelete: handleDeleteHistory)
                .environment(\.locale, locale)
        }
        // 回收站：从底部弹出的抽屉式面板（与历史记录一致），上滑可放大
        .sheet(isPresented: $trashOpen) {
            RecycleBinView(photos: store.trashed,
                           onRestore: handleRestore,
                           onPurge: handlePurge,
                           onEmpty: handleEmptyTrash)
                .environment(\.locale, locale)
        }
        .sheet(isPresented: $settingsOpen) { SettingsView() }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
        .sheet(isPresented: $paperSheetOpen) {
            PaperPickerSheet(selectedID: selectedPaperID,
                             sampleImage: photo?.displayImage ?? UIImage(),
                             onPick: handlePickPaper)
        }
        .onAppear(perform: setup)
        // 离开主页或被弹框/整页遮挡时暂停相机，回到主页且无遮挡时恢复。
        .onChange(of: cameraActive) { _, active in
            if active { camera.resume() } else { camera.stop() }
        }
        // 离开主页或进后台时停掉物理循环；回到主页且在前台时恢复。
        .onChange(of: sandboxActive) { _, active in
            if active { sandbox.start() } else { sandbox.stop() }
        }
        // 设置 Tab 或后台用不到陀螺仪，停掉省电；回到主页/日历且在前台时恢复。
        .onChange(of: motionActive) { _, active in
            if active { motion.start() } else { motion.stop() }
        }
        // 相机机身位置变化时，把沙盒地板抬到机身顶边——贴纸只在机身上方的空白里落定/滑动。
        .onChange(of: cameraRect) { _, r in
            sandbox.floorOverride = r == .zero ? nil : r.minY
            sandbox.wake()
        }
        // 跨天回到前台时，把当日计数清零（计数器复位到 99）。
        .onChange(of: scenePhase) { _, p in if p == .active { quota.rolloverIfNeeded() } }
        .onChange(of: ejectDone) { _, _ in maybeDevelop() }
        .onChange(of: cutoutReady) { _, _ in maybeDevelop() }
        .onChange(of: settings.speed) { _, v in sandbox.speed = CGFloat(v); sandbox.wake() }
        .onChange(of: settings.sensitivity) { _, v in sandbox.sensitivity = CGFloat(v); sandbox.wake() }
        .onChange(of: visiblePhotos.map(\.id)) { _, ids in sandbox.sync(photoIDs: ids, freshId: freshId) }
    }

    // MARK: - 主页（拍照）层

    private var studioLayer: some View {
        ZStack {
            // 页面背景：白天纯白，黑夜近黑
            Palette.surface
                .ignoresSafeArea()

            GeometryReader { geo in
                PolaroidStudioView(
                    camW: min(geo.size.width * 0.76, 300),
                    phase: phase, photo: photo,
                    cameraReady: camera.isReady,
                    quotaRemaining: quota.remaining,
                    tearing: tearing,
                    animateReveal: animateReveal,
                    reveal: reveal,
                    ejectDuration: ejectDuration, developDuration: developReveal,
                    session: AVCaptureSessionRef(session: camera.session),
                    onBeforeShutter: { motion.start() },
                    onShutter: handleShutter,
                    onFlipCamera: {
                        camera.flipCamera { front in
                            showToast(front ? "已切换前置镜头" : "已切换后置镜头")
                        }
                    },
                    onRetake: handleRetake,
                    onDelete: { if photo != nil { deleteStudioConfirm = true } },
                    onDownload: handleDownload,
                    onShare: handleShare,
                    onWindowFrame: { sandbox.spawnRect = $0 },
                    onCameraFrame: { cameraRect = $0 },
                    onOpenPaper: { paperSheetOpen = true },
                    onEdit: {
                        if let photo {
                            // 出片卡入口：可滑进全部历史，以刚拍这张为起点往回滑（按时间倒序）
                            detailList = store.photos.sorted { $0.timestamp > $1.timestamp }
                            detailPhoto = photo
                        }
                    }
                )
            }

            // 悬浮贴纸：仅在「无相纸」的待机相位（.idle）显示，且只在机身上方的空白里活动。
            // 一旦相纸吐出（.ejecting/.developing/.done），整层淡出并停用命中，完全隐藏。
            StickerSandboxView(engine: sandbox, frameStore: sandbox.frameStore,
                               images: stickerImages, onActivate: handleActivateSticker)
                .opacity(phase == .idle ? 1 : 0)
                .allowsHitTesting(phase == .idle)
                .animation(.easeInOut(duration: 0.3), value: phase == .idle)

            header

            if let errorMsg {
                VStack {
                    Text(errorMsg)
                        .font(.system(size: 13)).foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: 340)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.92)))
                        .padding(.horizontal, 16)
                        .padding(.top, 90)
                        .onTapGesture { self.errorMsg = nil }
                    Spacer()
                }
            }

            if let toast {
                VStack { Spacer()
                    Text(toast).font(.system(size: 14)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.8)))
                        .padding(.bottom, 60)
                }
            }

        }
    }

    // MARK: - 日历层 / 用户中心层

    private var calendarLayer: some View {
        CalendarView(photos: store.photos,
                     onSelect: { p, dayItems in detailList = dayItems; detailPhoto = p },
                     isOpen: Binding(get: { tab == .calendar },
                                     set: { if !$0 { tab = .home } }),
                     gravity: { [motion] in motion.gravity })
    }

    private var profileLayer: some View {
        UserCenterView(photos: store.photos,
                       trashedCount: store.trashed.count,
                       onOpenHistory: { sidebarOpen = true },
                       onOpenTrash: { trashOpen = true },
                       onOpenSettings: { settingsOpen = true })
    }

    // MARK: - 顶栏

    private var header: some View {
        VStack {
            HStack {
                Button { sidebarOpen = true } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(Palette.label.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Palette.card.opacity(0.85)))
                        .shadow(color: Palette.ink.opacity(0.12), radius: 4, y: 2)
                }
                Spacer()
                Text("拍 立 贴").font(.system(size: 16, weight: .bold)).tracking(6)
                    .foregroundColor(Palette.klein)
                Spacer()
                // 相纸切换键已移入出片卡的照片窗口右上角（随卡片出现/消失）；
                // 此处放交互设置快捷键，与左上角相册按钮等宽对称，保证标题居中。
                Button { settingsOpen = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(Palette.label.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Palette.card.opacity(0.85)))
                        .shadow(color: Palette.ink.opacity(0.12), radius: 4, y: 2)
                }
                .accessibilityLabel(Text("交互设置"))
            }
            .padding(.horizontal, 16).padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - 摄像头权限提示

    @ViewBuilder private var cameraPermissionOverlay: some View {
        if camera.error != nil && !camera.isReady {
            ZStack {
                Color.black.opacity(0.75).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.system(size: 30))
                        .foregroundColor(Color(white: 0.4))
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Palette.chip))
                    Text("需要摄像头权限").font(.system(size: 16, weight: .bold))
                    Text(cameraErrorMessage).font(.system(size: 14))
                        .foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button {
                        if camera.error == .denied,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        } else { camera.start() }
                    } label: {
                        Text(camera.error == .denied ? "前往系统设置" : "允许使用摄像头")
                            .font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Color(white: 0.18)))
                    }
                }
                .padding(24).frame(maxWidth: 300)
                .background(RoundedRectangle(cornerRadius: 24).fill(Palette.card))
                .foregroundColor(Palette.label)
            }
        }
    }

    private var cameraErrorMessage: LocalizedStringKey {
        switch camera.error {
        case .denied: return "摄像头权限被拒绝。请在系统设置里允许 SnapStick 访问摄像头，然后重试。"
        case .notFound: return "没有找到可用的摄像头设备。"
        default: return "无法访问摄像头，请检查设置后重试。"
        }
    }

    /// 出片卡「删除」确认弹窗：与历史记录一致，软删除到回收站。
    @ViewBuilder private var deleteStudioOverlay: some View {
        if deleteStudioConfirm {
            ConfirmOverlay(title: "删除这张贴纸？",
                           message: "会移到回收站，30 天内可恢复。",
                           confirmLabel: "删除", danger: true,
                           canConfirm: true,
                           onCancel: { deleteStudioConfirm = false },
                           onConfirm: {
                               if let p = photo { handleDeleteHistory(p) }
                               deleteStudioConfirm = false
                           })
        }
    }

    // MARK: - 生命周期

    private func setup() {
        if let saved = UserDefaults.standard.string(forKey: Self.lastStyleKey) {
            selectedPaperID = saved
        }
        camera.start()
        motion.onShake = handleShake
        if motionActive { motion.start() }
        sandbox.speed = CGFloat(settings.speed)
        sandbox.sensitivity = CGFloat(settings.sensitivity)
        // 首页沙盒透明盖在实时相机上，每帧合成 over 动态视频很贵：和相机预览抢 GPU 正是
        // 「贴纸一多就影响相机」的根因。用 30fps（120 的整数分频，节奏均匀）把合成次数再砍半，
        // 滑动的贴纸肉眼几乎无差。日历游乐场盖不透明背景、合成几乎免费，保持默认 120。
        sandbox.activeFPS = 30
        sandbox.gravityProvider = { [motion] in motion.gravity }
        sandbox.onWallHit = { [sound, settings] in
            if settings.wallHitHaptic { sound.wallHitHaptic() }
        }
        if sandboxActive { sandbox.start() }
        sandbox.sync(photoIDs: visiblePhotos.map(\.id), freshId: nil)
    }

    // MARK: - 状态机

    private func maybeDevelop() {
        guard phase == .ejecting, ejectDone, cutoutReady else { return }
        phase = .developing
        reveal = false
        developShaken = false
        developTask?.cancel()
        // 不摇晃：等 developWait 后自动揭晓显影
        developTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(developWait * 1_000_000_000))
            guard !Task.isCancelled, phase == .developing else { return }
            triggerReveal()
        }
    }

    /// 揭晓显影：开始「模糊→清晰」动画，动画结束后落定为成品。
    /// 由等待计时结束或摇晃手机触发，两条路径共用。
    private func triggerReveal() {
        guard phase == .developing, !reveal else { return }
        reveal = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(developReveal * 1_000_000_000))
            guard phase == .developing else { return }
            finishDevelop()
        }
    }

    /// 摇晃手机：模仿拍立得「甩照片」——跳过剩余等待，立即揭晓（约 1 秒出片）。
    private func handleShake() {
        guard phase == .developing, !developShaken else { return }
        developShaken = true
        developTask?.cancel()
        sound.shutterHaptic()
        triggerReveal()
    }

    private func finishDevelop() {
        phase = .done
        guard let pending = pendingPhoto else { return }
        pendingPhoto = nil
        // 套上当前选中的相纸样式
        var record = pending
        record.paperStyleID = selectedPaperID
        photo = record
        freshId = record.id
        store.add(record)
        sandbox.sync(photoIDs: visiblePhotos.map(\.id), freshId: record.id)
    }

    // MARK: - 拍照

    private func handleShutter() {
        guard !tearing else { return }
        // 每日额度：拍满 99 张后拦截，给出提示（计数器已显示 00）。
        quota.rolloverIfNeeded()
        guard quota.canShoot else {
            showToast("今天已经拍满 99 张啦，明天再来")
            return
        }
        guard let original = camera.captureSquare() else {
            errorMsg = "没抓到画面，请重试"; return
        }
        errorMsg = nil
        if settings.shutterSoundEnabled { sound.playShutter() }
        sound.shutterHaptic()

        if phase == .done {
            // 撕纸连拍：让上一张成品落入沙盒淡出，过渡后原地接着出新纸
            tearing = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                tearing = false
                beginShot(original)
            }
        } else {
            beginShot(original)
        }
    }

    /// 开拍：出纸 + 并行抠图，沿用「双就绪」barrier 推进显影
    private func beginShot(_ original: UIImage) {
        // 消耗一张当日额度（计数器随之 99 → 00 递减）。
        quota.record()
        let temp = PhotoRecord(original: original, result: original)
        photo = temp
        animateReveal = true
        ejectDone = false
        cutoutReady = false
        reveal = false
        developShaken = false
        developTask?.cancel()
        freshId = nil
        pendingPhoto = nil
        phase = .ejecting
        if settings.motorSoundEnabled { sound.playMotor(seconds: ejectDuration) }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ejectDuration * 1_000_000_000))
            ejectDone = true
        }

        Task { @MainActor in
            if let cutout = await VisionCutout.cutout(original) {
                // 抠到主体后再识别它的类别（一级分类 + Vision 原始标签），随作品一起保存。
                // 分类为亚秒级，且出纸计时（≈2s）通常仍占主导，不会拖慢显影。
                let classification = await SubjectClassifier.classify(cutout)
                let final = PhotoRecord(id: temp.id, timestamp: temp.timestamp,
                                        original: original, result: original, cutout: cutout,
                                        primaryCategoryID: classification?.primaryCategory.id,
                                        rawVisionLabel: classification?.rawVisionLabel,
                                        rawVisionConfidence: classification?.rawVisionConfidence,
                                        visionCandidates: classification?.candidates ?? [],
                                        categorySource: classification == nil ? nil : .vision)
                photo = final
                pendingPhoto = final
            } else {
                errorMsg = "没识别到主体，已保留原图"
                let classification = await SubjectClassifier.classify(original)
                let final = PhotoRecord(id: temp.id, timestamp: temp.timestamp,
                                        original: original, result: original,
                                        primaryCategoryID: classification?.primaryCategory.id,
                                        rawVisionLabel: classification?.rawVisionLabel,
                                        rawVisionConfidence: classification?.rawVisionConfidence,
                                        visionCandidates: classification?.candidates ?? [],
                                        categorySource: classification == nil ? nil : .vision)
                photo = final
                pendingPhoto = final
            }
            cutoutReady = true
        }
    }

    private func handleRetake() {
        phase = .idle
        photo = nil
        ejectDone = false
        cutoutReady = false
        reveal = false
        developShaken = false
        developTask?.cancel()
        pendingPhoto = nil
        errorMsg = nil
    }

    /// 生成导出图：选了相纸→套相纸的完整卡片（边框 + 衬纸 + 日期）；
    /// 「无相纸」→直接用透明背景的模切贴纸 PNG（无边框 / 日期）。
    private func exportImage(_ photo: PhotoRecord, style: PaperStyle) -> UIImage? {
        if style.isBare { return photo.displayImage }
        return PaperRenderer.image(style: style, image: photo.displayImage,
                                   date: photo.timestamp, locale: locale)
    }

    private func handleDownload() {
        guard let photo else { return }
        guard let img = exportImage(photo, style: paperStyle) else {
            errorMsg = "生成图片失败，请重试"; return
        }
        saveToAlbum(img)
    }

    /// 在历史记录页保存某张贴纸到相册（按该作品自身的相纸样式导出）。
    private func handleDownloadHistory(_ photo: PhotoRecord) {
        guard let img = exportImage(photo, style: photo.paperStyle) else {
            errorMsg = "生成图片失败，请重试"; return
        }
        saveToAlbum(img)
    }

    /// 申请相册权限并保存图片，统一错误/成功提示。
    private func saveToAlbum(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                guard status == .authorized || status == .limited else {
                    errorMsg = "无法保存：相册权限被拒绝"; return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                showToast("已保存到相册")
            }
        }
    }

    // MARK: - 相纸 / 分享

    /// 切换相纸样式（全部相纸均可直接选用）。
    private func handlePickPaper(_ style: PaperStyle) {
        selectedPaperID = style.id
        UserDefaults.standard.set(style.id, forKey: Self.lastStyleKey)
        if let p = photo {
            photo?.paperStyleID = style.id
            store.setPaperStyle(p.id, styleID: style.id)
        }
    }

    /// 按当前相纸渲染导出图，走系统分享面板（无相纸时分享透明贴纸 PNG）。
    private func handleShare() {
        guard let photo else { return }
        if let img = exportImage(photo, style: paperStyle) {
            shareItem = ShareImage(image: img)
        } else {
            errorMsg = "生成分享图失败，请重试"
        }
    }

    // MARK: - 历史

    /// 双击沙盒里的贴纸：打开它的详情抽屉（出纸/显影过程中忽略，避免打断动画）。
    private func handleActivateSticker(_ id: UUID) {
        guard !busy, let p = store.photos.first(where: { $0.id == id }) else { return }
        // 沙盒入口：可左右滑动散落在桌面上可见的那组
        detailList = visiblePhotos
        detailPhoto = p
    }

    /// 在详情抽屉里切换某张作品的相纸：持久化到该记录；若正好是出片卡上的当前作品，同步更新。
    private func handleDetailPickPaper(_ p: PhotoRecord, _ style: PaperStyle) {
        store.setPaperStyle(p.id, styleID: style.id)
        if photo?.id == p.id {
            photo?.paperStyleID = style.id
            selectedPaperID = style.id
        }
    }

    /// 在详情抽屉里修改一级分类：只改用户可见主标签，不覆盖 Vision 原始识别标签。
    private func handleDetailPickCategory(_ p: PhotoRecord, _ category: StickerCategory) {
        store.setPrimaryCategory(p.id, categoryID: category.id)
        if photo?.id == p.id {
            photo?.primaryCategoryID = category.id
            photo?.categorySource = .user
        }
        if detailPhoto?.id == p.id {
            detailPhoto?.primaryCategoryID = category.id
            detailPhoto?.categorySource = .user
        }
    }

    private func handleDeleteHistory(_ p: PhotoRecord) {
        store.delete(p.id)
        hiddenIds.remove(p.id)
        if photo?.id == p.id { handleRetake() }
        if detailPhoto?.id == p.id { detailPhoto = nil }
        sandbox.sync(photoIDs: visiblePhotos.map(\.id), freshId: nil)
    }

    private func toggleVisibility(_ p: PhotoRecord) {
        if hiddenIds.contains(p.id) { hiddenIds.remove(p.id) } else { hiddenIds.insert(p.id) }
        sandbox.sync(photoIDs: visiblePhotos.map(\.id), freshId: nil)
    }

    private func handleClearHistory() {
        store.trashAll()
        hiddenIds = []
        detailPhoto = nil
        handleRetake()
        sandbox.sync(photoIDs: [], freshId: nil)
    }

    // MARK: - 回收站

    private func handleRestore(_ p: PhotoRecord) {
        store.restore(p.id)
        sandbox.sync(photoIDs: visiblePhotos.map(\.id), freshId: nil)
    }

    private func handlePurge(_ p: PhotoRecord) {
        store.purge(p.id)
    }

    private func handleEmptyTrash() {
        store.emptyTrash()
    }

    private func showToast(_ msg: LocalizedStringKey) {
        toast = msg
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == msg { toast = nil }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PhotoStore())
        .environmentObject(AppSettings())
}
