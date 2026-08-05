//
//  CalendarView.swift
//  SnapStick
//
//  贴纸日历：把历史时间线二维化。月视图用代表贴纸铺满有作品的日子，
//  周视图把每天的贴纸叠成一摞拍立得，日视图平铺当天全部作品。
//  数据与历史抽屉同源（store.photos），点单张复用 onSelect 回看流程。
//

import SwiftUI

struct CalendarView: View {
    let photos: [PhotoRecord]
    /// 点开单张：带出这张 + 当天这组（供详情抽屉左右滑动切换）
    let onSelect: (PhotoRecord, [PhotoRecord]) -> Void
    @Binding var isOpen: Bool
    /// 共享重力源（由主页的 MotionManager 提供，避免重复创建 CMMotionManager）。
    /// 默认朝下，便于预览／无传入时也不崩。
    var gravity: () -> CGVector = { CGVector(dx: 0, dy: 1) }

    enum Mode: String, CaseIterable {
        case month = "月", week = "周", day = "日"
        /// 分段控件标签（rawValue 同时作为本地化 key）
        var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }

    /// 当前界面 locale（由根视图按所选语言注入），驱动日期与星期符号本地化。
    @Environment(\.locale) private var locale
    /// 沙盒物理参数（速度/灵敏度）跟随全局设置
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: Mode = .month
    /// 当前聚焦的时间锚点（月视图看它所在月，周视图看它所在周，日视图看当天）
    @State private var anchor = Date()

    /// 月视图「撒一把」物理游乐场：把当月贴纸倒进沙盒随手机倾斜到处跑。
    @StateObject private var playground = SandboxEngine()
    @State private var playing = false

    private let cal = Calendar.current
    private let ink = Palette.label
    private let accent = Color(red: 0.83, green: 0.52, blue: 0.27)

    /// 预聚合：以「当天 00:00」为 key 的贴纸字典，避免每个格子重复过滤
    private var byDay: [Date: [PhotoRecord]] {
        Dictionary(grouping: photos) { cal.startOfDay(for: $0.timestamp) }
    }

    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                content
                    // 内容区左右滑动切换 月/周/日 视图（与顶部分段控件联动：左滑→下一个，右滑→上一个）。
                    // 用 simultaneousGesture 不抢 ScrollView 的竖向滚动，只在横向位移占主导时才切换。
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24, coordinateSpace: .local)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                                switchMode(dx < 0 ? 1 : -1)
                            }
                    )
            }

            // 游乐场整屏覆盖（从屏幕顶开始），其局部坐标才与 floorY（window 坐标）对齐，
            // 贴纸才会被挡在 Tab 栏顶边、不会掉到 Tab 以下。
            if playing { playgroundLayer.transition(.opacity) }
            // 仅月视图、且当月有贴纸时显示「撒一把／收起」悬浮按钮
            if mode == .month && !monthPhotos.isEmpty { playToggle }
        }
        .foregroundColor(ink)
        // 离开日历 Tab 时收起游乐场，停掉物理循环省电
        .onChange(of: isOpen) { _, open in if !open { stopPlaying() } }
        // 切到周/日视图时收起游乐场；翻月时同步成新月份的贴纸
        .onChange(of: mode) { _, m in if m != .month { stopPlaying() } }
        .onChange(of: anchor) { _, _ in
            if playing { playground.sync(photoIDs: playgroundPhotos.map(\.id), freshId: nil) }
        }
    }

    // MARK: - 导航栏（模式切换 + 翻页）

    private var navBar: some View {
        VStack(spacing: 10) {
            modeSwitcher
                .padding(.horizontal, 16)

            HStack {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                Text(periodTitle).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { step(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
            }
            .foregroundColor(ink)
            .padding(.horizontal, 12)

            if !cal.isDate(anchor, equalTo: Date(), toGranularity: dayGranularity) {
                Button { withAnimation(.easeOut(duration: 0.2)) { anchor = Date() } } label: {
                    Text("回到今天").font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                }
            }
        }
        .padding(.top, 24).padding(.bottom, 10)
    }

    /// 月/周/日 切换：用普通按钮自绘分段控件，确保点击稳定可用
    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                let selected = mode == m
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    Text(m.titleKey)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? .white : ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Palette.klein : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11).fill(Palette.chip))
    }

    private var dayGranularity: Calendar.Component {
        switch mode { case .month: return .month; case .week: return .weekOfYear; case .day: return .day }
    }

    /// 横向滑动切换 月→周→日 视图（dir=+1 下一个 / -1 上一个），到头不循环。
    private func switchMode(_ dir: Int) {
        let all = Mode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        let next = i + dir
        guard next >= 0, next < all.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) { mode = all[next] }
    }

    private func step(_ dir: Int) {
        let comp: Calendar.Component = dayGranularity
        let value: Int = mode == .week ? dir * 7 : dir
        let unit: Calendar.Component = mode == .week ? .day : comp
        if let next = cal.date(byAdding: unit, value: value, to: anchor) {
            withAnimation(.easeOut(duration: 0.2)) { anchor = next }
        }
    }

    // MARK: - 内容路由

    @ViewBuilder private var content: some View {
        switch mode {
        case .month: monthView
        case .week: weekView
        case .day: dayView
        }
    }

    // MARK: - 月视图

    private var monthView: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { s in
                        Text(s).font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                        if let day { monthCell(day) } else { Color.clear.aspectRatio(1, contentMode: .fit) }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
        }
    }

    /// 当前月份的全部贴纸（「撒一把」游乐场用），按时间先后排序
    private var monthPhotos: [PhotoRecord] {
        photos.filter { cal.isDate($0.timestamp, equalTo: anchor, toGranularity: .month) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// 「撒一把」最多倒进沙盒的贴纸数：超过会太挤，只取当月最近的 30 张。
    private static let playgroundCap = 30
    private var playgroundPhotos: [PhotoRecord] {
        Array(monthPhotos.suffix(Self.playgroundCap))
    }

    /// 贴纸 id → 展示图查表，传给沙盒做 O(1) 取图（替代每帧线性 first 查找）。
    private var playgroundImages: [UUID: UIImage] {
        Dictionary(photos.map { ($0.id, $0.displayImage) }, uniquingKeysWith: { a, _ in a })
    }

    /// 物理游乐场：不透明铺底盖住月历格子，复用主页的贴纸沙盒视图
    private var playgroundLayer: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            StickerSandboxView(engine: playground, frameStore: playground.frameStore,
                               images: playgroundImages)
            VStack {
                Text("倾斜手机，贴纸会到处跑")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(.top, 6)
                Spacer()
            }
        }
    }

    /// 右下角悬浮按钮：撒一把（展开游乐场）／收起
    private var playToggle: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button { playing ? stopPlaying() : startPlaying() } label: {
                    Image(systemName: playing ? "xmark" : "hand.draw.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Palette.klein))
                        .shadow(color: Palette.ink.opacity(0.25), radius: 6, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private func startPlaying() {
        playground.gravityProvider = gravity
        playground.speed = CGFloat(settings.speed)
        playground.sensitivity = CGFloat(settings.sensitivity)
        playground.start()
        playground.dropIn(photoIDs: playgroundPhotos.map(\.id))   // 从顶上一起掉落（最多 30 张）
        withAnimation(.easeOut(duration: 0.25)) { playing = true }
    }

    private func stopPlaying() {
        guard playing else { return }
        withAnimation(.easeIn(duration: 0.2)) { playing = false }
        playground.stop()
    }

    private func monthCell(_ day: Date) -> some View {
        let items = byDay[cal.startOfDay(for: day)] ?? []
        let isToday = cal.isDateInToday(day)
        let dayNum = cal.component(.day, from: day)
        return Button {
            guard !items.isEmpty else { return }
            anchor = day
            withAnimation(.easeInOut(duration: 0.2)) { mode = .day }
        } label: {
            ZStack(alignment: .topLeading) {
                if let rep = items.first?.displayImage {
                    // 不垫底板、不描边、不投影，贴纸直接铺在页面底色上。
                    // 仍用一块透明方板撑住格子：整张照片必须完整收进方格，
                    // 以较长的一边为准等比缩放（不裁切、不溢出到相邻格子）。
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            Image(uiImage: rep)
                                .resizable().scaledToFit()
                        }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.chip)
                        .aspectRatio(1, contentMode: .fit)
                }

                Text("\(dayNum)")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular, design: .monospaced))
                    .foregroundColor(items.isEmpty ? Color(white: 0.42) : .white)
                    .padding(3)
                    .background(items.isEmpty ? nil : Capsule().fill(.black.opacity(0.45)))
                    .padding(3)

                if items.count > 1 {
                    VStack { Spacer(); HStack { Spacer()
                        Text("\(items.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ink)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.card))
                            .padding(4)
                    } }
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: 2)
                }
            }
            // 底板改成透明后，整格仍要可点（抠图周围的透明区域不能吞掉点击）
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 周视图（叠拍立得）

    private var weekView: some View {
        let days = weekDays
        return ScrollView {
            HStack(alignment: .top, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let items = byDay[cal.startOfDay(for: day)] ?? []
                    VStack(spacing: 8) {
                        VStack(spacing: 1) {
                            Text(shortWeekday(day))
                                .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                            Text("\(cal.component(.day, from: day))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(cal.isDateInToday(day) ? .white : ink)
                                .frame(width: 24, height: 24)
                                .background(cal.isDateInToday(day) ? Circle().fill(accent) : nil)
                        }
                        stackedColumn(items, day: day)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 12)
        }
    }

    /// 周视图一摞拍立得：点任意一张都进入当天的日视图（与月视图点格子一致），
    /// 不直接打开单张，便于先看清这天的全部作品再选。
    private func stackedColumn(_ items: [PhotoRecord], day: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, photo in
                Button {
                    anchor = day
                    withAnimation(.easeInOut(duration: 0.2)) { mode = .day }
                } label: {
                    Image(uiImage: photo.displayImage)
                        .resizable().scaledToFit()
                        .overlay(alignment: .topLeading) { indexBadge(idx + 1) }
                        .rotationEffect(.degrees(tilt(idx)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 用索引派生一个稳定的小角度，制造手贴的随意感（不依赖随机数）
    private func tilt(_ idx: Int) -> Double {
        let pattern: [Double] = [-3, 2.5, -1.5, 3, -2, 1.5]
        return pattern[idx % pattern.count]
    }

    // MARK: - 日视图

    private var dayView: some View {
        let items = (byDay[cal.startOfDay(for: anchor)] ?? [])
            .sorted { $0.timestamp > $1.timestamp }
        return ScrollView {
            if items.isEmpty {
                Text("这一天还没有贴纸")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, photo in
                        dayCard(photo, index: idx + 1, siblings: items)
                    }
                }
                .padding(16)
            }
        }
    }

    /// 日视图单卡：左上角序号角标，点按打开详情抽屉（分享/删除/换相纸都在详情里）。
    /// 贴纸本身已带白色模切边，直接浮在页面底色上，不再垫卡片底板与投影。
    /// siblings 为当天这组，传给详情抽屉作左右滑动切换的范围。
    private func dayCard(_ photo: PhotoRecord, index: Int, siblings: [PhotoRecord]) -> some View {
        VStack(spacing: 6) {
            Button { onSelect(photo, siblings) } label: {
                Image(uiImage: photo.displayImage)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) { indexBadge(index) }
            }
            .buttonStyle(.plain)

            Text(timeString(photo.timestamp))
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
        }
    }

    /// 左上角序号角标：低调的半透明小药丸（与月视图计数角标同款），仅作轻提示，不抢图。
    private func indexBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(.black.opacity(0.3)))
            .padding(5)
    }

    // MARK: - 标题与日期工具

    private var periodTitle: String {
        let f = DateFormatter(); f.locale = locale
        switch mode {
        case .month:
            f.setLocalizedDateFormatFromTemplate("yMMMM")
            return f.string(from: anchor)
        case .week:
            let days = weekDays
            guard let first = days.first, let last = days.last else { return "" }
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return "\(f.string(from: first)) – \(f.string(from: last))"
        case .day:
            f.setLocalizedDateFormatFromTemplate("yMMMMdEEEE")
            return f.string(from: anchor)
        }
    }

    private func timeString(_ ts: Date) -> String {
        let f = DateFormatter(); f.locale = locale; f.dateFormat = "HH:mm"
        return f.string(from: ts)
    }

    /// 当前 locale 下、按 firstWeekday 排好序的单字星期符号（中文「日一二…」/ 英文「S M…」）
    private var weekdaySymbols: [String] {
        var c = cal; c.locale = locale
        let base = c.veryShortWeekdaySymbols   // 周日打头
        let start = cal.firstWeekday - 1
        return (0..<7).map { base[($0 + start) % 7] }
    }

    private func shortWeekday(_ day: Date) -> String {
        var c = cal; c.locale = locale
        return c.veryShortWeekdaySymbols[cal.component(.weekday, from: day) - 1]
    }

    /// 当前锚点所在月的格子（前置空位补 nil，凑满整周）
    private var monthCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let firstWeekday = cal.component(.weekday, from: first)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: anchor)?.count ?? 0
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<count {
            cells.append(cal.date(byAdding: .day, value: d, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// 当前锚点所在周的 7 天
    private var weekDays: [Date] {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }
}
