# 拍立贴 · SnapStick

> 对准、按下快门，让 AI 把此刻冲印成一张专属贴纸。

拍立贴是一个模拟拍立得（Polaroid）相机的网页应用。用户用摄像头「拍」一张照片，相纸会像真的拍立得一样从机身底部吐出、慢慢显影 —— 但最终显影出来的不是原始照片，而是一张由 AI 生成的**卡通贴纸**（die-cut sticker 风格）。贴纸还会被**抠掉背景**变成一张单独的模切贴纸，像一个有弹性的实体小物件一样从高空**弹跳掉落进屏幕底部的收集托盘**，一张一张攒成你的收藏。

整个体验以手机为主、移动端优先，纯前端 + 一个轻量的服务端代理，无需登录，照片只存在你自己的浏览器里。

---

## ✨ 核心功能

- **📷 拟物拍立得相机** —— 全屏暗色摄影棚背景中渲染一台拍立得相机，镜头里是摄像头实时画面，配经典彩虹条与红色快门按钮。
- **⚡ 快门反馈** —— 按下快门时有白闪 + 快门声，出纸时有马达声（均由 Web Audio 实时合成，无需音频素材）。
- **🎞️ 出纸 / 显影动画** —— 拍照后相机整体上移、相纸从底部出纸口吐出，先是带扫描线的「空白药膜」，等 AI 返回后图片从模糊变清晰渐渐显影。
- **🤖 AI 贴纸生成** —— 后台并行调用豆包 `doubao-seedream-5-0-260128` 图生图模型，把照片主体转成可爱卡通贴纸。生成与动画并行，互不阻塞。
- **✂️ 自动抠图** —— 纯前端 canvas 把白底抠掉（四边洪水填充，保留主体内部白色细节），裁切贴合主体并补一圈白色模切边，得到一张透明背景的单独贴纸。
- **🎈 弹跳收集** —— 显影完成后，单独贴纸从高空带挤压回弹掉进屏幕底部的收集托盘，横向陈列、各带随机倾角，营造收集小物件的把玩感；点击可回看。
- **🗂️ 历史记录** —— 所有作品存在浏览器 IndexedDB，左侧抽屉以网格展示，点击可回看，可一键清空，无数量上限。
- **💾 保存到本地** —— 一键把最终贴纸下载为 PNG。
- **📱 移动端适配** —— 优先后置摄像头、安全区适配、禁用橡皮筋滚动与双击缩放；桌面端支持空格键拍照。
- **🧪 Demo 模式** —— 访问 `?demo=1` 时用合成动画画面代替摄像头，方便在无摄像头/无权限的环境演示与调试动画。

---

## 🛠️ 技术栈

| 分类 | 选型 |
|------|------|
| 框架 | Next.js 14（App Router） |
| 语言 | TypeScript |
| UI | React 18 + Tailwind CSS 3 |
| 动画 | Framer Motion |
| 摄像头 | `getUserMedia` + Canvas 截帧 |
| 抠图 | Canvas 洪水填充去背景（纯前端，无额外服务） |
| 本地存储 | IndexedDB |
| AI 模型 | 豆包 `doubao-seedream-5-0-260128`（火山引擎方舟 / Volcengine Ark） |
| 服务端代理 | Next.js API Route (`/api/generate`) |

---

## 🚀 快速开始

### 1. 安装依赖

```bash
pnpm install
```

### 2. 配置环境变量

复制模板并填入你的火山引擎方舟 API Key：

```bash
cp .env.example .env.local
```

```ini
# .env.local
ARK_API_KEY=你的_ark_api_key
```

> API Key 获取地址：<https://console.volcengine.com/ark>
> `ARK_API_KEY` 只在服务端（API Route）读取，不会暴露到前端。

### 3. 启动开发服务器

```bash
pnpm dev
```

打开 <http://localhost:3000> 即可使用。

> ⚠️ 浏览器只在**安全上下文**（HTTPS 或 `localhost`）下允许访问摄像头，
> **陀螺仪/方向传感器（`deviceorientation`）同样如此**——否则贴纸不会随手机倾斜摆动。
> 若要用手机在局域网内访问，开发服务器已绑定 `0.0.0.0`（`pnpm dev`），
> 但通过局域网 IP（`http://…`）访问时摄像头与陀螺仪都会被浏览器拦截，需要 HTTPS 才能调用。
> iOS 还需在首次点击时弹窗授权「运动与方向」。可先用 `?demo=1` 体验动画。

### 其他脚本

```bash
pnpm build   # 生产构建
pnpm start   # 启动生产服务器（绑定 0.0.0.0）
pnpm lint    # ESLint 检查
```

### 🐳 Docker / 部署

```bash
docker build -t pai-li-tie .
docker run -d -p 3000:3000 --env-file .env.local pai-li-tie
# 或： docker compose up -d --build
```

镜像基于 Next.js `standalone` 产物（约 267 MB，非 root 运行）。
推送到 AWS ECR 并用 App Runner / ECS Fargate / EC2 部署的完整步骤见 [docs/DEPLOY.md](docs/DEPLOY.md)。

> ⚠️ **部署前必读 —— 这个接口在花你的钱**：`/api/generate` **没有鉴权**，任何能访问到你部署实例的人都会用**你的** `ARK_API_KEY` 生成图片、产生费用。内置的按 IP 限流（5 次 / 10 分钟）只是基础防刷，且依赖 `X-Forwarded-For`：若实例**直接对公网暴露**（前面没有会重写该头的可信代理 / 负载均衡），伪造该头即可绕过。公开部署时请至少做到其一：放在会写入真实客户端 IP 的可信代理之后、加一层自建鉴权、或换成 Redis 等共享存储做全局限额（见 [`src/lib/rateLimit.ts`](src/lib/rateLimit.ts) 注释）。仅本地或可信小范围使用时可忽略。

---

## 📂 项目结构

```
pai-li-tie/
├── src/
│   ├── app/
│   │   ├── layout.tsx            # 根布局、元信息、视口配置
│   │   ├── page.tsx             # 主页面：状态机、摄像头、拍照、AI 调用编排
│   │   ├── globals.css          # 全局样式 + 拍立得相纸/扫描线等自定义样式
│   │   └── api/
│   │       └── generate/
│   │           └── route.ts     # 豆包 API 服务端代理（读 ARK_API_KEY，下载图片转 base64）
│   ├── components/
│   │   ├── PolaroidStudio.tsx   # 拍立得相机 + 出纸/显影动画 + 音效 + 最终展示
│   │   ├── StickerTray.tsx      # 底部收集托盘 + 贴纸弹跳掉落动画
│   │   └── Sidebar.tsx          # 历史记录抽屉
│   ├── hooks/
│   │   └── usePhotoHistory.ts   # IndexedDB 读写封装
│   ├── lib/
│   │   ├── api.ts               # 前端调用 /api/generate 的封装
│   │   └── cutout.ts            # Canvas 抠图（去背景 + 裁切 + 白色模切边）
│   └── types/
│       └── index.ts             # PhotoRecord 等类型定义
├── docs/
│   └── PRD.md                   # 产品需求文档
├── .env.example                 # 环境变量模板
├── next.config.js               # Next.js 配置
├── tailwind.config.ts           # Tailwind 配置（含动画扩展）
└── tsconfig.json
```

---

## 🔄 拍照流程

应用通过一个简单的状态机驱动（`idle → ejecting → developing → done`）：

```
[idle] 取景中
   │  按下快门（或空格键）
   ▼
白闪 + 快门声 → Canvas 居中正方形截取当前帧
   │
   ├─ 相机上移、相纸从出纸口吐出（约 2s，马达声）→ 相纸显示空白药膜 + 扫描线「冲印中」
   └─ 并行：POST /api/generate → 豆包生成贴纸（约 20~35s，前端 60s 超时）→ canvas 抠图
   │
   ▼  出纸动画完成 且 AI 返回（两者都就绪）
[developing] 贴纸从模糊/暗 渐变到清晰（约 3s）
   │
   ▼  显影完成：单独贴纸从高空弹跳掉落进底部收集托盘
[done] 显示日期 + [重拍] / [保存] 按钮，托盘里多出一张收藏
```

- AI 生成失败时保留原始照片，并提示「贴纸生成失败，已保留原图」。
- 点击历史记录会跳过动画，直接展示已完成的贴纸。

---

## 🔐 隐私说明

- 无需登录，纯匿名使用。
- 原始照片与生成的贴纸都只保存在浏览器本地（IndexedDB），不上传到任何服务器持久化。
- 拍照图片仅在生成贴纸时经服务端代理转发给豆包 API。

---

## 📄 许可

本项目仅用于学习与演示。
