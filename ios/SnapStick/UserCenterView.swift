//
//  UserCenterView.swift
//  SnapStick
//
//  设置中心：底栏右侧 Tab（无用户/登录概念）。上半是作品统计；
//  下半是设置列表——主题外观、历史记录、贴纸物理、关于。
//  贴纸物理仍复用 SettingsView（以 sheet 弹出）。
//

import SwiftUI

struct UserCenterView: View {
    @EnvironmentObject private var settings: AppSettings

    /// 关于抽屉（更新历史）是否展开
    @State private var aboutOpen = false
    /// 豆包 API 配置页
    @State private var doubaoSettingsOpen = false

    let photos: [PhotoRecord]
    let trashedCount: Int
    let onOpenHistory: () -> Void
    let onOpenTrash: () -> Void
    let onOpenSettings: () -> Void

    private let cal = Calendar.current

    /// 本月作品数
    private var thisMonth: Int {
        photos.filter { cal.isDate($0.timestamp, equalTo: Date(), toGranularity: .month) }.count
    }

    /// 留有作品的不同天数
    private var activeDays: Int {
        Set(photos.map { cal.startOfDay(for: $0.timestamp) }).count
    }

    /// 回收站行副标题：空时是说明，有内容时带数量。
    private var trashSubtitle: LocalizedStringKey {
        trashedCount == 0 ? "已删除的贴纸，30 天后自动清空"
                          : "\(trashedCount) 张待清空，30 天后自动清空"
    }

    var body: some View {
        ZStack {
            Palette.surface
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    statsRow
                    menuList
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)    // 底栏的安全区 inset 由系统 TabView 自动处理
            }
        }
        .foregroundColor(Palette.label)
        .sheet(isPresented: $aboutOpen) { AboutSheet() }
        .sheet(isPresented: $doubaoSettingsOpen) { DoubaoSettingsView() }
    }

    // MARK: - 统计

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard("\(photos.count)", "总贴纸")
            statCard("\(thisMonth)", "本月")
            statCard("\(activeDays)", "活跃天数")
        }
    }

    private func statCard(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Palette.klein)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .shadow(color: Palette.ink.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - 入口列表

    private var menuList: some View {
        VStack(spacing: 0) {
            appearanceRow
            Divider().padding(.leading, 56)
            languageRow
            Divider().padding(.leading, 56)
            menuRow("key.fill", "豆包 API", doubaoSubtitle) { doubaoSettingsOpen = true }
            Divider().padding(.leading, 56)
            menuRow("slider.horizontal.3", "交互设置", "声音、移动速度与倾斜灵敏度", action: onOpenSettings)
            Divider().padding(.leading, 56)
            menuRow("books.vertical", "贴纸册", "回看与管理全部贴纸", action: onOpenHistory)
            Divider().padding(.leading, 56)
            menuRow("trash", "回收站", trashSubtitle, action: onOpenTrash)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
        .shadow(color: Palette.ink.opacity(0.06), radius: 6, y: 2)
    }

    private var doubaoSubtitle: LocalizedStringKey {
        if !settings.doubaoConfigured { return "填写你自己的火山方舟 Key" }
        return settings.doubaoAICartoonEnabled ? "已配置，AI 卡通贴纸已开启"
                                               : "已配置，将使用你自己的火山方舟 Key"
    }

    /// 「关于拍立贴」单独成块，不与上方设置列表相连
    private var aboutCard: some View {
        aboutRow
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .shadow(color: Palette.ink.opacity(0.06), radius: 6, y: 2)
    }

    /// 主题外观：跟随系统 / 白天 / 黑夜（直接在列表里切换）
    private var appearanceRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 16))
                .foregroundColor(Palette.klein)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.klein.opacity(0.1)))
            VStack(alignment: .leading, spacing: 8) {
                Text("主题外观").font(.system(size: 15, weight: .medium))
                segmented($settings.appearance,
                          AppearanceMode.allCases.map { ($0, $0.labelKey) })
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// 界面语言：跟随系统 / 中文 / English（直接在列表里切换）
    private var languageRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundColor(Palette.klein)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.klein.opacity(0.1)))
            VStack(alignment: .leading, spacing: 8) {
                Text("界面语言").font(.system(size: 15, weight: .medium))
                segmented($settings.language,
                          AppLanguage.allCases.map { ($0, $0.labelKey) })
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// 自制分段选择器：用 Button 驱动，规避原生 `.segmented` Picker 嵌在滚动列表里
    /// 偶发「点了不响应」的问题（同页菜单行用的也是 Button，能正常点）。
    /// 选中段填克莱因蓝、白字，未选用 chip 底、label 字；点击即写回 binding 并即时生效。
    @ViewBuilder
    private func segmented<T: Hashable>(_ selection: Binding<T>,
                                        _ options: [(T, LocalizedStringKey)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSel = selection.wrappedValue == opt.0
                Button {
                    selection.wrappedValue = opt.0
                } label: {
                    Text(opt.1)
                        .font(.system(size: 14, weight: isSel ? .semibold : .regular))
                        .foregroundColor(isSel ? .white : Palette.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSel ? Palette.klein : Color.clear)
                        .padding(2)
                )
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.chip))
        .animation(.easeInOut(duration: 0.15), value: selection.wrappedValue)
    }

    private func menuRow(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Palette.klein)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.klein.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 关于行：副标题展示最新版本的介绍；点击弹出更新历史抽屉。
    private var aboutRow: some View {
        Button { aboutOpen = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Palette.klein)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.klein.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("关于拍立贴").font(.system(size: 15, weight: .medium))
                    Text(Changelog.latest.headline)
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Text(appVersion).font(.system(size: 12, design: .monospaced)).foregroundColor(Color(white: 0.7))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? Changelog.latest.version
        return "v\(v)"
    }
}
