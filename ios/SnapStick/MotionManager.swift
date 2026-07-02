//
//  MotionManager.swift
//  SnapStick
//
//  陀螺仪 / 重力传感器：把设备倾斜映射成屏幕平面里的重力方向，
//  驱动贴纸在物理沙盒里随手机倾斜滑动。对应网页版的 deviceorientation。
//  iOS 上 CoreMotion 的 deviceMotion 不需要权限弹窗，比网页省心。
//

import CoreMotion
import CoreGraphics
import Combine

@MainActor
final class MotionManager: ObservableObject {
    /// 屏幕坐标系重力方向（x 向右、y 向下），模长 ≤ 1。供物理循环每帧读取。
    private(set) var gravity = CGVector(dx: 0, dy: 1)

    @Published var isActive = false

    /// 摇晃手机回调（拍立得「甩照片」加速显影用）。在主线程触发。
    var onShake: (() -> Void)?
    /// 触发摇晃的去抖时间戳（用 CoreMotion 自带时间轴，避免依赖 Date）
    private var lastShakeTime: TimeInterval = 0

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = motion.gravity
            // 设备坐标：x 右、y 上、z 出屏。竖直拿 ≈ (0, -1, 0)。
            // 屏幕坐标 y 向下，故取反；平放时 x/y≈0 → 近乎失重、可自由滑动。
            var gx = g.x
            var gy = -g.y
            let mag = (gx * gx + gy * gy).squareRoot()
            if mag > 1 { gx /= mag; gy /= mag }
            self.gravity = CGVector(dx: gx, dy: gy)

            // 甩动检测：用户加速度（已剔除重力）模长超过阈值即视为一次摇晃，
            // 带 0.4s 去抖，避免一次甩动连发多次。
            let a = motion.userAcceleration
            let aMag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            if aMag > 1.8 {
                let t = motion.timestamp
                if t - self.lastShakeTime > 0.4 {
                    self.lastShakeTime = t
                    self.onShake?()
                }
            }
        }
        isActive = true
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        isActive = false
    }
}
