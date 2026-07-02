const WINDOW_MS = 10 * 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 5;

// 单容器内单进程内存计数：够拦截脚本刷量，重启即清零；
// 多实例横向扩容后限流会退化为「按实例」而非全局精确，届时应换成 Upstash/Redis 之类的共享存储
const hits = new Map<string, { count: number; resetAt: number }>();

function sweepExpired(now: number) {
  if (hits.size < 10_000) return;
  hits.forEach((entry, ip) => {
    if (now >= entry.resetAt) hits.delete(ip);
  });
}

export function checkRateLimit(ip: string): { allowed: boolean; retryAfterSeconds?: number } {
  const now = Date.now();
  sweepExpired(now);

  const entry = hits.get(ip);
  if (!entry || now >= entry.resetAt) {
    hits.set(ip, { count: 1, resetAt: now + WINDOW_MS });
    return { allowed: true };
  }

  if (entry.count >= MAX_REQUESTS_PER_WINDOW) {
    return { allowed: false, retryAfterSeconds: Math.ceil((entry.resetAt - now) / 1000) };
  }

  entry.count += 1;
  return { allowed: true };
}

export function getClientIp(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return request.headers.get("x-real-ip") || "unknown";
}
