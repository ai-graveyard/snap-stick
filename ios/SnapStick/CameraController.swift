//
//  CameraController.swift
//  SnapStick
//
//  AVFoundation 摄像头：实时取景预览 + 即时抓取当前帧并中心正方形裁剪。
//  优先后置摄像头，失败回退前置；权限被拒时给出可重试的提示。
//  采集与会话配置在后台队列进行（AVFoundation 的推荐做法），UI 状态回主线程发布。
//

@preconcurrency import AVFoundation
import UIKit
import Combine

/// 跨线程持有最近一帧像素缓冲（采集回调在后台队列，抓拍读取在主线程）。
/// 整体 nonisolated：这是脱离主 actor 使用的跨线程类型，init 不应被默认推断为 @MainActor。
nonisolated final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    func set(_ b: CVPixelBuffer) { lock.lock(); buffer = b; lock.unlock() }
    func get() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return buffer }
}

/// 采集回调代理：独立于主 actor，把帧塞进 FrameBox。
nonisolated final class SampleBufferProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let frameBox = FrameBox()
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) { frameBox.set(pb) }
    }
}

@MainActor
final class CameraController: ObservableObject {
    enum CamError: Equatable { case denied, notFound, unknown }

    @Published var isReady = false
    @Published var error: CamError?

    /// 可选变焦档位（用户看到的显示倍率，如 [0.5, 1, 2, 3]）。
    /// 少于 2 档时机身饰条回落成纯装饰形态，不显示变焦控件。
    @Published var zoomOptions: [Double] = []
    /// 当前显示倍率。点档位时是整档，捏合过程中是连续值。
    @Published var displayZoom: Double = 1

    /// 显示倍率上限。数字变焦超过 3× 后，720p 预设 + 512px 抠图工作图下画质明显劣化，
    /// 再往上给的是「废倍率」，所以在这里封顶（光学档位同样受此约束）。
    /// 必须显式 nonisolated：本项目 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，
    /// 否则它会被推断为 MainActor 隔离，而 adoptDevice 是在 sessionQueue 上跑的 nonisolated 方法。
    nonisolated static let maxDisplayZoom: Double = 3

    nonisolated let session = AVCaptureSession()

    /// 全局唯一的取景预览视图：机身镜头与大取景轮流把它挂到自己的容器里。
    /// 见 CameraPreviewView.swift 顶部——每处各建一个会在切换时同步重建 connection，
    /// 把主线程卡住数秒。
    let previewHost = CameraPreviewHost()
    private nonisolated let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "snapstick.camera.session")
    private nonisolated let outputQueue = DispatchQueue(label: "snapstick.camera.output")
    private nonisolated let proxy = SampleBufferProxy()
    private nonisolated let ciContext = CIContext()

    private var isFront = false
    /// 会话是否已完成一次性配置（仅在串行 sessionQueue 上读写，故安全）。
    private nonisolated(unsafe) var configured = false

    /// 当前输入设备，以及「1× 对应的 videoZoomFactor」。
    /// 二者仅在串行 sessionQueue 上读写（配置时写、变焦时读），故安全；
    /// 主线程一律不碰 device，只持有下面这几个已换算好的显示倍率。
    private nonisolated(unsafe) var currentDevice: AVCaptureDevice?
    private nonisolated(unsafe) var baseZoomFactor: CGFloat = 1

    /// 当前设备的显示倍率区间（主线程侧的钳位依据，随设备切换更新）。
    private var minDisplayZoom: Double = 1
    private var maxDisplayZoom: Double = 1
    /// 捏合起手时的显示倍率，手势期间乘以 magnification。
    private var pinchStartZoom: Double = 1

    init() {
        // 趁 session 还没添加任何输入就把预览层绑上：此时没有 connection 要建，几乎零成本。
        // 等会话跑起来之后再换 layer，那个赋值会同步重建 connection，主线程要卡好几秒。
        previewHost.previewLayer.session = session
        previewHost.previewLayer.videoGravity = .resizeAspectFill
    }

    /// 把预览层转正为竖屏取景。connection 要等 session 有了视频输入才存在，
    /// 所以首次配置完成、以及每次切换前后摄像头（输入被换掉）之后都要重新应用一次。
    private func applyPreviewRotation() {
        guard let conn = previewHost.previewLayer.connection,
              conn.isVideoRotationAngleSupported(90) else { return }
        conn.videoRotationAngle = 90
    }

    /// 请求权限并启动会话；可在权限提示后重试。
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    if granted { self?.run() } else { self?.error = .denied }
                }
            }
        default:
            error = .denied
        }
    }

    /// 暂停取景：仅停止会话运行，保留已配置的输入输出，便于快速恢复。
    /// 离开主页、被弹框遮挡时调用，避免相机长时间空转发热。
    func stop() {
        let session = self.session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    /// 恢复取景：已授权则直接重新运行（首次会先完成配置）；权限被拒等错误态不反复重试。
    func resume() {
        guard error == nil,
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        run()
    }

    /// 启动会话；首次调用先一次性配置输入输出，之后仅 startRunning 快速恢复。
    private func run() {
        error = nil
        let session = self.session
        let videoOutput = self.videoOutput
        let proxy = self.proxy
        let outputQueue = self.outputQueue
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                session.beginConfiguration()
                // 用 720p 而非 .high(≈1080p)：预览依旧清晰，抓拍也只会被裁成 512px 工作图做
                // 主体抠图，720p 绰绰有余。关键是它把这路「持续吐帧」的视频管线带宽降一半多——
                // 首页沙盒是透明盖在实时相机之上的，相机管线会和沙盒 Canvas 抢 GPU/内存带宽，
                // 下落时一起重画就掉帧（日历页没有相机，所以同样的沙盒在那边满帧顺滑）。
                session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }

                let device = Self.bestDevice(for: .back) ?? Self.bestDevice(for: .front)
                guard let device,
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    Task { @MainActor [weak self] in self?.error = .notFound }
                    return
                }
                let front = device.position == .front
                session.addInput(input)

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(proxy, queue: outputQueue)
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

                session.commitConfiguration()
                self.configured = true
                // 必须在 commitConfiguration 之后：变焦区间取决于最终生效的 activeFormat
                self.adoptDevice(device)
                Task { @MainActor [weak self] in self?.isFront = front }
            }

            if !session.isRunning { session.startRunning() }
            Task { @MainActor [weak self] in
                self?.isReady = true
                self?.applyPreviewRotation()
            }
        }
    }

    /// 前后摄像头切换：在会话队列上换掉视频输入，再回主线程更新 isFront（影响抓拍的转正方向）。
    /// 仅在已完成配置且无错误时执行；找不到目标摄像头则保持原输入不变（不回调）。
    /// 切换成功后在主线程回调 onComplete(isFront)，供上层提示「已切换前/后置镜头」。
    func flipCamera(onComplete: @escaping (Bool) -> Void = { _ in }) {
        guard isReady, error == nil else { return }
        let session = self.session
        let target: AVCaptureDevice.Position = isFront ? .back : .front
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = Self.bestDevice(for: target),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            // 新镜头的构成、变焦区间都不同：重算档位并复位到 1×，不沿用上一颗的倍率
            self.adoptDevice(device)
            let front = device.position == .front
            Task { @MainActor [weak self] in
                self?.isFront = front
                // 换了输入，预览层的 connection 也跟着重建，转正角度要再应用一次
                self?.applyPreviewRotation()
                onComplete(front)
            }
        }
    }

    // MARK: - 变焦

    /// 按优先级挑镜头：三摄 → 双广角 → 广角+长焦 → 单广角。
    /// 虚拟多摄（前三种）才有光学变焦和系统自动切镜头；DiscoverySession 按 deviceTypes
    /// 给定的顺序返回，取首个即当前机型上最优的那颗。
    private nonisolated static func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera,
                          .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: position
        ).devices.first
    }

    /// 记下新设备并算出变焦档位，再把 UI 用的显示倍率发布回主线程。只在 sessionQueue 上调用。
    ///
    /// 关键点：虚拟多摄的 `videoZoomFactor` 以**首颗构成镜头**为基准，所以「1×」未必等于 1.0——
    /// 三摄/双广角的首颗是超广角（1.0 其实是 0.5×），而广角+长焦的首颗就是广角（1.0 即 1×）。
    /// 因此要按广角在 `constituentDevices` 里的位置反查对应的切换点，不能直接拿 switchOver[0]。
    /// 若当前 activeFormat 不支持切镜头，`virtualDeviceSwitchOverVideoZoomFactors` 为空，
    /// 基准退回 1.0——虚拟设备等同单颗广角，档位集自动少掉 0.5×，功能优雅降级。
    private nonisolated func adoptDevice(_ device: AVCaptureDevice) {
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors
        let constituents = device.constituentDevices
        var base: CGFloat = 1
        if let wideIndex = constituents.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
           wideIndex > 0, wideIndex - 1 < switchOvers.count {
            base = CGFloat(truncating: switchOvers[wideIndex - 1])
        }
        currentDevice = device
        baseZoomFactor = base

        // 复位到 1×：切换镜头后不沿用上一颗的倍率
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = min(max(base, device.minAvailableVideoZoomFactor),
                                         device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        }

        let minDisplay = Double(device.minAvailableVideoZoomFactor / base)
        let maxDisplay = min(Self.maxDisplayZoom, Double(device.maxAvailableVideoZoomFactor / base))
        let options = [0.5, 1.0, 2.0, 3.0].filter { $0 >= minDisplay - 0.001 && $0 <= maxDisplay + 0.001 }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.minDisplayZoom = minDisplay
            self.maxDisplayZoom = maxDisplay
            self.zoomOptions = options
            self.displayZoom = 1
        }
    }

    /// 点选倍率档：用 ramp 平滑滑过去，而不是硬跳，观感接近系统相机。
    func selectZoom(_ display: Double) { applyZoom(display, smooth: true) }

    /// 捏合开始：记下起手倍率，后续按手势的相对缩放比叠加。
    func beginPinch() { pinchStartZoom = displayZoom }

    /// 捏合进行中：直接设值（不用 ramp，否则跟不上手指）。
    func updatePinch(_ magnification: Double) { applyZoom(pinchStartZoom * magnification, smooth: false) }

    /// 钳位后立刻更新主线程侧的 displayZoom（让倍率标签实时跟手，不等队列往返），
    /// 再把换算成设备倍率的实际操作丢给 sessionQueue —— 主线程始终不碰 AVCaptureDevice。
    private func applyZoom(_ display: Double, smooth: Bool) {
        guard !zoomOptions.isEmpty else { return }
        let clamped = min(max(display, minDisplayZoom), maxDisplayZoom)
        displayZoom = clamped
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            let target = min(max(CGFloat(clamped) * self.baseZoomFactor,
                                 device.minAvailableVideoZoomFactor),
                             device.maxAvailableVideoZoomFactor)
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.cancelVideoZoomRamp()
            if smooth {
                device.ramp(toVideoZoomFactor: target, withRate: 12)
            } else {
                device.videoZoomFactor = target
            }
            device.unlockForConfiguration()
        }
    }

    /// 抓取最近一帧，中心正方形裁剪，返回上正方向的 UIImage。
    func captureSquare() -> UIImage? {
        guard let buffer = proxy.frameBox.get() else { return nil }
        // 采集缓冲是传感器朝向（横向），竖屏取景需转正：后置右转、前置左转并镜像
        let ci = CIImage(cvPixelBuffer: buffer).oriented(isFront ? .leftMirrored : .right)
        let extent = ci.extent
        let side = min(extent.width, extent.height)
        let cropRect = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2,
                              width: side, height: side)
        let cropped = ci.cropped(to: cropRect)
        guard let cg = ciContext.createCGImage(cropped, from: cropped.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
