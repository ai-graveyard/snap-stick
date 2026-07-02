//
//  DailyQuota.swift
//  SnapStick
//
//  每日拍摄额度：每天最多拍 99 张，跨天自动清零。
//  仅一个轻量计数（存 UserDefaults：当日已拍张数 + 记录日期），
//  用于机身左上角复古滚轮计数器的「剩余张数」显示与拍照前的额度拦截。
//

import Foundation
import Combine

@MainActor
final class DailyQuota: ObservableObject {
    /// 每天最多可拍张数（计数器从 99 递减到 00）
    static let dailyLimit = 99

    /// 今日已拍张数
    @Published private(set) var usedToday: Int = 0

    private let countKey = "quota.usedToday"
    private let dayKey = "quota.day"

    init() {
        let d = UserDefaults.standard
        if let day = d.object(forKey: dayKey) as? Date, Calendar.current.isDateInToday(day) {
            usedToday = d.integer(forKey: countKey)
        } else {
            usedToday = 0
        }
    }

    /// 今日剩余可拍张数（99 → 0）
    var remaining: Int { max(0, Self.dailyLimit - usedToday) }

    /// 今日是否还能拍
    var canShoot: Bool { remaining > 0 }

    /// 跨天后把今日计数清零（进入前台 / 拍照前调用）。
    func rolloverIfNeeded() {
        let day = UserDefaults.standard.object(forKey: dayKey) as? Date
        if day == nil || !Calendar.current.isDateInToday(day!) {
            usedToday = 0
            persist()
        }
    }

    /// 记录一次成功拍摄（先跨天清零，再 +1）。
    func record() {
        rolloverIfNeeded()
        usedToday += 1
        persist()
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(usedToday, forKey: countKey)
        d.set(Date(), forKey: dayKey)
    }
}
