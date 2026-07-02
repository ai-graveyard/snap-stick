//
//  AboutSheet.swift
//  SnapStick
//
//  「关于拍立贴」抽屉：设置页的关于行点开后，自下而上弹出的更新历史。
//  顶部突出当前（最新）版本的介绍，下方按版本倒序列出历次更新。
//  Changelog 是更新历史的单一来源——发版时在 releases 顶部追加一条即可。
//

import SwiftUI

/// 一个版本的更新说明。
struct AppRelease: Identifiable {
    let version: String           // 例如 "1.1"
    let date: LocalizedStringKey  // 发布时间，展示用
    let headline: LocalizedStringKey
    let notes: [LocalizedStringKey]
    var id: String { version }
}

/// 更新历史（倒序，最新在最前）。发版时在顶部追加一条。
enum Changelog {
    static let releases: [AppRelease] = [
        AppRelease(
            version: "1.1",
            date: "2026 年 6 月",
            headline: "回收站与中英双语",
            notes: [
                "新增「回收站」，删除的贴纸 30 天内都能恢复",
                "主体识别更精准，抠图边缘更干净",
                "全面支持中英文，可在设置里随时切换",
                "更多相纸样式与细节打磨",
            ]
        ),
        AppRelease(
            version: "1.0",
            date: "2026 年 5 月",
            headline: "拍立贴，正式登场",
            notes: [
                "对准、按下快门，把此刻冲印成贴纸",
                "甩一甩手机，加速显影",
                "陀螺仪物理沙盒，贴纸随手机倾斜滑动碰撞",
                "日历与贴纸册，随时回看过往",
            ]
        ),
    ]

    /// 最新版本（用于关于行的默认介绍）。
    static var latest: AppRelease { releases[0] }
}

/// 自下而上的更新历史抽屉。
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(Changelog.releases) { release in
                        releaseBlock(release, isLatest: release.id == Changelog.latest.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .foregroundColor(Palette.label)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 抽屉头部：App 名 + 当前版本简介。
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.klein))
                VStack(alignment: .leading, spacing: 2) {
                    Text("拍立贴").font(.system(size: 20, weight: .bold))
                    HStack(spacing: 5) {
                        Text(verbatim: "v\(Changelog.latest.version)")
                        Text(verbatim: "·")
                        Text(Changelog.latest.headline)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
            }
            Text("更新历史").font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }

    /// 单个版本块。
    private func releaseBlock(_ release: AppRelease, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: "v\(release.version)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Palette.klein)
                if isLatest {
                    Text("最新")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.klein))
                }
                Spacer()
                Text(release.date).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text(release.headline).font(.system(size: 14, weight: .medium))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Palette.klein.opacity(0.5)).frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(note).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .shadow(color: Palette.ink.opacity(0.05), radius: 6, y: 2)
    }
}
