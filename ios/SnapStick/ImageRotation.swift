//
//  ImageRotation.swift
//  SnapStick
//
//  照片旋转：把拍歪的画面按 90° 的整数倍转正（90 / 180 / 270）。
//  只做整象限重绘（换轴、不重采样），且磁盘文件始终保持原始朝向、角度只记在索引里，
//  这样反复旋转不会把 jpg 一次次重编码越压越糊。
//

import UIKit

/// 贴纸的旋转角度（顺时针，单位度）。只允许 0 / 90 / 180 / 270。
enum PhotoRotation {
    /// 归一到 0 / 90 / 180 / 270（可接受负数或超过一圈的值）
    static func normalized(_ degrees: Int) -> Int {
        (((degrees / 90) % 4 + 4) % 4) * 90
    }

    /// 下一档：在当前角度上再顺时针转 90°（90 → 180 → 270 → 0 循环）
    static func next(after degrees: Int) -> Int { normalized(degrees + 90) }
}

extension UIImage {
    /// 顺时针旋转 90° 的整数倍；0° 原样返回。
    func rotatedClockwise(_ degrees: Int) -> UIImage {
        let angle = PhotoRotation.normalized(degrees)
        guard angle != 0, size.width > 0, size.height > 0 else { return self }
        // 90 / 270：宽高互换
        let target = angle % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false   // 抠图贴纸带透明背景，不能填底
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: target.width / 2, y: target.height / 2)
            // UIKit 绘制坐标系 y 轴向下，正角即顺时针
            cg.rotate(by: CGFloat(angle) * .pi / 180)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                            width: size.width, height: size.height))
        }
    }
}

extension PhotoRecord {
    /// 旋转到指定角度后的副本：原图 / 贴纸 / 抠图三张一起转，角度记在 `rotation` 上。
    /// 内部只按「目标角 − 当前角」的差值转一次，多次旋转不会叠加重绘。
    func rotated(to degrees: Int) -> PhotoRecord {
        let target = PhotoRotation.normalized(degrees)
        let delta = PhotoRotation.normalized(target - rotation)
        guard delta != 0 else { return self }
        var copy = self
        copy.rotation = target
        copy.original = original.rotatedClockwise(delta)
        copy.result = result.rotatedClockwise(delta)
        copy.cutout = cutout?.rotatedClockwise(delta)
        return copy
    }
}
