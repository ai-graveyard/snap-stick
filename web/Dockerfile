# syntax=docker/dockerfile:1.7

ARG NODE_VERSION=22

# ---------- 依赖安装 ----------
FROM node:${NODE_VERSION}-slim AS deps
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# ---------- 构建 ----------
FROM node:${NODE_VERSION}-slim AS builder
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

# ---------- 运行 ----------
FROM node:${NODE_VERSION}-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN groupadd --system --gid 1001 nodejs \
 && useradd --system --uid 1001 --gid nodejs nextjs

# Next.js standalone 产物：server.js + 精简版 node_modules
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# 运行期环境变量（用 `docker run -e` 或 `--env-file` 注入，不要打进镜像）：
#   ARK_API_KEY — 豆包 (Doubao) API Key，服务端 /api/generate 调用所需

USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
