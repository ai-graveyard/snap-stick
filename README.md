# 拍立贴 · SnapStick

> 对准、按下快门，把此刻冲印成一张专属贴纸。

拍立贴是一个模拟拍立得（Polaroid）体验的贴纸相机项目，同一个产品概念下有两套独立实现：一个 Next.js 网页版，一个原生 SwiftUI iOS 版。本仓库把两者合并管理，各自作为子目录、可独立构建运行。

## 目录结构

```
snap-stick/
├── web/   # Next.js 网页版（AI 生成卡通贴纸）
└── ios/   # 原生 SwiftUI iOS 版（SnapStick，端上 Vision 抠图）
```

## [web/](web/) —— 网页版

纯前端 + 轻量服务端代理，无需登录。用摄像头拍一张照片，相纸像真拍立得一样吐出、显影，最终显影出的是后台调用豆包（Volcengine Ark）图生图模型生成的卡通贴纸，抠掉背景后弹跳掉进屏幕底部的收集托盘。

详见 [web/README.md](web/README.md)。

```bash
cd web
pnpm install
cp .env.example .env.local   # 填入 ARK_API_KEY
pnpm dev
```

## [ios/](ios/) —— iOS 版

原生 SwiftUI App，最初是网页版的移植，后改为默认完全端上处理：用 Vision 的前景抠图 API 提取拍摄主体（无需联网），加白色模切边，冲印动画（静置约 5 秒或摇晃手机瞬间显影），最后贴纸落入一个陀螺仪驱动的物理沙盘里滑动碰撞。历史记录纯本地存储，无需账号。也可自带豆包（火山方舟）Key 开启可选的「AI 卡通贴纸」：拍照先经 seedream 图生图变成冰箱贴风格卡通卡片再抠图，任何失败自动回退纯本地流程。

详见 [ios/README.md](ios/README.md)（架构、开发约束等更详细的说明见 [ios/AGENTS.md](ios/AGENTS.md)）。

```bash
cd ios
xcodebuild -project SnapStick.xcodeproj -scheme SnapStick \
  -destination 'generic/platform=iOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

需要在真机上运行以测试摄像头与陀螺仪相关功能。

## 两个版本的差异

| | web | ios |
|---|---|---|
| 抠图/贴纸生成 | 服务端调用豆包图生图模型 | 端上 Vision 前景抠图（默认，无需联网）；可选自带豆包 Key 的 AI 卡通贴纸 |
| 显影动画 | 固定时长 | 静置约 5 秒 / 摇一摇加速至约 1 秒 |
| 落地效果 | 弹跳掉入底部收集托盘 | 陀螺仪驱动的物理沙盘 |
| 数据存储 | 浏览器 IndexedDB | 设备本地文件 + JSON 索引，带 30 天回收站 |
| 账号/登录 | 无 | 无 |

## License

[MIT](LICENSE)
