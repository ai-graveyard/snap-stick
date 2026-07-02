//
//  VisionCutout.swift
//  SnapStick
//
//  用 Vision 的前景主体蒙版（VNGenerateForegroundInstanceMaskRequest，iOS 17+，
//  即相册「拷贝主体」同款）把真实照片里的主体抠出来，背景任意（不再依赖白底）。
//  纯设备端、离线、免费，无需网络与 API Key。抠出主体后裁切到外接框、补一圈白色
//  模切边，得到单独贴纸。替代原来的「AI 卡通化 + 洪水填充去白底」管线。
//

import Vision
import CoreImage
import UIKit

enum VisionCutout {
    private nonisolated static let workMax = 512        // 描边工作分辨率上限（控制边框绘制开销与输出尺寸）
    private nonisolated static let borderRatio = 0.02   // 白色模切描边宽度（相对工作尺寸）

    /// 返回抠好的单独贴纸；没识别到主体或失败返回 nil，调用方回退原图。
    nonisolated static func cutout(_ image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            process(image)
        }.value
    }

    private nonisolated static func process(_ image: UIImage) -> UIImage? {
        guard let cg = normalizedCGImage(image) else { return nil }

        // Vision 前景蒙版：识别主体，背景置透明
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              !result.allInstances.isEmpty,
              let masked = try? result.generateMaskedImage(
                  ofInstances: result.allInstances,
                  from: handler,
                  croppedToInstancesExtent: true)   // 自动裁切到主体外接框
        else { return nil }

        guard let cutCG = cgImage(from: masked) else { return nil }

        // 缩到工作分辨率再补白边（控制描边开销，与历史输出尺寸保持一致）
        let scale = min(1.0, Double(workMax) / Double(max(cutCG.width, cutCG.height)))
        let w = max(1, Int((Double(cutCG.width) * scale).rounded()))
        let h = max(1, Int((Double(cutCG.height) * scale).rounded()))
        guard let buf = rgbaBuffer(from: cutCG, width: w, height: h),
              let scaled = makeCGImage(buf, w, h) else { return nil }

        let border = max(2, Int((Double(max(w, h)) * borderRatio).rounded()))
        return addStickerBorder(scaled, border: border)
    }

    /// 把 Vision 返回的带 alpha 像素缓冲转成 CGImage
    private nonisolated static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    // MARK: - 白色模切边（与原 ImageCutout 一致）

    // 在抠好的主体外补一圈实心白色模切边
    private nonisolated static func addStickerBorder(_ cut: CGImage, border b: Int) -> UIImage? {
        let cw = cut.width
        let ch = cut.height
        let outW = cw + b * 2
        let outH = ch + b * 2

        // 白色剪影：白色 RGB，alpha 跟随 cut（预乘 → 白色预乘后 = alpha 值）
        guard let silBuf = rgbaBuffer(from: cut, width: cw, height: ch) else { return nil }
        var sil = silBuf
        for p in 0..<(cw * ch) {
            let a = sil[p * 4 + 3]
            sil[p * 4] = a
            sil[p * 4 + 1] = a
            sil[p * 4 + 2] = a
        }
        guard let silCG = makeCGImage(sil, cw, ch),
              let ctx = bitmapContext(width: outW, height: outH) else { return nil }

        // cutCG / scaled 经 CGBitmapContext 往返（identity）后已是正向，CoreGraphics 自
        // 身一致：在普通位图上下文里 draw→makeImage 不会颠倒，故不再做 y 翻转（之前那次
        // 翻转是从旧 ImageCutout 照搬的，会让贴纸上下颠倒）。

        // 在半径 b 的圆盘内多次偏移绘制剪影，叠出实心白边
        let b2 = b * b
        for dy in -b...b {
            for dx in -b...b where dx * dx + dy * dy <= b2 {
                ctx.draw(silCG, in: CGRect(x: b + dx, y: b + dy, width: cw, height: ch))
            }
        }
        ctx.draw(cut, in: CGRect(x: b, y: b, width: cw, height: ch))  // 主体盖在白边之上
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }

    // MARK: - 像素工具

    private nonisolated static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// 把 CGImage 重绘到 width×height 的 RGBA8（预乘）缓冲并取出字节
    private nonisolated static func rgbaBuffer(from cg: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let ctx = bitmapContext(width: width, height: height) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return Array(UnsafeBufferPointer(start: ptr, count: width * height * 4))
    }

    private nonisolated static func makeCGImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let ctx = bitmapContext(width: w, height: h), let dst = ctx.data else { return nil }
        px.withUnsafeBytes { dst.copyMemory(from: $0.baseAddress!, byteCount: px.count) }
        return ctx.makeImage()
    }

    /// 归一化方向并取 CGImage（避免 EXIF 旋转影响逐像素处理）
    private nonisolated static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        return normalized.cgImage
    }
}
