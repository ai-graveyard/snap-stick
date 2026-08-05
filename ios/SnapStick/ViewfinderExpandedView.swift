//
//  ViewfinderExpandedView.swift
//  SnapStick
//
//  大取景模式：点机身镜头后展开的整屏取景层。
//
//  取景框刻意做成**正方形**——`captureSquare()` 抓的就是画面中心的正方形，1:1 对上
//  才是所见即所得。机身上那个圆形取景圈等于把同样大的正方形裁成内切圆，四个角照样
//  会被拍进照片、取景时却看不见（约 21% 的画面）；这里把那四个角还给用户。
//
//  展开期间实时预览由本视图独占：机身镜头会暂停渲染 CameraPreviewView，避免两个
//  AVCaptureVideoPreviewLayer 同时挂在同一个 AVCaptureSession 上（见 ContentView
//  的 bodyPreviewLive）。
//

import SwiftUI
import AVFoundation

struct ViewfinderExpandedView: View {
    let preview: CameraPreviewRef
    /// 可选变焦档位（显示倍率，如 [0.5, 1, 2, 3]）。少于 2 档时不显示变焦条。
    let zoomOptions: [Double]
    /// 当前显示倍率；捏合过程中是连续值（如 1.4）
    let displayZoom: Double
    /// 快门是否可按（相机就绪，且不在出纸 / 显影 / 撕纸过渡中）
    let canShutter: Bool

    let onShutter: () -> Void
    let onFlipCamera: () -> Void
    /// 点选某一档倍率（平滑滑过去）
    let onSelectZoom: (Double) -> Void
    /// 捏合：起手 / 进行中（传手势的相对缩放比）
    let onPinchBegin: () -> Void
    let onPinchChange: (Double) -> Void
    /// 收起大取景，回到机身形态
    let onCollapse: () -> Void

    /// 向下拖拽收起：手指实时跟随的竖向位移（松手后归零或触发收起）
    @State private var dragY: CGFloat = 0
    /// 捏合是否正在进行（只在起手时回调一次 onPinchBegin）
    @State private var pinching = false
    /// 快门待命时的呼吸光环
    @State private var shutterPulse = false

    /// 变焦可用（至少两档可选）。
    private var zoomEnabled: Bool { zoomOptions.count > 1 }

    var body: some View {
        GeometryReader { geo in
            // 取景框吃满屏宽（左右各留 16pt），同时留出下方控件区的高度
            let side = min(geo.size.width - 32, geo.size.height * 0.56)
            VStack(spacing: 0) {
                grabber
                Spacer(minLength: 0)
                viewfinder(side: side)
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.surface.ignoresSafeArea())
        // 下滑跟手；松手过阈值即收起
        .offset(y: max(0, dragY))
        .simultaneousGesture(collapseDrag)
        .onAppear { shutterPulse = true }
    }

    // MARK: - 顶部把手

    private var grabber: some View {
        VStack(spacing: 8) {
            Capsule().fill(Palette.label.opacity(0.22))
                .frame(width: 40, height: 5)
            Text("下滑收起")
                .font(.system(size: 11)).tracking(2)
                .foregroundColor(Palette.label.opacity(0.45))
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - 取景框

    private func viewfinder(side: CGFloat) -> some View {
        ZStack {
            // 与机身取景圈同色的药膜底，预览起来前不会闪白
            Color(red: 0.082, green: 0.067, blue: 0.051)

            if let h = preview.host {
                CameraPreviewView(host: h)
            }

            cropGuides(side: side)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background(
            // 阴影画在背后这块静态圆角矩形上，而不是直接加在含实时预览的视图上——
            // 后者会让每一帧新预览都重算一次离屏阴影，白白吃掉取景帧率。
            // 机身 cameraBody / 相纸也是同样的写法。
            RoundedRectangle(cornerRadius: 14)
                .fill(Palette.surface)
                .shadow(color: Palette.ink.opacity(0.28), radius: 18, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Palette.klein.opacity(0.5), lineWidth: 2)
        )
        // 取景框上双指捏合变焦（这里地方够大，不必像机身那样把手势铺满整块）
        .simultaneousGesture(zoomPinch)
    }

    /// 三分构图辅助线：极淡的两横两竖，帮着摆主体，不抢画面。
    private func cropGuides(side: CGFloat) -> some View {
        ZStack {
            ForEach([1.0 / 3, 2.0 / 3], id: \.self) { f in
                Rectangle().fill(.white.opacity(0.13))
                    .frame(width: 0.5)
                    .offset(x: side * (f - 0.5))
                Rectangle().fill(.white.opacity(0.13))
                    .frame(height: 0.5)
                    .offset(y: side * (f - 0.5))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 控件区

    private var controls: some View {
        VStack(spacing: 22) {
            if zoomEnabled { zoomStrip }
            HStack {
                roundButton("arrow.triangle.2.circlepath.camera.fill",
                            label: "切换前后摄像头", action: onFlipCamera)
                    .disabled(!canShutter)
                    .opacity(canShutter ? 1 : 0.4)
                Spacer()
                shutterButton
                Spacer()
                roundButton("chevron.down", label: "收起", action: onCollapse)
            }
            .padding(.horizontal, 40)
        }
        .padding(.top, 22)
        .padding(.bottom, 26)
    }

    /// 变焦条：沿用机身饰条的蓝底 + 镉黄选中档，只是放大到适合整屏操作的尺寸。
    private var zoomStrip: some View {
        HStack(spacing: 6) {
            ForEach(zoomOptions, id: \.self) { level in
                zoomPill(level)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(LinearGradient(colors: [Palette.klein, Palette.kleinDeep],
                                          startPoint: .leading, endPoint: .trailing))
        )
    }

    /// 当前生效的档位：不超过当前倍率的最大档（与机身饰条同一套判定）。
    private var activeZoomLevel: Double? {
        zoomOptions.last { $0 <= displayZoom + 0.001 } ?? zoomOptions.first
    }

    /// 选中的那颗显示**实时倍率**而非档位标称值，捏合到 1.4× 时它就写「1.4×」。
    private func zoomPill(_ level: Double) -> some View {
        let selected = activeZoomLevel == level
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelectZoom(level)
        } label: {
            Text(zoomLabel(selected ? displayZoom : level))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(selected ? Palette.klein : .white.opacity(0.78))
                .frame(width: 52, height: 34)
                .background(Capsule().fill(selected ? Palette.cadmium : .white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("变焦"))
        .accessibilityValue(Text(zoomLabel(level)))
    }

    /// 整屏取景下的大快门：造型与机身快门同源（白圈 + 镉黄盘 + 克莱因蓝相机图标）。
    private var shutterButton: some View {
        Button(action: onShutter) {
            ZStack {
                // 待命时向外扩散淡出的呼吸光环
                Circle()
                    .stroke(Palette.cadmium.opacity(0.75), lineWidth: 3)
                    .frame(width: 84, height: 84)
                    .scaleEffect(shutterPulse ? 1.32 : 1)
                    .opacity(canShutter ? (shutterPulse ? 0 : 0.85) : 0)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false),
                               value: shutterPulse)
                    .allowsHitTesting(false)
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 84, height: 84)
                    .shadow(color: Palette.ink.opacity(0.3), radius: 5, y: 2)
                Circle()
                    .fill(Palette.cadmium)
                    .frame(width: 68, height: 68)
                    .shadow(color: Palette.cadmium.opacity(0.6), radius: 8)
                Image(systemName: "camera.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(Palette.klein)
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!canShutter)
        .opacity(canShutter ? 1 : 0.45)
        .accessibilityLabel(Text("拍照"))
    }

    private func roundButton(_ icon: String, label: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Palette.label.opacity(0.8))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.chip))
        }
        .buttonStyle(ShutterButtonStyle())
        .accessibilityLabel(Text(label))
    }

    // MARK: - 手势

    /// 在整屏取景上向下滑动即可收起，回到机身形态。
    /// 与出片卡的 collapseDrag 是同一套手势语言：只认「向下为主」的拖拽。
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                // 捏合变焦时两指整体下移也会喂给 DragGesture（它只跟第一根手指），
                // 不挡掉的话调个倍率就把整层拖下去了
                guard !pinching,
                      v.translation.height > 0,
                      v.translation.height > abs(v.translation.width) else { return }
                dragY = v.translation.height
            }
            .onEnded { v in
                let down = v.translation.height
                if !pinching, down > 100, down > abs(v.translation.width) {
                    onCollapse()
                    withAnimation(.easeOut(duration: 0.26)) { dragY = 0 }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
                }
            }
    }

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
}

/// 0.5 →「0.5×」、1 →「1×」、1.4 →「1.4×」：整数不拖小数点。
/// 机身饰条（`PolaroidStudioView.zoomStrip`）与大取景的变焦条共用这一份，
/// 免得两处各写一遍、日后格式跑偏。纯数字 + ×，无需进 Localizable.xcstrings。
func zoomLabel(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded()
        ? String(format: "%.0f×", rounded)
        : String(format: "%.1f×", rounded)
}
