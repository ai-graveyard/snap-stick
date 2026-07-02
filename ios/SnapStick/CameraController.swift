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

    nonisolated let session = AVCaptureSession()
    private nonisolated let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "snapstick.camera.session")
    private nonisolated let outputQueue = DispatchQueue(label: "snapstick.camera.output")
    private nonisolated let proxy = SampleBufferProxy()
    private nonisolated let ciContext = CIContext()

    private var isFront = false
    /// 会话是否已完成一次性配置（仅在串行 sessionQueue 上读写，故安全）。
    private nonisolated(unsafe) var configured = false

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

                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
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
                Task { @MainActor [weak self] in self?.isFront = front }
            }

            if !session.isRunning { session.startRunning() }
            Task { @MainActor [weak self] in self?.isReady = true }
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
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: target),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            let front = device.position == .front
            Task { @MainActor [weak self] in
                self?.isFront = front
                onComplete(front)
            }
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
