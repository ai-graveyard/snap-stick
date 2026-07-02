# 贴纸分类需求文档

## 背景

SnapStick 的历史记录需要比“全部贴纸”更有用的浏览方式。面向小红书式生活方式场景，分类应该优先帮助用户回看和整理日常内容，而不是直接暴露 Apple Vision 的技术标签。

本需求采用“用户友好的一级分类 + Apple Vision 原始识别标签”的双层结构：

- 一级分类用于展示、筛选和用户手动修改。
- Vision 原始识别标签作为二级标签保存，用于后续业务细分、模板推荐或重新映射。

## 目标

1. 拍照后自动推荐一个一级分类。
2. 用户可以在贴纸详情页修改一级分类。
3. 保留 Apple Vision 的 Top1 原始识别标签、置信度和候选标签 Top 5。
4. 历史记录按一级分类筛选，不直接用原始识别标签筛选。
5. 旧数据兼容：旧版 `category` 字段迁移为 `rawVisionLabel`，并映射出一级分类。

## 一级分类

首版使用 10 个稳定分类：

| ID | 中文 | English | 典型内容 |
| --- | --- | --- | --- |
| `food` | 美食 | Food | 正餐、甜点、零食、烘焙 |
| `drink` | 饮品 | Drinks | 咖啡、茶、奶茶、果汁、酒水、杯子 |
| `plant` | 花草 | Plants | 鲜花、绿植、盆栽、花束 |
| `pet` | 宠物 | Pets | 猫、狗、鸟、兔子等动物 |
| `fashion` | 穿搭 | Outfits | 衣服、鞋、包、帽子、饰品 |
| `beauty` | 美妆 | Beauty | 口红、香水、美甲、化妆品 |
| `home` | 家居 | Home | 家具、灯、香薰、桌面小物 |
| `handmade` | 手作 | Handmade | 手账、玩具、手办、串珠、DIY |
| `travel` | 出行 | Travel | 交通工具、街景、露营、海边、地标 |
| `other` | 其他 | Other | 未能明确归类的内容 |

## 数据结构

`PhotoRecord` 新增以下字段：

```swift
var primaryCategoryID: String?
var rawVisionLabel: String?
var rawVisionConfidence: Float?
var visionCandidates: [VisionCandidate]
var categorySource: CategorySource?
```

`VisionCandidate`：

```swift
struct VisionCandidate: Codable, Equatable, Identifiable {
    let label: String
    let confidence: Float
}
```

`CategorySource`：

```swift
enum CategorySource: String, Codable {
    case vision
    case user
}
```

示例：

```json
{
  "primaryCategoryID": "drink",
  "rawVisionLabel": "coffee",
  "rawVisionConfidence": 0.82,
  "visionCandidates": [
    { "label": "coffee", "confidence": 0.82 },
    { "label": "cup", "confidence": 0.63 },
    { "label": "beverage", "confidence": 0.51 }
  ],
  "categorySource": "vision"
}
```

如果用户把一级分类从“饮品”改成“美食”：

```json
{
  "primaryCategoryID": "food",
  "rawVisionLabel": "coffee",
  "rawVisionConfidence": 0.82,
  "categorySource": "user"
}
```

注意：用户修改只覆盖 `primaryCategoryID` 与 `categorySource`，不得覆盖 `rawVisionLabel` 和 `visionCandidates`。

## 识别流程

1. 拍照后先运行 `VisionCutout.cutout`。
2. 抠图成功时，对 `cutout` 运行 `SubjectClassifier.classify`。
3. 抠图失败时，保留原图并对 `original` 运行分类，尽量仍给出推荐分类。
4. `SubjectClassifier` 同时使用：
   - `VNClassifyImageRequest`：通用 Apple Vision 图像分类。
   - `VNRecognizeAnimalsRequest`：专门识别动物，提高宠物分类稳定性。
5. 从 Vision 候选结果中保存 Top 5。
6. 优先选择能命中本地映射表的高置信度标签作为 `rawVisionLabel`；动物识别高置信度命中时直接归入 `pet`。
7. 无结果时保持未分类。

## 交互

### 出片卡

- 右下角显示推荐的一级分类。
- 不在出片卡上直接修改分类，避免干扰拍照主流程。

### 贴纸详情页

- 显示当前一级分类。
- 提供分类菜单，允许用户改为任意一级分类。
- 显示 Vision 原始识别标签与置信度。
- 显示候选标签 Top 5 的可读名称。

### 历史记录

- 分类筛选条按一级分类聚合。
- 未识别的贴纸进入“未分类”筛选。
- 行标题优先显示一级分类；无分类时显示“贴纸快照”。

## 持久化与兼容

`PhotoStore.Meta` 继续读取旧版 `category` 字段：

- `category` -> `rawVisionLabel`
- 按映射表推导 `primaryCategoryID`
- `categorySource` 默认为 `vision`
- `visionCandidates` 回填为包含旧标签的单元素数组

新写入的 `index.json` 使用新字段，并保留 `category: nil` 作为兼容占位。

## 后续扩展

1. 用真实拍摄数据调整 `StickerCategory.labelMap`，提高小红书场景命中率。
2. 为 `rawVisionLabel` 做更细的业务规则，例如咖啡模板、猫狗模板、鲜花相纸。
3. 支持按二级标签搜索，但默认 UI 仍以一级分类为主。
4. 将 `visionCandidates` 用于历史数据重映射，避免重新跑 Vision。
