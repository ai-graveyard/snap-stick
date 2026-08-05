//
//  CameraPreviewView.swift
//  SnapStick
//
//  把 AVCaptureVideoPreviewLayer 包进 SwiftUI，作为镜头里的实时取景画面。
//
//  全 app 只有 `CameraController.previewHost` 这一个预览视图实例，机身镜头与大取景
//  轮流把它挂到自己的容器里。**切忌每处各建一个**：给一个正在运行的 AVCaptureSession
//  绑定新的 preview layer 是同步操作，要重建 connection，实测能把主线程卡住数秒
//  （大取景来回切换时表现为整个界面卡死好几秒）。复用同一个实例后，切换只剩一次
//  addSubview，session 绑定则在会话还没添加输入时就做完了。
//

import SwiftUI
import AVFoundation

/// 承载 AVCaptureVideoPreviewLayer 的 UIView —— layerClass 直接就是预览层本身。
final class CameraPreviewHost: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// 把共享的预览视图挂进 SwiftUI 视图树。makeUIView 只是交还那个既有实例，
/// 不做任何配置——配置在 CameraController 里一次性完成。
struct CameraPreviewView: UIViewRepresentable {
    let host: CameraPreviewHost

    func makeUIView(context: Context) -> CameraPreviewHost { host }

    func updateUIView(_ uiView: CameraPreviewHost, context: Context) {}
}
