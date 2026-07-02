# 部署指南（Docker → AWS）

本项目是 Next.js 14 应用，含服务端 API 路由 `/api/generate`（调用豆包，需要 `ARK_API_KEY`），
因此必须运行 Node 服务，**不能**用纯静态托管（S3 / CloudFront-only）。

构建产物用 Next.js [`output: "standalone"`](https://nextjs.org/docs/app/api-reference/next-config-js/output)，
镜像约 **267 MB**，以非 root 用户运行，监听 `0.0.0.0:3000`。

> ⚠️ **安全提醒**：`/api/generate` 无鉴权，公网暴露后任何人都能用你的 `ARK_API_KEY` 生成图片、产生费用。
> 内置的按 IP 限流依赖 `X-Forwarded-For`，实例直接暴露时可被伪造该头绕过。
> 生产部署请放在会写入真实客户端 IP 的可信代理 / 负载均衡之后，或加鉴权 / 全局限额。详见 web `README.md` 的「部署前必读」。

---

## 本地构建与运行

```bash
# 构建
docker build -t pai-li-tie:latest .

# 运行（通过 --env-file 注入密钥，不要把密钥打进镜像）
docker run -d -p 3000:3000 --env-file .env.local --name pai-li-tie pai-li-tie:latest
```

或用 compose：

```bash
docker compose up -d --build
```

打开 <http://localhost:3000> 验证。

### 运行期环境变量

| 变量          | 必填 | 说明                                          |
| ------------- | ---- | --------------------------------------------- |
| `ARK_API_KEY` | 是   | 豆包 (Doubao) API Key，服务端 `/api/generate` 调用所需 |
| `PORT`        | 否   | 监听端口，默认 `3000`                          |

---

## 推送镜像到 AWS ECR

下面假设 region = `cn-north-1`（北京）或 `us-east-1`，按需替换。

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REPO=pai-li-tie

# 1. 创建仓库（只需一次）
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# 2. 登录 ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 3. 为 AWS 平台构建（Fargate / App Runner 为 linux/amd64；
#    在 Apple Silicon 上务必带 --platform，否则镜像架构不匹配）
docker build --platform linux/amd64 -t $ECR_REPO:latest .

# 4. 打 tag 并推送
docker tag $ECR_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:latest
```

---

## 部署方式（择一）

### 方式 A：App Runner（最省心，推荐）

全托管，自动 HTTPS、自动扩缩容，最适合这种「单容器 Web 服务」。

1. 控制台 → App Runner → Create service → Container registry → 选上面推送的 ECR 镜像。
2. Port 填 `3000`。
3. Environment variables 添加 `ARK_API_KEY`（建议用 Secrets Manager 引用，而非明文）。
4. 创建后获得一个 `*.awsapprunner.com` HTTPS 域名，直接可用。

> 注意：豆包图像生成是同步等待的长请求，App Runner 默认请求超时较宽松，
> 若遇到超时可适当调大 health-check / request timeout。

### 方式 B：ECS Fargate（需要更多控制时）

1. 建 ECS Cluster（Fargate）。
2. Task definition：容器镜像填 ECR 地址，端口 `3000`，环境变量注入 `ARK_API_KEY`
   （用 `secrets` 字段从 Secrets Manager 注入）。
3. Service：放在私有子网，前面挂 ALB，target group 指向 `3000`，
   health check path 填 `/`。
4. ALB 上配 ACM 证书启用 HTTPS。

### 方式 C：EC2（最简单粗暴）

```bash
# EC2 上装好 docker 后
aws ecr get-login-password --region $AWS_REGION | docker login ...   # 同上
docker pull <account>.dkr.ecr.<region>.amazonaws.com/pai-li-tie:latest
docker run -d -p 80:3000 --restart unless-stopped \
  -e ARK_API_KEY=xxx <account>.dkr.ecr.<region>.amazonaws.com/pai-li-tie:latest
```

安全组放行 80/443，建议前面套一层 Nginx / Caddy 做 HTTPS。

---

## ⚠️ 摄像头、陀螺仪与 HTTPS

前端用 `getUserMedia` 调摄像头、用 `deviceorientation` 读陀螺仪（贴纸随手机倾斜摆动），
这两类能力浏览器都**只在 HTTPS（或 localhost）下允许**——用 `http://<IP>` 访问时，
摄像头被拦截、陀螺仪事件根本不派发（iOS 还需用户手势授权），贴纸便只会笔直下落、不随倾斜移动。
上述 App Runner / ALB+ACM / Caddy 任一方案都能提供 HTTPS，部署后用 HTTPS 域名访问即可。

## 🔐 密钥安全

- 绝不要把 `ARK_API_KEY` 写进 Dockerfile 或镜像层。
- 生产环境用 **AWS Secrets Manager** 注入，`.env.local` 仅用于本地。
- `.dockerignore` 已排除 `.env*`，密钥不会进镜像。
