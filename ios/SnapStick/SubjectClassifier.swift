//
//  SubjectClassifier.swift
//  SnapStick
//
//  用 Apple Vision 的内置图像分类与动物识别，为贴纸推荐一个用户友好的一级分类，
//  同时保留 Vision 原始 identifier 作为二级标签，供后续业务继续细分。
//  全流程纯设备端、离线、无网络与 API Key。
//

import SwiftUI
import UIKit
import Vision

/// 一条 Vision 原始候选标签。`label` 保持 Apple 返回的技术 identifier，不直接展示给用户。
struct VisionCandidate: Codable, Equatable, Identifiable {
    let label: String
    let confidence: Float

    var id: String { label }
}

/// 一级分类来自用户选择还是 Vision 推荐。
enum CategorySource: String, Codable {
    case vision
    case user
}

/// 给用户看的一级分类。rawValue 是稳定持久化 id，不随中英文展示名变化。
enum StickerCategory: String, CaseIterable, Codable, Identifiable {
    case food
    case drink
    case plant
    case pet
    case fashion
    case beauty
    case home
    case handmade
    case travel
    case other

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .food: "美食"
        case .drink: "饮品"
        case .plant: "花草"
        case .pet: "宠物"
        case .fashion: "穿搭"
        case .beauty: "美妆"
        case .home: "家居"
        case .handmade: "手作"
        case .travel: "出行"
        case .other: "其他"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .drink: "cup.and.saucer.fill"
        case .plant: "leaf.fill"
        case .pet: "pawprint.fill"
        case .fashion: "tshirt.fill"
        case .beauty: "sparkles"
        case .home: "house.fill"
        case .handmade: "paintpalette.fill"
        case .travel: "map.fill"
        case .other: "tag.fill"
        }
    }

    static func fromID(_ id: String?) -> StickerCategory? {
        guard let id else { return nil }
        return StickerCategory(rawValue: id)
    }

    /// 把 Apple Vision identifier 归并到 SnapStick 的一级分类。
    nonisolated static func category(for rawLabel: String) -> StickerCategory {
        let key = normalize(rawLabel)
        return labelMap[key] ?? .other
    }

    /// 是否命中除「其他」外的明确业务分类。
    nonisolated static func isMapped(_ rawLabel: String) -> Bool {
        labelMap[normalize(rawLabel)] != nil
    }

    nonisolated private static func normalize(_ label: String) -> String {
        label
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// 映射表偏向 Apple 通用分类 label，同时补充常见同义写法。
    private nonisolated static let labelMap: [String: StickerCategory] = [
        // 美食
        "food": .food, "fruit": .food, "vegetable": .food, "dessert": .food,
        "baked_goods": .food, "bread": .food, "cake": .food, "cookie": .food,
        "candy": .food, "chocolate": .food, "snack": .food, "fast_food": .food,
        "pizza": .food, "hamburger": .food, "sandwich": .food, "sushi": .food,
        "noodle": .food, "noodles": .food, "rice": .food, "egg": .food,
        "meat": .food, "seafood": .food, "cheese": .food, "ice_cream": .food,
        "hotdog": .food, "hot_dog": .food, "dumpling": .food, "salad": .food,
        "pasta": .food, "steak": .food, "soup": .food,

        // 饮品
        "beverage": .drink, "drink": .drink, "coffee": .drink, "espresso": .drink,
        "tea": .drink, "juice": .drink, "wine": .drink, "beer": .drink,
        "cocktail": .drink, "soft_drink": .drink, "water": .drink,
        "bottle": .drink, "cup": .drink, "mug": .drink, "glass": .drink,
        "teapot": .drink, "coffee_cup": .drink, "wine_glass": .drink,

        // 花草
        "plant": .plant, "flower": .plant, "tree": .plant, "leaf": .plant,
        "succulent": .plant, "houseplant": .plant, "rose": .plant,
        "daisy": .plant, "bouquet": .plant, "vase": .plant,

        // 宠物 / 动物
        "animal": .pet, "dog": .pet, "cat": .pet, "bird": .pet, "fish": .pet,
        "rabbit": .pet, "horse": .pet, "turtle": .pet, "hamster": .pet,
        "guinea_pig": .pet, "parrot": .pet, "kitten": .pet, "puppy": .pet,

        // 穿搭
        "clothing": .fashion, "shoe": .fashion, "footwear": .fashion,
        "hat": .fashion, "bag": .fashion, "handbag": .fashion,
        "backpack": .fashion, "glasses": .fashion, "sunglasses": .fashion,
        "jewelry": .fashion, "watch": .fashion, "scarf": .fashion,
        "dress": .fashion, "skirt": .fashion, "shirt": .fashion,
        "tshirt": .fashion, "t_shirt": .fashion,

        // 美妆
        "cosmetics": .beauty, "makeup": .beauty, "lipstick": .beauty,
        "perfume": .beauty, "nail_polish": .beauty, "mirror": .beauty,
        "comb": .beauty, "hairbrush": .beauty,

        // 家居
        "furniture": .home, "chair": .home, "table": .home, "lamp": .home,
        "candle": .home, "clock": .home, "book": .home, "box": .home,
        "pillow": .home, "sofa": .home, "plant_pot": .home,

        // 手作 / 玩具
        "toy": .handmade, "teddy_bear": .handmade, "doll": .handmade,
        "art": .handmade, "painting": .handmade, "craft": .handmade,
        "sticker": .handmade, "bead": .handmade, "bracelet": .handmade,
        "stationery": .handmade, "notebook": .handmade,

        // 出行
        "vehicle": .travel, "car": .travel, "bicycle": .travel,
        "motorcycle": .travel, "airplane": .travel, "boat": .travel,
        "train": .travel, "bus": .travel, "street": .travel, "road": .travel,
        "building": .travel, "landmark": .travel, "mountain": .travel,
        "beach": .travel, "camping": .travel, "tent": .travel
    ]
}

struct SubjectClassification: Equatable {
    let primaryCategory: StickerCategory
    let rawVisionLabel: String
    let rawVisionConfidence: Float
    let candidates: [VisionCandidate]
}

enum SubjectClassifier {
    /// 低于此置信度的标签直接丢弃（Vision 会返回大量极低置信度的长尾标签）。
    private nonisolated static let minConfidence: Float = 0.15
    /// 宠物用专门动物识别请求，阈值略高一点，减少把背景误判成宠物。
    private nonisolated static let animalMinConfidence: Float = 0.30
    /// 只在置信度最高的前若干个里优先挑「映射表里有的」标签，避免拿冷门词当主类。
    private nonisolated static let topK = 6
    private nonisolated static let candidateLimit = 5

    /// 识别主体类别。失败 / 无把握返回 nil；调用方可保留未分类状态。
    nonisolated static func classify(_ image: UIImage) async -> SubjectClassification? {
        await Task.detached(priority: .userInitiated) {
            process(image)
        }.value
    }

    private nonisolated static func process(_ image: UIImage) -> SubjectClassification? {
        guard let cg = image.cgImage else { return nil }

        let animalCandidates = recognizeAnimals(cg)
        let imageCandidates = classifyImage(cg)
        let merged = merge(animalCandidates + imageCandidates)
        guard !merged.isEmpty else { return nil }

        let topAnimal = animalCandidates.first { $0.confidence >= animalMinConfidence }
        let mapped = imageCandidates.prefix(topK).first { StickerCategory.isMapped($0.label) }
        let picked: VisionCandidate
        let primary: StickerCategory
        if let topAnimal {
            picked = topAnimal
            primary = .pet
        } else {
            picked = mapped ?? imageCandidates.first ?? merged[0]
            primary = StickerCategory.category(for: picked.label)
        }
        return SubjectClassification(primaryCategory: primary,
                                     rawVisionLabel: picked.label,
                                     rawVisionConfidence: picked.confidence,
                                     candidates: Array(merged.prefix(candidateLimit)))
    }

    private nonisolated static func classifyImage(_ cg: CGImage) -> [VisionCandidate] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else { return [] }

        return results
            .filter { $0.confidence >= minConfidence }
            .map { VisionCandidate(label: $0.identifier, confidence: $0.confidence) }
    }

    private nonisolated static func recognizeAnimals(_ cg: CGImage) -> [VisionCandidate] {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else { return [] }

        return results
            .flatMap(\.labels)
            .filter { $0.confidence >= minConfidence }
            .map { VisionCandidate(label: $0.identifier, confidence: $0.confidence) }
            .sorted { $0.confidence > $1.confidence }
    }

    private nonisolated static func merge(_ candidates: [VisionCandidate]) -> [VisionCandidate] {
        var best: [String: VisionCandidate] = [:]
        for candidate in candidates {
            if let existing = best[candidate.label], existing.confidence >= candidate.confidence {
                continue
            }
            best[candidate.label] = candidate
        }
        return best.values.sorted { $0.confidence > $1.confidence }
    }
}

/// Vision 分类标识符 → 展示名（中 / 英）。表里没有的标识符回落到 humanized identifier。
enum SubjectCategory {
    /// identifier → (中文, English)。覆盖常见主体；长尾交给 humanize 兜底。
    private nonisolated static let names: [String: (zh: String, en: String)] = [
        // 食物
        "food": ("食物", "Food"),
        "fruit": ("水果", "Fruit"),
        "vegetable": ("蔬菜", "Vegetable"),
        "dessert": ("甜点", "Dessert"),
        "baked_goods": ("烘焙", "Baked Goods"),
        "bread": ("面包", "Bread"),
        "cake": ("蛋糕", "Cake"),
        "cookie": ("饼干", "Cookie"),
        "candy": ("糖果", "Candy"),
        "chocolate": ("巧克力", "Chocolate"),
        "snack": ("零食", "Snack"),
        "fast_food": ("快餐", "Fast Food"),
        "pizza": ("披萨", "Pizza"),
        "hamburger": ("汉堡", "Hamburger"),
        "sandwich": ("三明治", "Sandwich"),
        "sushi": ("寿司", "Sushi"),
        "noodle": ("面条", "Noodles"),
        "noodles": ("面条", "Noodles"),
        "rice": ("米饭", "Rice"),
        "egg": ("鸡蛋", "Egg"),
        "meat": ("肉类", "Meat"),
        "seafood": ("海鲜", "Seafood"),
        "cheese": ("奶酪", "Cheese"),
        "ice_cream": ("冰淇淋", "Ice Cream"),
        "hotdog": ("热狗", "Hot Dog"),
        "hot_dog": ("热狗", "Hot Dog"),
        "dumpling": ("饺子", "Dumpling"),
        "salad": ("沙拉", "Salad"),
        "pasta": ("意面", "Pasta"),
        "steak": ("牛排", "Steak"),
        "soup": ("汤", "Soup"),

        // 饮料
        "beverage": ("饮料", "Beverage"),
        "drink": ("饮品", "Drink"),
        "coffee": ("咖啡", "Coffee"),
        "espresso": ("浓缩咖啡", "Espresso"),
        "tea": ("茶", "Tea"),
        "juice": ("果汁", "Juice"),
        "wine": ("葡萄酒", "Wine"),
        "beer": ("啤酒", "Beer"),
        "cocktail": ("鸡尾酒", "Cocktail"),
        "soft_drink": ("汽水", "Soft Drink"),
        "water": ("水", "Water"),
        "bottle": ("瓶子", "Bottle"),
        "cup": ("杯子", "Cup"),
        "mug": ("马克杯", "Mug"),
        "glass": ("玻璃杯", "Glass"),
        "coffee_cup": ("咖啡杯", "Coffee Cup"),
        "wine_glass": ("酒杯", "Wine Glass"),

        // 人 / 动物
        "people": ("人物", "People"),
        "person": ("人物", "Person"),
        "face": ("人脸", "Face"),
        "baby": ("宝宝", "Baby"),
        "animal": ("动物", "Animal"),
        "dog": ("狗", "Dog"),
        "cat": ("猫", "Cat"),
        "bird": ("鸟", "Bird"),
        "fish": ("鱼", "Fish"),
        "rabbit": ("兔子", "Rabbit"),
        "horse": ("马", "Horse"),
        "insect": ("昆虫", "Insect"),
        "butterfly": ("蝴蝶", "Butterfly"),
        "turtle": ("乌龟", "Turtle"),

        // 植物
        "plant": ("植物", "Plant"),
        "flower": ("花", "Flower"),
        "tree": ("树", "Tree"),
        "leaf": ("叶子", "Leaf"),
        "succulent": ("多肉", "Succulent"),
        "houseplant": ("盆栽", "Houseplant"),
        "rose": ("玫瑰", "Rose"),
        "bouquet": ("花束", "Bouquet"),

        // 日用 / 电子 / 家具
        "furniture": ("家具", "Furniture"),
        "chair": ("椅子", "Chair"),
        "table": ("桌子", "Table"),
        "lamp": ("台灯", "Lamp"),
        "electronic_device": ("电子产品", "Electronics"),
        "computer": ("电脑", "Computer"),
        "laptop": ("笔记本电脑", "Laptop"),
        "mobile_phone": ("手机", "Phone"),
        "phone": ("手机", "Phone"),
        "camera": ("相机", "Camera"),
        "headphones": ("耳机", "Headphones"),
        "television": ("电视", "TV"),
        "watch": ("手表", "Watch"),
        "clock": ("时钟", "Clock"),
        "book": ("书", "Book"),
        "toy": ("玩具", "Toy"),
        "teddy_bear": ("玩偶熊", "Teddy Bear"),
        "doll": ("玩偶", "Doll"),
        "musical_instrument": ("乐器", "Instrument"),
        "guitar": ("吉他", "Guitar"),

        // 服饰 / 配件
        "clothing": ("服饰", "Clothing"),
        "shoe": ("鞋", "Shoe"),
        "footwear": ("鞋履", "Footwear"),
        "hat": ("帽子", "Hat"),
        "bag": ("包", "Bag"),
        "handbag": ("手提包", "Handbag"),
        "backpack": ("背包", "Backpack"),
        "glasses": ("眼镜", "Glasses"),
        "sunglasses": ("太阳镜", "Sunglasses"),
        "jewelry": ("首饰", "Jewelry"),

        // 出行
        "vehicle": ("交通工具", "Vehicle"),
        "car": ("汽车", "Car"),
        "bicycle": ("自行车", "Bicycle"),
        "motorcycle": ("摩托车", "Motorcycle"),
        "airplane": ("飞机", "Airplane"),
        "boat": ("船", "Boat"),
        "train": ("火车", "Train"),
        "bus": ("公交车", "Bus"),
        "street": ("街道", "Street"),
        "road": ("道路", "Road"),
        "building": ("建筑", "Building"),
        "landmark": ("地标", "Landmark"),
        "mountain": ("山", "Mountain"),
        "beach": ("海边", "Beach"),
        "camping": ("露营", "Camping"),
        "tent": ("帐篷", "Tent"),

        // 其他常见
        "candle": ("蜡烛", "Candle"),
        "umbrella": ("雨伞", "Umbrella"),
        "key": ("钥匙", "Key"),
        "box": ("盒子", "Box"),
        "art": ("艺术品", "Artwork"),
        "painting": ("画作", "Painting"),
    ]

    /// 展示名：表里命中按界面语言取中 / 英；未命中把标识符 humanize。
    nonisolated static func displayName(_ identifier: String, locale: Locale) -> String {
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if let pair = names[identifier] {
            return isChinese ? pair.zh : pair.en
        }
        return humanize(identifier)
    }

    private nonisolated static func humanize(_ identifier: String) -> String {
        identifier
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
