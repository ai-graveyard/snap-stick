//
//  Models.swift
//  SnapStick
//
//  一张「拍立贴」作品：原始照片、AI 生成的白底贴纸、抠图后的单独贴纸。
//

import UIKit

/// 拍照流程的状态机：取景 → 出纸 → 显影 → 完成
enum StudioPhase {
    case idle
    case ejecting
    case developing
    case done
}

/// 一张作品记录。图片以 UIImage 持有，便于即时渲染；持久化由 PhotoStore 负责落盘。
struct PhotoRecord: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    /// 原始拍摄照片
    let original: UIImage
    /// AI 生成的白底贴纸（整张）
    var result: UIImage
    /// 抠掉背景后的单独贴纸（透明 + 白色模切边）；抠图失败时为 nil
    var cutout: UIImage?
    /// 套用的相纸样式 id（见 PaperCatalog）。仅决定外观，可随时切换。
    var paperStyleID: String
    /// 软删除时间戳：nil 表示在用；非 nil 表示已在回收站（满 30 天自动清理）。
    var deletedAt: Date?
    /// 推荐给用户看的一级分类 id（见 StickerCategory）。用户可在详情页修改。
    var primaryCategoryID: String?
    /// Vision 识别出的 Top1 原始标识符（如 "coffee" / "hotdog"）；作为二级标签保留。
    var rawVisionLabel: String?
    /// Top1 原始识别标签的置信度。
    var rawVisionConfidence: Float?
    /// Vision 返回的候选标签 Top N，保留给后续业务重映射或细分。
    var visionCandidates: [VisionCandidate]
    /// 一级分类来源：Vision 推荐或用户手动修改。
    var categorySource: CategorySource?

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         original: UIImage,
         result: UIImage,
         cutout: UIImage? = nil,
         paperStyleID: String = PaperCatalog.defaultID,
         deletedAt: Date? = nil,
         primaryCategoryID: String? = nil,
         rawVisionLabel: String? = nil,
         rawVisionConfidence: Float? = nil,
         visionCandidates: [VisionCandidate] = [],
         categorySource: CategorySource? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.original = original
        self.result = result
        self.cutout = cutout
        self.paperStyleID = paperStyleID
        self.deletedAt = deletedAt
        self.primaryCategoryID = primaryCategoryID
        self.rawVisionLabel = rawVisionLabel
        self.rawVisionConfidence = rawVisionConfidence
        self.visionCandidates = visionCandidates
        self.categorySource = categorySource
    }

    /// 托盘 / 历史里优先展示的图：有抠图用抠图，否则用整张贴纸
    var displayImage: UIImage { cutout ?? result }

    /// 当前套用的相纸样式
    var paperStyle: PaperStyle { PaperCatalog.style(for: paperStyleID) }

    /// 当前一级分类；旧数据 / 未识别时为 nil。
    var primaryCategory: StickerCategory? { StickerCategory.fromID(primaryCategoryID) }

    static func == (lhs: PhotoRecord, rhs: PhotoRecord) -> Bool {
        lhs.id == rhs.id
            && lhs.timestamp == rhs.timestamp
            && lhs.result === rhs.result
            && lhs.cutout === rhs.cutout
            && lhs.paperStyleID == rhs.paperStyleID
            && lhs.deletedAt == rhs.deletedAt
            && lhs.primaryCategoryID == rhs.primaryCategoryID
            && lhs.rawVisionLabel == rhs.rawVisionLabel
            && lhs.rawVisionConfidence == rhs.rawVisionConfidence
            && lhs.visionCandidates == rhs.visionCandidates
            && lhs.categorySource == rhs.categorySource
    }
}
