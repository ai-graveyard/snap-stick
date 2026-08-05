//
//  AIRender.swift
//  SnapStick
//
//  AI 卡通贴纸（可选，设置 → 豆包 API 里的开关）：把拍到的照片交给豆包生成模型
//  （seedream 图生图），用与 web 版 /api/generate 完全一致的固定提示词生成
//  「冰箱贴」风格的卡通贴纸卡片（纯白背景、主体居中、四周留白）。生成的卡片由
//  调用方（ContentView.beginShot）再走本地 VisionCutout 抠出主体、补模切边。
//  任何失败（网络 / 超时 / 返回数据解不出图）都抛错，调用方回退纯本地抠图流程。
//

import UIKit

enum AIRender {
    enum RenderError: Error {
        case encodeFailed   // 输入图压缩 / 编码失败
        case badImageData   // 返回的数据解不出图片
        case timedOut       // 整体超时
    }

    /// 输入图长边上限（控制 base64 体积；只影响送给模型的输入，不影响出图分辨率）
    /// 与整体超时。2K 出图通常 10~20s，但结果挂在出片 barrier（cutoutReady）上，
    /// 必须有硬上限兜底：超时抛错回退本地，不能让显影一直卡住。
    private nonisolated static let uploadMax: CGFloat = 1024
    private nonisolated static let deadline: TimeInterval = 30

    /// 与 web 版一致的固定提示词（web/src/app/api/generate/route.ts 的 STICKER_PROMPT）
    private nonisolated static let prompt =
        "把这张照片变成一张可爱的卡通贴纸，保留主体，明快配色，纯白背景纯色平涂，主体居中且四周留出白色边距、不要触碰画面边缘"

    /// 主入口：成功返回冰箱贴风格的卡通卡片，失败抛错由调用方回退。
    static func cartoonCard(_ image: UIImage, apiKey: String, modelID: String,
                            baseURL: String) async throws -> UIImage {
        // 1. 压图并编成 data URL（后台线程，摄像头原图可能是 3000px 级别）
        guard let dataURL = await Task.detached(priority: .userInitiated, operation: {
            jpegDataURL(image)
        }).value else { throw RenderError.encodeFailed }

        // 2. 图生图（带硬超时）
        let data = try await withDeadline(deadline) {
            try await DoubaoAPI.generateImage(prompt: prompt, imageDataURL: dataURL,
                                              apiKey: apiKey, modelID: modelID,
                                              baseURL: baseURL, timeout: deadline)
        }

        guard let card = UIImage(data: data) else { throw RenderError.badImageData }
        return card
    }

    // MARK: - 图片工具

    /// 长边压到 uploadMax、JPEG 编码后拼成 data URL
    private nonisolated static func jpegDataURL(_ image: UIImage) -> String? {
        let longSide = max(image.size.width, image.size.height)
        let scale = min(1, uploadMax / max(longSide, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(),
                          height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    // MARK: - 超时竞速

    /// 让 op 与倒计时竞速：倒计时先到就抛 timedOut 并取消 op（URLSession 会响应取消）。
    private static func withDeadline<T: Sendable>(
        _ seconds: TimeInterval,
        _ op: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw RenderError.timedOut
            }
            guard let first = try await group.next() else { throw RenderError.timedOut }
            group.cancelAll()
            return first
        }
    }
}
