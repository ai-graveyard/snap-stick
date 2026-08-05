//
//  PolaroidStudioView.swift
//  SnapStick
//
//  原创即时相机（SnapStick）+ 出纸 / 显影动画 + 最终展示。
//  造型为自有品牌设计：双色调机身、单色品牌饰条（不使用任何第三方商标）。
//  按快门：白闪 + 快门声 → 相机整体下移、相纸从顶部出纸口吐出（马达声）→
//  空白药膜 + 扫描线「冲印中」→ AI 返回后从模糊渐变到清晰显影。
//

import SwiftUI
import AVFoundation

struct PolaroidStudioView: View {
    let camW: CGFloat
    let phase: StudioPhase
    let photo: PhotoRecord?
    let cameraReady: Bool
    /// 今日剩余可拍张数（99 → 0），驱动机身左上角的复古滚轮计数器
    let quotaRemaining: Int
    /// 撕纸连拍过渡：上一张成品正在脱离（落入沙盒），期间锁快门并触发向下退场动画
    let tearing: Bool
    let animateReveal: Bool
    /// 显影揭晓已触发（开始模糊→清晰）。在此之前展示药膜「冲印中」与摇一摇提示。
    let reveal: Bool
    let ejectDuration: Double
    /// 揭晓动画时长（模糊→清晰）
    let developDuration: Double
    let preview: CameraPreviewRef
    /// 可选变焦档位（显示倍率，如 [0.5, 1, 2, 3]）。少于 2 档时饰条回落成纯装饰形态。
    let zoomOptions: [Double]
    /// 当前显示倍率；捏合过程中是连续值（如 1.4）
    let displayZoom: Double

    let onBeforeShutter: () -> Void
    let onShutter: () -> Void
    let onFlipCamera: () -> Void
    /// 点选某一档倍率（平滑滑过去）
    let onSelectZoom: (Double) -> Void
    /// 机身捏合：起手 / 进行中（传手势的相对缩放比）
    let onPinchBegin: () -> Void
    let onPinchChange: (Double) -> Void
    let onRetake: () -> Void
    /// 删除当前出片卡上的作品（先弹确认，移到回收站）
    let onDelete: () -> Void
    let onDownload: () -> Void
    let onShare: () -> Void
    /// 报告相纸窗口在屏幕中的位置，作为新贴纸掉落起点
    let onWindowFrame: (CGRect) -> Void
    /// 报告相机机身在屏幕中的位置，作为沙盒贴纸的「地板」（贴纸只在机身上方的空白里活动）
    let onCameraFrame: (CGRect) -> Void
    /// 打开相纸选择器（仅出片完成、卡片在屏时可用）
    let onOpenPaper: () -> Void
    /// 打开当前这张的详情抽屉（改分类 / 换相纸 / 查看识别信息）；仅出片完成时可用
    let onEdit: () -> Void
    /// 把当前这张顺时针再转 90°（90 → 180 → 270 → 0 循环）；仅出片完成时可用
    let onRotate: () -> Void
    /// 用户触碰出片卡（点看原图、拖拽、卡上任意按钮）：宿主用来取消「出片后自动收起」计时
    let onCardInteraction: () -> Void
    /// 机身镜头是否渲染实时预览。展开大取景期间交由 ViewfinderExpandedView 独占，
    /// 这里留黑圆——同一个 session 上挂两个 AVCaptureVideoPreviewLayer 会互相抢画面。
    let previewLive: Bool
    /// 点镜头展开大取景（仅待机相位可用）
    let onExpandViewfinder: () -> Void

    /// 当前界面 locale（由根视图按所选语言注入），供日期格式化使用。
    @Environment(\.locale) private var locale

    // 机身闪光灯：拍照瞬间这块灯亮一下
    @State private var flashLampOn = false
    @State private var scan = false
    // 快门待命时的呼吸光环动画驱动（把视线引向拍照键）
    @State private var shutterPulse = false
    // 相纸的竖向位置与不透明度由代码显式驱动，便于做「下落撕纸 → 瞬移归位 → 出纸升起」多段动画
    @State private var paperY: CGFloat = 0
    @State private var paperOpacity: Double = 1
    @State private var didInitPaper = false
    // 点击照片在「贴图」与「原图」之间就地来回切换（不再弹框）
    @State private var showingOriginal = false
    // 向下拖拽收起：手指实时跟随的竖向位移（松手后归零或触发收起）
    @State private var dragY: CGFloat = 0
    // 旋转键的转动观感：图片瞬间转好 90° 的同时，先把视图反向预置 -90°（画面不跳），
    // 下一帧再动画回 0，看上去就是照片自己转了过去
    @State private var spin: Double = 0
    // 捏合变焦是否正在进行（用于只在手势起手时回调一次 onPinchBegin）
    @State private var pinching = false

    private var busy: Bool { phase == .ejecting || phase == .developing }
    private var paperOut: Bool { phase != .idle }
    private var showImage: Bool { (phase == .developing || phase == .done) && photo != nil }
    /// 显影等待期（尚未揭晓）：展示药膜扫描动画与「摇一摇」提示
    private var developingFilm: Bool { phase == .developing && !reveal }
    private var canShutter: Bool { cameraReady && !busy && !tearing }

    // 尺寸（全部由相机宽度派生）
    private var camH: CGFloat { camW * 1.25 }
    /// 取景镜头直径。这个比例越大取景越大，但机身内部的竖向留白也随之被吃掉——
    /// 顶板 + 镜头 + 变焦条 + 状态区加起来必须仍塞得进 camH（=1.25×camW），
    /// 所以改这里必须连着下面 lens 的上下留白一起算。
    private var lensD: CGFloat { camW * 0.70 }
    /// 取景画面在镜头里的内缩量。镜头里那几层（玻璃反光、显影遮罩）共用同一个值，
    /// 否则放大后各圈会互相错位。可见取景直径 = lensD × (1 − 2×0.09)。
    private var lensInset: CGFloat { lensD * 0.09 }
    /// 快门键外圈直径
    private let shutterSize: CGFloat = 64
    /// 快门键距机身顶的偏移。左上角的胶片计数器与它同源对齐，改这里两边一起走。
    private var shutterTop: CGFloat { camH * 0.20 }
    private var paperW: CGFloat { camW * 0.82 }
    private var paperPad: CGFloat { paperW * 0.05 }
    private var windowSide: CGFloat { paperW - paperPad * 2 }
    private var captionH: CGFloat { windowSide * 0.18 }
    private var dateStripH: CGFloat { windowSide * 0.12 }
    private var paperH: CGFloat { paperPad + dateStripH + windowSide + captionH + paperW * 0.07 }

    // 出纸口：吐纸/显影时相纸底边塞进机身槽口（slotTuck），显影完成后再升起 doneRise 露出按钮
    private var slotTuck: CGFloat { camW * 0.1 }
    private var doneRise: CGFloat { camW * 0.085 }
    private var ejectBaseY: CGFloat { -(camH / 2 + paperH / 2) }
    private var ejectedY: CGFloat { ejectBaseY + slotTuck }
    // 收起态：相纸整体落在机身高度范围内，被机身（zIndex 更高）完全盖住，底边不外露
    private var hiddenY: CGFloat { camH / 2 - paperH / 2 - camW * 0.1 }
    // 撕纸：成品向下飞离机身、落向沙盒的方向
    private var dropY: CGFloat { camH * 0.95 }

    /// 某一相位下相纸应停留的基础位置（不含撕纸/淡出的临时态）
    /// 出纸后即停在最终位置（露出底部按钮区），显影中与显影后高度/形状完全一致，
    /// 避免显影完成时卡片再上移一截造成「忽然变高」的观感。
    private func basePaperY(_ p: StudioPhase) -> CGFloat {
        switch p {
        case .idle: return hiddenY
        case .ejecting, .developing, .done: return ejectedY - doneRise
        }
    }


    var body: some View {
        ZStack {
            // 舞台：相机 + 相纸，出纸时整体下移
            ZStack {
                paper.zIndex(1)
                cameraBody.zIndex(2)
            }
            .frame(width: camW, height: camH)
            // 相机固定在中下方；相纸只管向上出纸
            .offset(y: camH * 0.42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 进入页面时按当前相位就位，避免首帧从 0 位闪一下
            paperY = basePaperY(phase)
            paperOpacity = 1
            didInitPaper = true
        }
        // 翻看到另一张时，复位「原图/贴图」切换态
        .onChange(of: photo?.id) { _, _ in showingOriginal = false }
        .onChange(of: tearing) { _, t in
            // 撕纸：成品向下落入沙盒并淡出
            if t {
                withAnimation(.easeIn(duration: 0.3)) {
                    paperY = dropY
                    paperOpacity = 0
                }
            }
        }
        .onChange(of: phase) { _, new in
            switch new {
            case .ejecting:
                // 新一张默认显示贴图（清掉上一张可能停留的「原图」切换态）
                showingOriginal = false
                dragY = 0
                spin = 0
                // 复位揭晓态，下一张从「冲印中」药膜开始
                revealActive = false
                // 出新纸：先无动画归位到藏纸口（撕纸后此刻仍透明、不可见），再上升并淡入
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { paperY = hiddenY }
                withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: ejectDuration)) {
                    paperY = basePaperY(.ejecting)   // 一次出纸到最终位置，后续显影/完成不再上移
                    paperOpacity = 1
                }
            case .done:
                // 已在出纸时停到最终位置，这里只确保位置/不透明度归位（按钮以淡入过渡出现，卡片不再上移）
                withAnimation(.easeOut(duration: 0.45)) { paperY = basePaperY(.done) }
                paperOpacity = 1
            case .idle:
                // 收起：相纸退回机身
                withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7)) {
                    paperY = hiddenY
                }
                paperOpacity = 1
            case .developing:
                break   // 维持在出纸位
            }
        }
    }

    // MARK: - 相纸

    private var paper: some View {
        VStack(spacing: 0) {
            // 顶部白边：日期
            ZStack {
                if phase == .done, let photo {
                    Text(Self.dateString(photo.timestamp, locale: locale))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                        .transition(.opacity)
                }
            }
            .frame(width: paperW, height: dateStripH)

            // 相片窗口（正方形）
            ZStack {
                Color(red: 0.082, green: 0.067, blue: 0.051)

                if !showImage || developingFilm {
                    emulsion
                }
                if phase == .done, let photo {
                    // 显影完成：展示刚拍的这张；点击在「贴图 / 原图」间就地切换。
                    // 回看历史已移到详情抽屉（日历 / 贴纸册点开），出片卡只管当前这张。
                    Group {
                        if showingOriginal {
                            Image(uiImage: photo.original)
                                .resizable().scaledToFill()
                                .frame(width: windowSide, height: windowSide)
                                .clipped()
                        } else {
                            PaperMat(style: photo.paperStyle, image: photo.displayImage)
                                .frame(width: windowSide, height: windowSide)
                        }
                    }
                    .transition(.opacity)
                    .rotationEffect(.degrees(spin))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showingOriginal.toggle() }
                    }
                } else if showImage, let photo {
                    Image(uiImage: photo.result)
                        .resizable()
                        .scaledToFill()
                        .frame(width: windowSide, height: windowSide)
                        .clipped()
                        .blur(radius: revealBlur)
                        .brightness(revealActive ? 0 : -0.5)
                        .saturation(revealActive ? 1 : 0.45)
                        .opacity(revealActive ? 1 : 0)
                }

                // 显影等待提示：摇一摇加速（拍立得甩照片）
                if developingFilm {
                    VStack {
                        Spacer()
                        Text("摇一摇加速显影")
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.bottom, windowSide * 0.12)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                // 出纸口暗影
                VStack {
                    LinearGradient(colors: [.black.opacity(0.45), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: windowSide * 0.25)
                    Spacer()
                }
                .allowsHitTesting(false)

                // 底部角标行（仅出片完成）：左下「原图 / 贴图」当前状态，右下一级分类。
                if phase == .done {
                    VStack {
                        Spacer()
                        HStack {
                            Text(showingOriginal ? "原图" : "贴图")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .padding(8)
                            Spacer()
                            // 右下角：推荐给用户的一级分类（跟随界面语言）
                            if let category = photo?.primaryCategory {
                                Text(category.titleKey)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Palette.klein.opacity(0.78)))
                                    .padding(8)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }

                // 顶部角标行（仅出片完成时）：左上「编辑 + 旋转」，右上相纸切换。
                // 这几个键随卡片一同出现/消失——不在卡片时绝不显示。
                if phase == .done {
                    VStack {
                        HStack(spacing: 8) {
                            windowButton("slider.horizontal.3", label: "编辑", action: onEdit)
                            windowButton("rotate.right", label: "旋转", action: handleRotate)
                            Spacer()
                            windowButton("square.stack.3d.up.fill", label: "相纸", action: onOpenPaper)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(width: windowSide, height: windowSide)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            // 揭晓显影：reveal 触发时做一次「模糊→清晰」动画（约 developDuration）。
            // 从历史选入（animateReveal=false）时直接成品，无需动画。
            .onChange(of: reveal) { _, r in
                if r {
                    withAnimation(animateReveal ? .easeOut(duration: developDuration) : nil) {
                        revealActive = true
                    }
                }
            }
            .background(
                // 把窗口的全局位置报告给沙盒
                GeometryReader { geo in
                    Color.clear.onChange(of: geo.frame(in: .global)) { _, f in onWindowFrame(f) }
                        .onAppear { onWindowFrame(geo.frame(in: .global)) }
                }
            )

            // 底部白边：三个操作按钮
            ZStack {
                if phase == .done {
                    HStack(spacing: 22) {
                        Button(action: onDownload) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(white: 0.35))
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel(Text("保存"))
                        Button(action: onShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Palette.klein)
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel(Text("分享"))
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(white: 0.5))
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel(Text("删除"))
                    }
                    .transition(.opacity)
                } else {
                    Text("SNAPSTICK")
                        .font(.system(size: 11)).tracking(3)
                        .foregroundColor(Color(white: 0.6))
                }
            }
            .frame(width: paperW, height: captionH + paperW * 0.07)
        }
        .padding(paperPad)
        .padding(.bottom, paperW * 0.03)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.988, blue: 0.973),
                                              Color(red: 0.953, green: 0.929, blue: 0.882)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(red: 0.36, green: 0.27, blue: 0.16).opacity(0.38),
                        radius: 15, x: 0, y: 12)
        )
        // 位置/淡出由 paperY、paperOpacity 显式驱动（见 body 的 onAppear / onChange）；
        // dragY 叠加用户向下拖拽的实时位移
        .offset(y: (didInitPaper ? paperY : basePaperY(phase)) + dragY)
        .opacity(didInitPaper ? paperOpacity : 1)
        // 卡上任何点按（含四角/底部按钮、切原图）都算「用户在看这张」，通知宿主取消自动收起
        .simultaneousGesture(TapGesture().onEnded { onCardInteraction() })
        // 在出片卡上向下滑动即可收起相纸，只留相机
        .simultaneousGesture(collapseDrag)
    }

    /// 照片窗口四角的小圆键（编辑 / 旋转 / 相纸），统一尺寸与配色。
    private func windowButton(_ icon: String, label: LocalizedStringKey,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.black.opacity(0.5)))
        }
        .accessibilityLabel(Text(label))
    }

    /// 出片完成后，在卡片上向下滑动把相纸收起（退回机身，仅留相机）。
    /// 只响应「向下为主」的拖拽，避免误触点击切换贴图/原图。
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard phase == .done else { return }
                onCardInteraction()
                // 仅在明显向下时跟随，避免与左右翻看冲突
                guard v.translation.height > 0,
                      v.translation.height > abs(v.translation.width) else { return }
                dragY = v.translation.height
            }
            .onEnded { v in
                guard phase == .done else { return }
                let down = v.translation.height
                if down > 90, down > abs(v.translation.width) {
                    // 越过阈值：收起相纸（onRetake 内部把相位切回 .idle，相纸退回机身）。
                    // dragY 一并动画归零，与 .idle 的 paperY 动画衔接，避免位置跳变。
                    withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6)) { dragY = 0 }
                    onRetake()
                } else {
                    // 未达阈值：回弹归位
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
                }
            }
    }

    private var emulsion: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.227, green: 0.208, blue: 0.18),
                                    Color(red: 0.129, green: 0.114, blue: 0.094),
                                    Color(red: 0.082, green: 0.067, blue: 0.051)],
                           center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: windowSide * 0.8)
            // 扫描线
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.12), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: windowSide * 0.16)
                .offset(y: scan ? windowSide * 0.5 : -windowSide * 0.5)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false), value: scan)
            Text("冲印中")
                .font(.system(size: 11)).tracking(5)
                .foregroundColor(Color(white: 0.6).opacity(0.6))
        }
        .onAppear { scan = true }
    }

    // 显影：用一个绑定到 phase 的派生状态制造动画的「从模糊到清晰」
    @State private var revealActive = false
    private var revealBlur: CGFloat { revealActive ? 0 : 16 }

    // MARK: - 相机机身

    private var cameraBody: some View {
        VStack(spacing: 0) {
            // 顶部炭灰面板：闪光灯 + 品牌字标 + 前后摄像头切换键（占据原品牌色指示灯位）
            HStack(spacing: camW * 0.04) {
                flashLamp
                Spacer()
                Text("SNAPSTICK")
                    .font(.system(size: 10, weight: .heavy)).tracking(2.5)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                flipButton
            }
            .padding(.horizontal, camW * 0.055)
            .padding(.vertical, camW * 0.04)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.faceplate))
            .padding(.horizontal, camW * 0.06)
            .padding(.top, camW * 0.06)

            // 大镜头。镜头从 0.62 加粗到 0.70 后，上下留白同步收窄，
            // 让「顶板 + 镜头 + 变焦条 + 状态区」的总高仍落在 camH 之内（余约 0.025×camW）。
            lens.padding(.top, camW * 0.10).padding(.bottom, camW * 0.05)

            zoomStrip

            // 底部状态区
            HStack(alignment: .bottom) {
                Text("Snap Ready")
                    .font(.system(size: 10)).tracking(2)
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Circle().fill(Palette.klein)
                    .frame(width: 8, height: 8)
                    .shadow(color: Palette.klein.opacity(0.65), radius: 5)
            }
            .padding(.horizontal, camW * 0.08)
            .padding(.top, camW * 0.035)
            Spacer(minLength: 0)
        }
        .frame(width: camW, height: camH)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [Palette.cream,
                                              Color(red: 0.898, green: 0.859, blue: 0.784)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.36, green: 0.27, blue: 0.16).opacity(0.45),
                        radius: 24, x: 0, y: 18)
        )
        .background(
            // 把机身的全局位置报告给沙盒，用作贴纸地板（贴纸停在机身上方的空白里）
            GeometryReader { geo in
                Color.clear
                    .onAppear { onCameraFrame(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { _, f in onCameraFrame(f) }
            }
        )
        .overlay(
            // 机身侧边一道品牌色细描边，强化自有识别
            RoundedRectangle(cornerRadius: 26)
                .stroke(Palette.klein.opacity(0.35), lineWidth: 1.5)
        )
        .overlay(alignment: .top) {
            // 顶部出纸口：一道低调的细缝
            Capsule().fill(.black.opacity(0.55))
                .frame(width: camW * 0.9, height: 3)
                .padding(.top, camW * 0.015)
        }
        .overlay(alignment: .topTrailing) { shutterButton }
        .overlay(alignment: .topLeading) { filmCounter }
        // 捏合变焦：手势区覆盖整个机身（取景圆太小，两指摆不开）
        .simultaneousGesture(zoomPinch)
    }

    // MARK: - 变焦条（兼品牌饰条）

    /// 变焦可用（至少两档可选）。
    private var zoomEnabled: Bool { zoomOptions.count > 1 }

    /// 镜头正下方的品牌饰条 —— 同时是变焦控件。
    /// 有两档以上可选倍率时显示倍率胶囊；否则（虚拟多摄降级、或该镜头压根不支持变焦）
    /// 回落成原本的单色圆角条 + 细分点纹装饰（原创，非任何商标光谱）。
    /// 两种形态外框尺寸完全一致，机身各段的定位不受影响，切换镜头时不会有布局跳变。
    private var zoomStrip: some View {
        HStack(spacing: camW * 0.02) {
            Group {
                if zoomEnabled {
                    HStack(spacing: camW * 0.012) {
                        ForEach(zoomOptions, id: \.self) { zoomPill($0) }
                    }
                } else {
                    HStack(spacing: camW * 0.018) {
                        ForEach(0..<7, id: \.self) { _ in
                            Capsule().fill(.white.opacity(0.22))
                                .frame(width: camW * 0.012)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // 饰条右端（最大那档倍率之后）：放大取景键
            expandButton
        }
        .padding(.horizontal, camW * 0.02)
        .frame(height: camW * 0.075)
        .background(
            Capsule().fill(LinearGradient(colors: [Palette.klein, Palette.kleinDeep],
                                          startPoint: .leading, endPoint: .trailing))
        )
        .padding(.horizontal, camW * 0.09)
    }

    /// 饰条右端的放大取景键——展开整屏的正方形大取景。
    /// 刻意不把图标叠进取景圈里：那块地方正是用户在看的画面，不该被 UI 占掉。
    /// 与变焦胶囊同高同底色，读起来是同一排控件里的一个键。
    private var expandButton: some View {
        let pillH = camW * 0.055
        return Button(action: onExpandViewfinder) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: camW * 0.032, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: pillH, height: pillH)
                .background(Circle().fill(.white.opacity(0.16)))
                // 同 zoomPill：用纵向留白把命中区补到 44pt，溢出的部分落进饰条上下的空白里
                .padding(.vertical, max(0, (44 - pillH) / 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 只有待机相位能展开（与 ContentView.expandViewfinder 的 guard 一致），
        // 出纸 / 显影 / 出片卡在屏时置灰，不做「点了没反应」的键
        .disabled(phase != .idle)
        .opacity(phase == .idle ? 1 : 0.4)
        .accessibilityLabel(Text("放大取景"))
    }

    /// 当前生效的档位：不超过当前倍率的最大档。
    /// 捏合到 1.4× 时高亮的是 1× 那颗（而不是四舍五入到 1×/2× 中更近的那个）。
    private var activeZoomLevel: Double? {
        zoomOptions.last { $0 <= displayZoom + 0.001 } ?? zoomOptions.first
    }

    /// 单个倍率胶囊。选中档用镉黄底 + 克莱因蓝字，正是品牌的蓝黄撞色。
    /// 选中的那颗显示的是**实时倍率**而非档位标称值，所以捏合到 1.4× 时它写「1.4×」，
    /// 不会出现「写着 1× 实际 1.4×」的谎报。
    private func zoomPill(_ level: Double) -> some View {
        let selected = activeZoomLevel == level
        let pillH = camW * 0.055
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectZoom(level)
        } label: {
            Text(zoomLabel(selected ? displayZoom : level))
                .font(.system(size: camW * 0.036, weight: .bold))
                .monospacedDigit()
                .foregroundColor(selected ? Palette.klein : .white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: pillH)
                .background(Capsule().fill(selected ? Palette.cadmium : .white.opacity(0.14)))
                // 饰条本体只有 camW*0.075（≈22pt）高，远低于 44pt 的最小点击目标。
                // 这里用纵向留白把命中区补到 44pt：它会溢出饰条外框、落进镜头下方和状态区
                // 的留白里（那两处没有别的控件），视觉上一切照旧。
                .padding(.vertical, max(0, (44 - pillH) / 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("变焦"))
        .accessibilityValue(Text(zoomLabel(level)))
    }

    /// 机身上的双指捏合变焦。取景圆可见直径只有 ~138pt，两根手指根本摆不开，
    /// 所以手势区放大到整个机身（camW × camH）。用 simultaneousGesture 挂载，
    /// 不抢快门/翻转键的点击，也不干扰相纸卡上的 collapseDrag（那个在另一棵子树）。
    private var zoomPinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard zoomEnabled else { return }
                if !pinching {
                    pinching = true
                    onPinchBegin()
                }
                onPinchChange(value.magnification)
            }
            .onEnded { _ in pinching = false }
    }

    /// 机身左上角的复古胶片计数器：与右上角快门对称的一面。
    /// 一块暗色嵌入式小窗 + 两位米白滚轮数字，随剩余张数 99 → 00 递减滚动。
    /// 刻意做小、低调，不抢快门的视觉重心。
    private var filmCounter: some View {
        let value = max(0, min(99, quotaRemaining))
        let digitH = camW * 0.056          // 数字窗口高度（刻意做小，弱化存在感）
        let digitW = camW * 0.034          // 单个数字宽度
        let vPad = camW * 0.012
        let hPad = camW * 0.015
        // 与右侧快门同源对齐（shutterTop + 快门半径 = 快门圆心），再略向上提一点
        let totalH = digitH + vPad * 2
        let topPad = shutterTop + shutterSize / 2 - totalH / 2 - camH * 0.03
        return HStack(spacing: -camW * 0.004) {
            DigitWheel(digit: value / 10, width: digitW, height: digitH)
            DigitWheel(digit: value % 10, width: digitW, height: digitH)
        }
        .padding(.vertical, vPad)
        .padding(.horizontal, hPad)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.02)],
                                     startPoint: .top, endPoint: .bottom))
        )
        // 滚轮接缝：横贯中线的一道细高光，暗示机械转动
        .overlay(
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Palette.ink.opacity(0.3), radius: 3, y: 1)
        .opacity(0.6)                       // 整体压暗，进一步退到快门之后
        .padding(.top, topPad)
        .padding(.leading, camW * 0.1)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: value)
        .accessibilityElement()
        .accessibilityLabel(Text("今日剩余张数"))
        .accessibilityValue(Text("\(value)"))
    }

    /// 前后摄像头切换键，占据顶部面板原品牌色指示灯的位置。
    /// 沿用克莱因蓝圆底（保留品牌锚点与发光），叠一枚白色翻转图标，
    /// 在炭灰面板上清晰可见、明确「可点」。
    private var flipButton: some View {
        Button(action: onFlipCamera) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.klein, Palette.kleinDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: camW * 0.085, height: camW * 0.085)
                    .shadow(color: Palette.klein.opacity(0.7), radius: 4)
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: camW * 0.042, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!canShutter)
        .opacity(canShutter ? 1 : 0.4)
        .accessibilityLabel(Text("切换前后摄像头"))
    }

    /// 机身左上角的闪光灯：常态是一块磨砂灯窗，拍照瞬间整块亮白并向外发光。
    private var flashLamp: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(
                colors: flashLampOn
                    ? [.white, Color(white: 0.95)]
                    : [Color(white: 0.34), Color(white: 0.16)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: camW * 0.16, height: camW * 0.06)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.white.opacity(flashLampOn ? 0.9 : 0.18), lineWidth: 1)
            )
            // 灯窗高光，强化「玻璃/灯泡」质感（居中）
            .overlay {
                Capsule().fill(.white.opacity(flashLampOn ? 0.95 : 0.22))
                    .frame(width: camW * 0.1, height: camW * 0.012)
            }
            .shadow(color: .white.opacity(flashLampOn ? 0.95 : 0),
                    radius: flashLampOn ? camW * 0.12 : 0)
    }

    private var lens: some View {
        let d = lensD
        let inset = lensInset
        return ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.33), Color(white: 0.13)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.black).padding(d * 0.08)
            // 实时取景。展开大取景时预览交给 ViewfinderExpandedView 独占，这里退回黑圆。
            Group {
                if previewLive, let h = preview.host {
                    CameraPreviewView(host: h)
                } else {
                    Color.black
                }
            }
            .clipShape(Circle())
            .padding(inset)

            if busy {
                Circle().fill(Color(red: 0.035, green: 0.031, blue: 0.027))
                    .overlay(Text("Developing")
                        .font(.system(size: 9, weight: .semibold)).tracking(4)
                        .foregroundColor(.white.opacity(0.3)))
                    .padding(inset)
            }
            // 玻璃反光
            Circle().stroke(.white.opacity(0.1)).padding(inset)
            // 品牌色镜圈
            Circle().stroke(Palette.klein.opacity(0.6), lineWidth: 2).padding(d * 0.04)

            // 直接点取景圈也能展开大取景——一块隐形的大命中区。
            // 可见的入口是下方饰条右端的 expandButton：图标不进取景圈，免得挡住正在拍的画面。
            if phase == .idle {
                Circle()
                    .fill(.clear)
                    .contentShape(Circle())
                    .onTapGesture(perform: onExpandViewfinder)
                    .accessibilityLabel(Text("放大取景"))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: d, height: d)
    }

    private var shutterButton: some View {
        Button(action: handleShutter) {
                ZStack {
                    // 待命时向外扩散淡出的呼吸光环，主动把视线引向快门
                    Circle()
                        .stroke(Palette.cadmium.opacity(0.75), lineWidth: 3)
                        .frame(width: 60, height: 60)
                        .scaleEffect(shutterPulse ? 1.4 : 1)
                        .opacity(canShutter ? (shutterPulse ? 0 : 0.85) : 0)
                        .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false),
                                   value: shutterPulse)
                        .allowsHitTesting(false)
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: shutterSize, height: shutterSize)
                        .shadow(color: Palette.ink.opacity(0.3), radius: 4, y: 2)
                    Circle()
                        .fill(Palette.cadmium)
                        .frame(width: 52, height: 52)
                        .shadow(color: Palette.cadmium.opacity(0.6), radius: 6)
                    // 中心相机图标（克莱因蓝），明确「这是拍照键」，蓝黄撞色更醒目
                    Image(systemName: "camera.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Palette.klein)
                }
            }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!canShutter)
        .opacity(canShutter ? 1 : 0.45)
        .padding(.top, shutterTop)
        .padding(.trailing, camW * 0.04)
        .onAppear { shutterPulse = true }
    }

    // MARK: - 交互

    private func handleShutter() {
        // 快门始终用于拍照；在 .done 直接按下即「撕纸连拍」（由 onShutter 内部按相位决定）。
        // 收起相纸改由在卡片上「向下滑动」触发（onRetake），不再有底部重拍按钮。
        guard canShutter else { return }
        onBeforeShutter()
        Task { @MainActor in
            // 机身闪光灯亮一下：瞬间点亮 → 快速回落
            withAnimation(.linear(duration: 0.05)) { flashLampOn = true }
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.easeOut(duration: 0.45)) { flashLampOn = false }
            onShutter()
        }
    }

    /// 旋转键：图片顺时针转 90° 的同时，把视图反向预置 -90°（两者抵消，画面不跳），
    /// 下一帧再动画回正，观感就是照片跟着手指转了过去。
    private func handleRotate() {
        guard phase == .done, photo != nil else { return }
        spin = -90          // 不包在 withAnimation 里 → 立即生效、无过渡
        onRotate()
        Task { @MainActor in
            // 等预置的这一帧落地，再从 -90 动画回 0，避免两次赋值被合并成「没动」
            withAnimation(.easeOut(duration: 0.32)) { spin = 0 }
        }
    }

    /// 日期串：按传入 locale 自适应（中文「2026年6月4日」/ 英文「June 4, 2026」）。
    static func dateString(_ date: Date, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMMd")
        return f.string(from: date)
    }
}

/// 单个数字滚轮：0~9 竖排成条，按当前数字上移并裁切出一个数字高的小窗，
/// 数字变化时偏移随父层动画滚动，得到拍立得胶片计数器的转轮观感。
private struct DigitWheel: View {
    let digit: Int          // 0...9
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0...9, id: \.self) { n in
                Text("\(n)")
                    .font(.system(size: height * 0.74, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Color(red: 0.97, green: 0.93, blue: 0.84))
                    .frame(width: width, height: height)
            }
        }
        .offset(y: -CGFloat(min(max(digit, 0), 9)) * height)
        .frame(width: width, height: height, alignment: .top)
        .clipped()
    }
}

/// 快门按钮按下反馈：回弹式缩放，模拟实体按键的下压手感。
/// 机身快门与大取景（`ViewfinderExpandedView`）的控件共用同一份手感。
struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55),
                       value: configuration.isPressed)
    }
}

/// 轻量包装，避免把 UIKit 预览视图直接作为可比较的 View 属性。
/// 携带的是 `CameraController.previewHost` 那一个共享实例（见 CameraPreviewView.swift）。
struct CameraPreviewRef {
    let host: CameraPreviewHost?
}
