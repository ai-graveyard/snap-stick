//
//  PhotoStore.swift
//  SnapStick
//
//  本地持久化：图片以文件形式存在 Documents/SnapStickPhotos/ 下，
//  元数据（id / 时间 / 是否有抠图）记录在 index.json。对应网页版的 IndexedDB。
//  纯本地、无上传，匹配网页版「照片只存在你自己设备里」的隐私模型。
//

import UIKit
import Combine

@MainActor
final class PhotoStore: ObservableObject {
    /// 在用的贴纸，按拍摄时间倒序（最新在前）
    @Published private(set) var photos: [PhotoRecord] = []
    /// 回收站里的贴纸，按删除时间倒序（最近删的在前）；满 30 天自动清理
    @Published private(set) var trashed: [PhotoRecord] = []

    /// 回收站保留时长：30 天
    static let trashRetention: TimeInterval = 30 * 24 * 3600

    private let dir: URL
    private let indexURL: URL

    /// index.json 里每条记录的元数据
    private struct Meta: Codable {
        let id: UUID
        let timestamp: Date
        let hasCutout: Bool
        /// 相纸样式 id；旧数据缺该字段时解码为 nil，回落默认相纸。
        var paperStyleID: String?
        /// 软删除时间戳；旧数据缺该字段时解码为 nil（= 在用）。
        var deletedAt: Date?
        /// 一级分类 id（用户可改）；旧数据缺该字段时解码为 nil。
        var primaryCategoryID: String?
        /// Vision Top1 原始 identifier，作为二级标签保留。
        var rawVisionLabel: String?
        /// Vision Top1 置信度。
        var rawVisionConfidence: Float?
        /// Vision 候选标签 Top N。
        var visionCandidates: [VisionCandidate]?
        /// 一级分类来源：vision / user。
        var categorySource: CategorySource?
        /// 旧版字段：曾经直接存 Vision 原始标识符。只用于迁移读取，不再写入业务逻辑。
        var category: String?
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("SnapStickPhotos", isDirectory: true)
        indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 读取

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let metas = try? JSONDecoder().decode([Meta].self, from: data) else {
            photos = []
            trashed = []
            return
        }
        let now = Date()
        var active: [PhotoRecord] = []
        var bin: [PhotoRecord] = []
        var didPurge = false
        for m in metas {
            // 懒清理：回收站里满 30 天的，启动时直接抹掉文件，不再载入。
            if let deletedAt = m.deletedAt, now.timeIntervalSince(deletedAt) >= Self.trashRetention {
                removeFiles(m.id)
                didPurge = true
                continue
            }
            guard let original = loadImage(m.id, "original"),
                  let result = loadImage(m.id, "result") else { continue }
            let cutout = m.hasCutout ? loadImage(m.id, "cutout") : nil
            let rawLabel = m.rawVisionLabel ?? m.category
            let primaryID = m.primaryCategoryID
                ?? rawLabel.map { StickerCategory.category(for: $0).id }
            let candidates = m.visionCandidates
                ?? rawLabel.map { [VisionCandidate(label: $0, confidence: m.rawVisionConfidence ?? 0)] }
                ?? []
            let source = m.categorySource ?? (primaryID == nil ? nil : .vision)
            let record = PhotoRecord(id: m.id,
                                     timestamp: m.timestamp,
                                     original: original,
                                     result: result,
                                     cutout: cutout,
                                     paperStyleID: m.paperStyleID ?? PaperCatalog.defaultID,
                                     deletedAt: m.deletedAt,
                                     primaryCategoryID: primaryID,
                                     rawVisionLabel: rawLabel,
                                     rawVisionConfidence: m.rawVisionConfidence,
                                     visionCandidates: candidates,
                                     categorySource: source)
            if m.deletedAt == nil { active.append(record) } else { bin.append(record) }
        }
        active.sort { $0.timestamp > $1.timestamp }
        bin.sort { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        photos = active
        trashed = bin
        // 若启动时清理过过期项，把瘦身后的索引落盘。
        if didPurge { persistIndex() }
    }

    // MARK: - 写入

    func add(_ record: PhotoRecord) {
        writeImage(record.original, record.id, "original", asPNG: false)
        writeImage(record.result, record.id, "result", asPNG: false)
        if let cutout = record.cutout {
            writeImage(cutout, record.id, "cutout", asPNG: true)
        }
        photos.insert(record, at: 0)
        photos.sort { $0.timestamp > $1.timestamp }
        persistIndex()
    }

    /// 切换某条记录的相纸样式（只改外观，不动图片文件）。
    func setPaperStyle(_ id: UUID, styleID: String) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[idx].paperStyleID = styleID
        persistIndex()
    }

    /// 用户手动修改一级分类。Vision 原始标签与候选标签保持不变，供后续业务继续使用。
    func setPrimaryCategory(_ id: UUID, categoryID: String) {
        if let idx = photos.firstIndex(where: { $0.id == id }) {
            photos[idx].primaryCategoryID = categoryID
            photos[idx].categorySource = .user
            persistIndex()
            return
        }
        if let idx = trashed.firstIndex(where: { $0.id == id }) {
            trashed[idx].primaryCategoryID = categoryID
            trashed[idx].categorySource = .user
            persistIndex()
        }
    }

    // MARK: - 回收站（软删除）

    /// 软删除：移入回收站（不删文件），30 天后由 load() 自动清理。
    func delete(_ id: UUID) {
        guard let idx = photos.firstIndex(where: { $0.id == id }) else { return }
        var record = photos.remove(at: idx)
        record.deletedAt = Date()
        trashed.insert(record, at: 0)
        persistIndex()
    }

    /// 把全部在用贴纸移入回收站（历史页「清空所有记录」）。
    func trashAll() {
        guard !photos.isEmpty else { return }
        let now = Date()
        let moved = photos.map { p -> PhotoRecord in var c = p; c.deletedAt = now; return c }
        trashed = moved + trashed
        photos = []
        persistIndex()
    }

    /// 从回收站恢复：清掉删除标记，移回在用列表。
    func restore(_ id: UUID) {
        guard let idx = trashed.firstIndex(where: { $0.id == id }) else { return }
        var record = trashed.remove(at: idx)
        record.deletedAt = nil
        photos.insert(record, at: 0)
        photos.sort { $0.timestamp > $1.timestamp }
        persistIndex()
    }

    /// 彻底删除回收站里的一张（抹掉文件，不可恢复）。
    func purge(_ id: UUID) {
        removeFiles(id)
        trashed.removeAll { $0.id == id }
        persistIndex()
    }

    /// 清空回收站：抹掉其中全部文件，不可恢复。
    func emptyTrash() {
        for p in trashed { removeFiles(p.id) }
        trashed = []
        persistIndex()
    }

    // MARK: - 文件读写

    private func removeFiles(_ id: UUID) {
        for kind in ["original", "result", "cutout"] {
            try? FileManager.default.removeItem(at: fileURL(id, kind, png: kind == "cutout"))
        }
    }

    private func persistIndex() {
        // 在用 + 回收站一起落盘，靠 deletedAt 区分。
        let metas = (photos + trashed).map { Meta(id: $0.id, timestamp: $0.timestamp,
                                                  hasCutout: $0.cutout != nil,
                                                  paperStyleID: $0.paperStyleID,
                                                  deletedAt: $0.deletedAt,
                                                  primaryCategoryID: $0.primaryCategoryID,
                                                  rawVisionLabel: $0.rawVisionLabel,
                                                  rawVisionConfidence: $0.rawVisionConfidence,
                                                  visionCandidates: $0.visionCandidates,
                                                  categorySource: $0.categorySource,
                                                  category: nil) }
        if let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func fileURL(_ id: UUID, _ kind: String, png: Bool) -> URL {
        dir.appendingPathComponent("\(id.uuidString)-\(kind).\(png ? "png" : "jpg")")
    }

    private func loadImage(_ id: UUID, _ kind: String) -> UIImage? {
        let png = kind == "cutout"
        guard let data = try? Data(contentsOf: fileURL(id, kind, png: png)) else { return nil }
        return UIImage(data: data)
    }

    private func writeImage(_ image: UIImage, _ id: UUID, _ kind: String, asPNG: Bool) {
        let data = asPNG ? image.pngData() : image.jpegData(compressionQuality: 0.9)
        guard let data else { return }
        try? data.write(to: fileURL(id, kind, png: asPNG), options: .atomic)
    }
}
