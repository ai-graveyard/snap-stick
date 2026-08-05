//
//  StickerSandboxView.swift
//  SnapStick
//
//  物理沙盒：新贴纸从相纸窗口「脱落」带挤压回弹掉进屏幕，历史贴纸散落全屏，
//  随手机倾斜（重力方向）自由滑动、互相碰撞堆叠。对应网页版 StickerSandbox。
//

import SwiftUI
import QuartzCore
import Combine

// 物理常量（与网页版一致）
private let STICKER: CGFloat = 78
private let RADIUS: CGFloat = STICKER * 0.42
private let GRAVITY: CGFloat = 2600
private let RESTITUTION: CGFloat = 0.42
private let WALL_FRICTION: CGFloat = 0.78
private let AIR: CGFloat = 0.992
private let ANG_DAMP: CGFloat = 0.94
private let ANG_SLEEP: CGFloat = 6        // 角速度(deg/s)低于此值就归零，让落地贴纸停止打转
private let IMPACT_SPIN_MIN: CGFloat = 220 // 入射速度超过此值才算「砸」到地板、产生滚动自旋
private let WALL_HAPTIC_MIN: CGFloat = 320 // 入射速度超过此值才算「砸」到边、触发一次震动
private let HAPTIC_DEBOUNCE: CFTimeInterval = 0.09 // 撞墙震动全局节流，避免多体同帧／连续帧机枪式连震
private let MAX_STEP: CGFloat = 1.0 / 60.0       // 单个物理子步时长上限；dt 超过即拆成多个固定子步，避免穿模
private let MAX_SUBSTEPS = 4                      // 掉帧追赶的子步上限，超过则放弃追赶（防止卡死后的「死亡螺旋」）
private let COLLISION_ITERS = 4
private let REST_FRAMES = 40                     // 连续无运动帧数达到即休眠（≈0.33s @120fps），避免抛物线顶点等瞬时静止误判
private let REST_GRAVITY_EPS: CGFloat = 0.02    // 休眠中重力方向变化超过此值即唤醒（倾斜手机）
private let ACTIVE_FPS = 120                      // 活动时帧率：跟随屏幕刷新（ProMotion 120Hz 更顺滑；系统按设备能力自动钳到 60）
private let REST_FPS = 15                        // 休眠时仅低频轮询重力，省电
private let SIZE_MIN: CGFloat = 0.82
private let SIZE_MAX: CGFloat = 1.18
private let JITTER_MIN: CGFloat = 0.88
private let JITTER_MAX: CGFloat = 1.18

private final class Body {
    let id: UUID
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var angle: CGFloat = 0   // deg
    var va: CGFloat = 0      // deg/s
    var size: CGFloat = 1
    var radius: CGFloat = RADIUS
    var motionScale: CGFloat = 1
    var held: Bool = false    // 手指正按住拖动时为 true：暂停重力，不被碰撞推走
    init(id: UUID) { self.id = id }
}

struct BodyFrame: Identifiable, Equatable {
    let id: UUID
    let x: CGFloat
    let y: CGFloat
    let angle: CGFloat
    let scale: CGFloat
}

/// 只承载「每帧位置数据」的轻量可观察对象。把它从 `SandboxEngine` 拆出来，是为了
/// 让每帧 60/120Hz 的位置更新只通知观察它的沙盒视图（Canvas）重绘，而**不**触发持有
/// `SandboxEngine` 的 ContentView/CalendarView 重算——否则 engine 上这一个 `@Published`
/// 每帧发一次 `objectWillChange`，会把整棵首页视图树（含相机预览）每秒重建 60 次。
@MainActor
final class SandboxFrameStore: ObservableObject {
    @Published var frames: [BodyFrame] = []
}

@MainActor
final class SandboxEngine: NSObject, ObservableObject {
    /// 帧数据放在独立对象里（见 `SandboxFrameStore` 说明）；engine 自身不再有任何
    /// `@Published`，所以持有它的视图不会因每帧位置更新而重算。
    let frameStore = SandboxFrameStore()

    var gravityProvider: () -> CGVector = { CGVector(dx: 0, dy: 1) }
    /// 贴纸以足够速度砸到任一边缘时回调一次（节流后），由外部接到触感反馈。
    var onWallHit: () -> Void = {}
    private var lastHapticTime: CFTimeInterval = 0
    var spawnRect: CGRect?
    var speed: CGFloat = CGFloat(AppSettings.defaultSpeed)
    var sensitivity: CGFloat = CGFloat(AppSettings.defaultSensitivity)
    /// 活动帧率。首页沙盒透明盖在实时相机上，每帧都要和动态视频合成（很贵），故降到 60；
    /// 日历游乐场盖在不透明背景上、合成几乎免费，保持 120。须取 120 的整数分频（60/40/30）
    /// 以保证在 ProMotion 上节奏均匀不抖动。运行中修改会即时套用到当前 CADisplayLink。
    var activeFPS: Int = ACTIVE_FPS {
        didSet { if !resting { link?.preferredFramesPerSecond = activeFPS } }
    }
    var viewport: CGSize = .zero
    /// 碰撞地板的屏幕 y 坐标（取底栏 Tab 栏顶边）：贴纸落到 Tab 栏上沿就被挡住，
    /// 不会掉到 Tab 以下。<=0 表示尚未量到，退回用整屏高度当地板。
    var floorY: CGFloat = 0
    /// 地板覆盖值（屏幕 y）：首页把它设为相机机身顶边，让悬浮贴纸只在机身上方的空白里
    /// 落定、来回滑动（而不是掉到屏幕最底部）。为 nil 时退回用 `floorY`（Tab 栏顶边）。
    var floorOverride: CGFloat?

    /// 在视口高度 h 下的有效地板：优先用 `floorOverride`（机身顶边），否则用量到的 Tab 栏顶边，
    /// 都没有则退回整屏高度。结果钳在 (0, h] 内。
    private func floorValue(_ h: CGFloat) -> CGFloat {
        let f = floorOverride ?? floorY
        return f > 0 ? min(f, h) : h
    }

    private var bodies: [UUID: Body] = [:]
    private var order: [UUID] = []
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    /// 是否允许运行（仅在拍照页 / 前台为 true）；离开 Tab 或进后台时彻底停掉 CADisplayLink。
    private var enabled = false
    /// 休眠态：所有贴纸都静止了，只低频轮询重力等待倾斜唤醒——跳过物理与发布（不算碰撞、不重绘）。
    private var resting = false
    /// 连续无运动帧计数，达到 REST_FRAMES 即转入休眠。
    private var stillFrames = 0
    /// 上一帧重力方向，休眠中用来判断手机是否被倾斜。
    private var lastGravity = CGVector(dx: 0, dy: 1)
    private var viewportSize: CGSize {
        if viewport.width > 0, viewport.height > 0 {
            return viewport
        }
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            return window.bounds.size
        }
        return CGSize(width: 1, height: 1)
    }

    /// 进入拍照页 / 回到前台时调用：允许运行并启动循环。
    func start() {
        guard !enabled else { return }
        enabled = true
        startLink()
    }

    /// 离开拍照页 / 进入后台时调用：彻底停掉 CADisplayLink，不再空转。
    func stop() {
        enabled = false
        link?.invalidate()
        link = nil
        lastTime = 0
        resting = false
        stillFrames = 0
    }

    /// 从休眠恢复全速模拟（新增/抓取/抛出贴纸、检测到倾斜时调用）。
    func wake() {
        stillFrames = 0
        guard resting else { return }
        resting = false
        link?.preferredFramesPerSecond = activeFPS
    }

    private func startLink() {
        guard enabled, link == nil else { return }
        resting = false
        stillFrames = 0
        lastTime = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFramesPerSecond = activeFPS
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// 与可见贴纸列表对齐：新增建体（freshId 从相纸掉落），删除清体。
    func sync(photoIDs: [UUID], freshId: UUID?) {
        let incoming = Set(photoIDs)
        for id in bodies.keys where !incoming.contains(id) { bodies.removeValue(forKey: id) }
        for id in photoIDs where bodies[id] == nil {
            bodies[id] = makeBody(id: id, fresh: id == freshId)
        }
        order = photoIDs
        wake()
    }

    /// 把整组贴纸从屏幕顶部「倒下来」：在顶边一条窄带内随机错落排布、带向下初速度，
    /// 靠重力继续坠落（顶边有墙不能放到屏幕外，所以贴着顶边生成）。日历「撒一把」入场用。
    func dropIn(photoIDs: [UUID]) {
        let size = viewportSize
        let w = size.width
        let h = size.height
        bodies.removeAll()
        for id in photoIDs {
            let b = makeBody(id: id, fresh: false)   // 复用 size/radius/motionScale 计算
            b.x = rand(b.radius, w - b.radius)
            b.y = b.radius + rand(0, h * 0.12)       // 贴着顶边的窄带
            b.vx = rand(-40, 40) * b.motionScale
            b.vy = rand(140, 300) * b.motionScale    // 向下初速度，制造坠落感
            b.angle = rand(-14, 14)
            b.va = rand(-90, 90) * b.motionScale
            bodies[id] = b
        }
        order = photoIDs
        wake()
    }

    /// 手指按住一张贴纸：暂停其重力与自旋，准备跟随手指。
    func grab(_ id: UUID) {
        guard let b = bodies[id] else { return }
        b.held = true
        b.vx = 0; b.vy = 0; b.va *= 0.3
        wake()
    }

    /// 拖动中：直接把贴纸贴到手指位置（限制在视口内）。
    func dragTo(_ id: UUID, point: CGPoint) {
        guard let b = bodies[id] else { return }
        let size = viewportSize
        let w = size.width
        let h = size.height
        let floor = floorValue(h)
        b.x = min(max(point.x, b.radius), w - b.radius)
        b.y = min(max(point.y, b.radius), floor - b.radius)
    }

    /// 松手：按甩动速度抛出（适度衰减），重新交回物理模拟。
    func release(_ id: UUID, velocity: CGVector) {
        guard let b = bodies[id] else { return }
        b.held = false
        let throwScale: CGFloat = 0.5
        let maxV: CGFloat = 4000
        b.vx = min(max(velocity.dx * throwScale, -maxV), maxV)
        b.vy = min(max(velocity.dy * throwScale, -maxV), maxV)
        wake()
    }

    private func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + CGFloat.random(in: 0...1) * (b - a) }

    private func makeBody(id: UUID, fresh: Bool) -> Body {
        let boundsSize = viewportSize
        let w = boundsSize.width
        let h = boundsSize.height
        let floor = floorValue(h)
        let b = Body(id: id)
        let size = rand(SIZE_MIN, SIZE_MAX)
        let motion = pow(1 / size, 0.85) * rand(JITTER_MIN, JITTER_MAX)
        b.size = size
        b.radius = RADIUS * size
        b.motionScale = motion

        if fresh {
            let r = spawnRect
            b.x = r.map { $0.midX } ?? w / 2
            b.y = r.map { $0.midY } ?? h * 0.34
            b.vx = rand(-80, 80) * motion
            b.vy = rand(60, 160) * motion
            b.angle = rand(-12, 12)
            b.va = rand(-120, 120) * motion
        } else {
            b.x = rand(b.radius, w - b.radius)
            b.y = rand(b.radius, floor - b.radius)
            b.angle = rand(-10, 10)
        }
        return b
    }

    @objc private func tick(_ link: CADisplayLink) {
        let g = gravityProvider()
        if resting {
            // 休眠：只比对重力方向，倾斜手机即唤醒；否则跳过物理与发布（不算碰撞、不重绘）。
            let dx = g.dx - lastGravity.dx, dy = g.dy - lastGravity.dy
            if dx * dx + dy * dy > REST_GRAVITY_EPS * REST_GRAVITY_EPS {
                wake()
            } else {
                lastTime = link.timestamp   // 保持时间基准，唤醒首帧 dt 不暴冲
                return
            }
        }
        lastGravity = g
        if lastTime == 0 { lastTime = link.timestamp; return }
        let dt = CGFloat(link.timestamp - lastTime)
        lastTime = link.timestamp
        if dt <= 0 { return }
        // 掉帧后用固定子步「追赶」真实时间，而不是把 dt 截断。截断会让模拟落后于真实
        // 时间，表现为掉帧后「慢半拍」的顿挫；子步则在保持数值稳定（不穿模）的前提下追上。
        var moving = false
        if dt > MAX_STEP {
            let steps = min(Int((dt / MAX_STEP).rounded(.up)), MAX_SUBSTEPS)
            let sub = dt / CGFloat(steps)
            for _ in 0..<steps {
                if simulate(sub) { moving = true }
            }
        } else {
            moving = simulate(dt)
        }
        publish()
        if moving {
            stillFrames = 0
        } else if stillFrames < REST_FRAMES {
            stillFrames += 1
        } else {
            // 连续多帧无运动：转入休眠，降频轮询重力以省电
            resting = true
            link.preferredFramesPerSecond = REST_FPS
        }
    }

    /// 返回本帧是否仍有运动（有任一贴纸被按住或速度非零）；全静止则交由 tick 计入休眠。
    @discardableResult
    private func simulate(_ dt: CGFloat) -> Bool {
        let size = viewportSize
        let w = size.width
        let h = size.height
        let floor = floorValue(h)   // 地板优先取相机机身顶边，否则 Tab 栏顶边

        var g = gravityProvider()
        g.dx *= sensitivity; g.dy *= sensitivity
        let mag = (g.dx * g.dx + g.dy * g.dy).squareRoot()
        if mag > 1 { g.dx /= mag; g.dy /= mag }

        let gravityPower = GRAVITY * speed
        let ax = gravityPower * g.dx
        let ay = gravityPower * g.dy
        let arr = order.compactMap { bodies[$0] }

        var wallHit = false   // 本帧是否有贴纸以足够速度砸到边缘（任一即可，节流后只震一次）
        var moving = false    // 本帧是否仍有运动；全静止则计入休眠
        for b in arr {
            if b.held { moving = true; continue }   // 被按住：跟随手指，跳过重力积分与边界反弹
            let bax = ax * b.motionScale
            let bay = ay * b.motionScale
            b.vx = (b.vx + bax * dt) * AIR
            b.vy = (b.vy + bay * dt) * AIR
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.angle += b.va * dt
            b.va *= ANG_DAMP

            // 反弹前的入射速度（按门槛判定是否算「砸」边）。静止压在边上的贴纸 vy/vx
            // 已被下方休眠逻辑归零，不会越过门槛，所以不会每帧续震。
            if b.x < b.radius { if b.vx < -WALL_HAPTIC_MIN { wallHit = true }; b.x = b.radius; b.vx = -b.vx * RESTITUTION; b.vy *= WALL_FRICTION }
            else if b.x > w - b.radius { if b.vx > WALL_HAPTIC_MIN { wallHit = true }; b.x = w - b.radius; b.vx = -b.vx * RESTITUTION; b.vy *= WALL_FRICTION }
            if b.y < b.radius { if b.vy < -WALL_HAPTIC_MIN { wallHit = true }; b.y = b.radius; b.vy = -b.vy * RESTITUTION; b.vx *= WALL_FRICTION }
            else if b.y > floor - b.radius {
                let impactVy = b.vy   // 反弹前的入射速度
                if impactVy > WALL_HAPTIC_MIN { wallHit = true }
                b.y = floor - b.radius; b.vy = -b.vy * RESTITUTION; b.vx *= WALL_FRICTION
                // 只有真正「砸」到地板（入射速度够大）才产生滚动自旋；
                // 静止压在地板上时重力每帧都会触发本分支，若无门槛会永久续命导致打转。
                if impactVy > IMPACT_SPIN_MIN { b.va += b.vx * 0.6 }
            }
            if abs(b.vy) < abs(bay) * dt * 1.5 { b.vy = 0 }
            if abs(b.vx) < abs(bax) * dt * 1.5 { b.vx = 0 }
            if abs(b.va) < ANG_SLEEP { b.va = 0 }   // 角速度休眠，避免落地后无限打转
            if b.vx != 0 || b.vy != 0 || b.va != 0 { moving = true }
        }
        // 节流：多张贴纸同帧砸边、或同一贴纸连续帧多次接触，都只触发一次震动。
        if wallHit, lastTime - lastHapticTime > HAPTIC_DEBOUNCE {
            lastHapticTime = lastTime
            onWallHit()
        }

        // 贴纸之间的圆形碰撞（位置分离 + 法向冲量）
        for _ in 0..<COLLISION_ITERS {
            for i in 0..<arr.count {
                for j in (i + 1)..<arr.count {
                    let a = arr[i], c = arr[j]
                    if a.held && c.held { continue }   // 两个都被按住：互不影响
                    let dx = c.x - a.x, dy = c.y - a.y
                    let d2 = dx * dx + dy * dy
                    let minD = a.radius + c.radius
                    if d2 >= minD * minD || d2 == 0 { continue }
                    let dist = d2.squareRoot()
                    let nx = dx / dist, ny = dy / dist
                    let overlap = minD - dist
                    // 被按住的一方视为不可推动：分离量全部由可动的一方承担
                    let aMov = !a.held, cMov = !c.held
                    if aMov && cMov {
                        let total = a.radius + c.radius
                        let aShare = c.radius / total, cShare = a.radius / total
                        a.x -= nx * overlap * aShare; a.y -= ny * overlap * aShare
                        c.x += nx * overlap * cShare; c.y += ny * overlap * cShare
                    } else if aMov {
                        a.x -= nx * overlap; a.y -= ny * overlap
                    } else {
                        c.x += nx * overlap; c.y += ny * overlap
                    }
                    let vn = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny
                    if vn < 0 {
                        let aInv = aMov ? 1 / a.radius : 0
                        let cInv = cMov ? 1 / c.radius : 0
                        if aInv + cInv > 0 {
                            let imp = (-(1 + RESTITUTION) * vn) / (aInv + cInv)
                            a.vx -= imp * aInv * nx; a.vy -= imp * aInv * ny
                            c.vx += imp * cInv * nx; c.vy += imp * cInv * ny
                        }
                    }
                }
            }
            for b in arr {
                b.x = min(max(b.x, b.radius), w - b.radius)
                b.y = min(max(b.y, b.radius), floor - b.radius)
            }
        }
        return moving
    }

    private func publish() {
        frameStore.frames = order.compactMap { id in
            guard let b = bodies[id] else { return nil }
            return BodyFrame(id: id, x: b.x, y: b.y, angle: b.angle, scale: b.size)
        }
    }
}

/// 量出底栏 Tab 栏顶边的屏幕 y 坐标，作为贴纸的碰撞地板。沙盒视图自身 `ignoresSafeArea`
/// 已退出了 Tab 栏安全区，`geo.safeAreaInsets.bottom` 在那里恒为 0，量不到栏，所以直接问
/// UIKit：找出原生 TabView 背后的 `UITabBar`（含 iOS 26 悬浮玻璃栏），取它顶边。
/// 找不到栏时退回 home indicator 安全区上沿。返回 0 表示拿不到，调用方用整屏兜底。
@MainActor
enum TabBarMetrics {
    static func floorY() -> CGFloat {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return 0 }
        let screenH = window.bounds.height
        if let bar = firstTabBar(in: window) {
            let f = bar.convert(bar.bounds, to: window)
            if f.height > 0, f.minY > 0, f.minY < screenH { return f.minY }
        }
        return screenH - window.safeAreaInsets.bottom
    }

    private static func firstTabBar(in view: UIView) -> UITabBar? {
        if let tb = view as? UITabBar { return tb }
        for sub in view.subviews {
            if let found = firstTabBar(in: sub) { return found }
        }
        return nil
    }
}

/// 预渲染「贴纸 + 投影」位图缓存。投影（高斯模糊）只在首次按 id 烘焙一次，之后每帧只是把
/// 这张位图按位置/旋转/缩放画出去——**不再逐帧做模糊**。逐帧高斯模糊（原 Canvas 的
/// `addFilter(.shadow)`）在下落时所有贴纸同时重画会吃满 GPU 导致掉帧，是「一卡一卡」的主因。
/// 按 id 缓存，并记住烘焙时用的那张原图——用户旋转贴纸后图片会被换成新实例，
/// 靠这个身份比对让缓存失效，避免沙盒里还画着旋转前的旧位图。
@MainActor
final class SpriteCache {
    private var cache: [UUID: (base: UIImage, sprite: UIImage)] = [:]

    /// scale=1 时贴纸内容方框边长（pt），与原 STICKER 一致。
    static let content: CGFloat = STICKER
    /// 四周给投影（模糊半径 + 向下偏移）留的余量。
    static let pad: CGFloat = 12
    /// 整张位图边长（含投影留白）。
    static var side: CGFloat { content + pad * 2 }

    func sprite(id: UUID, base: UIImage) -> UIImage {
        if let c = cache[id], c.base === base { return c.sprite }
        let s = Self.bake(base)
        cache[id] = (base, s)
        return s
    }

    /// 丢弃已不在场的贴纸位图，避免缓存无限增长。
    func prune(_ ids: Set<UUID>) {
        if cache.count > ids.count { cache = cache.filter { ids.contains($0.key) } }
    }

    private static func bake(_ img: UIImage) -> UIImage {
        let side = Self.side
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt)
        // 等比放入中心 content 方框（替代原 .scaledToFit）
        let src = img.size
        let scale = (src.width > 0 && src.height > 0) ? min(content / src.width, content / src.height) : 1
        let w = src.width * scale, h = src.height * scale
        let rect = CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
        return renderer.image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 6), blur: 8,
                                    color: UIColor.black.withAlphaComponent(0.5).cgColor)
            img.draw(in: rect)
        }
    }
}

struct StickerSandboxView: View {
    /// 引擎本身**不**被观察（无 `@ObservedObject`）——它不再有任何 `@Published`，
    /// 这里只用它派发手势回调（抓/拖/放）和读取配置。
    let engine: SandboxEngine
    /// 只观察「每帧位置数据」这一个轻量对象：位置更新只让本视图（Canvas）重绘，
    /// 不会波及持有 `engine` 的上层视图（相机预览树）。见 `SandboxFrameStore`。
    @ObservedObject var frameStore: SandboxFrameStore
    /// 贴纸图片查表（O(1)）：由上层用 photos 预先建好字典传入，避免每帧逐贴纸线性查找。
    let images: [UUID: UIImage]
    /// 双击某张贴纸：把它调到出片卡上展示。
    var onActivate: (UUID) -> Void = { _ in }
    /// 「贴纸 + 投影」预渲染位图缓存（见 `SpriteCache`）。@State 让它跨 body 重算存活。
    @State private var sprites = SpriteCache()
    private let coordSpace = "sandbox"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 绘制层：所有贴纸在单个 Canvas 里一次性画完（一个 Metal pass），不再为每张
                // 贴纸建立独立的 Image 视图。每帧只画**预烘焙好的位图**（含投影），不做逐帧
                // 高斯模糊——这是把下落卡顿降下来的关键。Canvas 不参与命中测试，触摸交给命中层。
                Canvas { ctx, _ in
                    let side0 = SpriteCache.side
                    for f in frameStore.frames {
                        guard let base = images[f.id] else { continue }
                        let resolved = ctx.resolve(Image(uiImage: sprites.sprite(id: f.id, base: base)))
                        let s = side0 * f.scale
                        var layer = ctx
                        layer.translateBy(x: f.x, y: f.y)
                        layer.rotate(by: .degrees(f.angle))
                        layer.draw(resolved, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                    }
                }
                .allowsHitTesting(false)

                // 命中层：每张贴纸一个透明矩形承载手势。空白处没有任何视图，触摸自然穿透到
                // 下层的相机／快门（保持原有穿透行为）。这些是无图无阴影的轻量叶子视图。
                ForEach(frameStore.frames) { f in
                    Color.clear
                        .frame(width: STICKER * f.scale, height: STICKER * f.scale)
                        .contentShape(Rectangle())
                        .position(x: f.x, y: f.y)
                        .gesture(gesture(for: f.id))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: coordSpace)
            .onAppear {
                engine.viewport = geo.size
                refreshFloor()
                // Tab 栏首帧可能还没布局好，稍后再量一次确保拿到栏顶位置。
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    refreshFloor()
                }
            }
            .onChange(of: geo.size) { _, s in engine.viewport = s; refreshFloor() }
            .onChange(of: images.count) { _, _ in sprites.prune(Set(images.keys)) }
        }
        .ignoresSafeArea()
    }

    /// 双击调卡 + 拖动抓放（与原行为一致）；现在挂在透明命中矩形上。双击产生的两次零距离
    /// 拖动只是原地抓放、速度≈0，无副作用，故两手势可并存。
    private func gesture(for id: UUID) -> some Gesture {
        TapGesture(count: 2)
            .onEnded { onActivate(id) }
            .simultaneously(with:
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
                    .onChanged { v in
                        engine.grab(id)
                        engine.dragTo(id, point: v.location)
                    }
                    .onEnded { v in
                        engine.release(id, velocity: CGVector(dx: v.velocity.width,
                                                              dy: v.velocity.height))
                    }
            )
    }

    private func refreshFloor() {
        engine.floorY = TabBarMetrics.floorY()
    }
}
