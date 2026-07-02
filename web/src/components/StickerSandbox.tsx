"use client";

// 贴纸物理沙盒：散落贴纸随设备倾斜滑动 / 堆叠（对应 iOS SandboxEngine + MotionManager）。
// 速度 / 灵敏度从全局 SettingsContext 读取；陀螺仪授权暴露给快门手势默认启用。

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSettings } from "@/contexts/SettingsContext";
import type { PhotoRecord } from "@/types";

interface StickerSandboxProps {
  photos: PhotoRecord[];
  /** 刚拍好、要从相纸里「掉出来」的贴纸 id；其余按已落定处理 */
  freshId: string | null;
  /** 返回相纸窗口当前的屏幕矩形，作为新贴纸掉落的起点（拿不到则用屏幕中上方） */
  getSpawnRect: () => DOMRect | null;
  /** 把方向传感器授权函数暴露给快门等明确用户手势，用于默认启用 */
  registerOrientationRequester?: (requester: (() => void) | null) => void;
}

const STICKER = 78;
const RADIUS = STICKER * 0.42;
const GRAVITY = 2600;
const RESTITUTION = 0.42;
const WALL_FRICTION = 0.78;
const AIR = 0.992;
const ANG_DAMP = 0.94;
const MAX_DT = 1 / 30;
const COLLISION_ITERS = 4;
const SIZE_MIN = 0.82;
const SIZE_MAX = 1.18;
const MOTION_JITTER_MIN = 0.88;
const MOTION_JITTER_MAX = 1.18;

interface Body {
  id: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  angle: number;
  va: number;
  size: number;
  radius: number;
  motionScale: number;
  el: HTMLImageElement | null;
}

interface MotionState {
  supported: boolean;
  secure: boolean;
  permissionApi: boolean;
  permission: string;
}

function rand(min: number, max: number) {
  return min + Math.random() * (max - min);
}

function makePhysicalTraits() {
  const size = rand(SIZE_MIN, SIZE_MAX);
  const sizeMotion = Math.pow(1 / size, 0.85);
  const motionScale = sizeMotion * rand(MOTION_JITTER_MIN, MOTION_JITTER_MAX);
  return { size, radius: RADIUS * size, motionScale };
}

export default function StickerSandbox({
  photos,
  freshId,
  getSpawnRect,
  registerOrientationRequester,
}: StickerSandboxProps) {
  const { t, speed, sensitivity } = useSettings();
  const [ids, setIds] = useState<string[]>([]);
  const [sensorPromptDismissed, setSensorPromptDismissed] = useState(false);
  const [motionState, setMotionState] = useState<MotionState>({
    supported: false,
    secure: false,
    permissionApi: false,
    permission: "unknown",
  });

  const bodies = useRef<Map<string, Body>>(new Map());
  const grav = useRef({ x: 0, y: 1 });
  const viewport = useRef({ w: 0, h: 0 });
  const orientationAttached = useRef(false);
  const speedRef = useRef(speed);
  const sensitivityRef = useRef(sensitivity);

  const byId = useMemo(() => new Map(photos.map((p) => [p.id, p])), [photos]);

  useEffect(() => {
    speedRef.current = speed;
  }, [speed]);
  useEffect(() => {
    sensitivityRef.current = sensitivity;
  }, [sensitivity]);

  const handleOrientation = useCallback((e: DeviceOrientationEvent) => {
    const beta = e.beta ?? 0;
    const gamma = e.gamma ?? 0;
    const angleScale = sensitivityRef.current;
    let gx = Math.sin(((gamma * angleScale) * Math.PI) / 180);
    let gy = Math.sin(((beta * angleScale) * Math.PI) / 180);
    const mag = Math.hypot(gx, gy);
    if (mag > 1) {
      gx /= mag;
      gy /= mag;
    }
    grav.current = { x: gx, y: gy };
  }, []);

  const attachOrientationListener = useCallback(() => {
    if (orientationAttached.current) return;
    window.addEventListener("deviceorientation", handleOrientation);
    orientationAttached.current = true;
  }, [handleOrientation]);

  const requestOrientationAccess = useCallback(() => {
    const DOE = window.DeviceOrientationEvent as
      | (typeof DeviceOrientationEvent & { requestPermission?: () => Promise<PermissionState> })
      | undefined;
    if (!DOE) return;
    if (typeof DOE.requestPermission !== "function") {
      setMotionState((p) => ({ ...p, permission: "not-required" }));
      attachOrientationListener();
      return;
    }
    DOE.requestPermission()
      .then((state) => {
        setMotionState((p) => ({ ...p, permission: state }));
        if (state === "granted") attachOrientationListener();
      })
      .catch(() => setMotionState((p) => ({ ...p, permission: "error" })));
  }, [attachOrientationListener]);

  // 把授权函数暴露给外部（快门手势）默认启用
  useEffect(() => {
    registerOrientationRequester?.(() => requestOrientationAccess());
    return () => registerOrientationRequester?.(null);
  }, [registerOrientationRequester, requestOrientationAccess]);

  // 视口尺寸
  useEffect(() => {
    const measure = () => {
      viewport.current = { w: window.innerWidth, h: window.innerHeight };
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  // 陀螺仪初始化
  useEffect(() => {
    const DOE = window.DeviceOrientationEvent as
      | (typeof DeviceOrientationEvent & { requestPermission?: () => Promise<PermissionState> })
      | undefined;
    const permissionApi = !!DOE?.requestPermission;
    setMotionState({
      supported: !!DOE,
      secure: window.isSecureContext,
      permissionApi,
      permission: permissionApi ? "needs-user-gesture" : "not-required",
    });
    if (!DOE) return;
    if (!permissionApi) {
      attachOrientationListener();
    }
    return () => {
      if (orientationAttached.current) {
        window.removeEventListener("deviceorientation", handleOrientation);
        orientationAttached.current = false;
      }
    };
  }, [attachOrientationListener, handleOrientation]);

  // 贴纸集合与历史照片对齐
  const makeBody = useCallback(
    (id: string, fresh: boolean): Body => {
      const w = viewport.current.w || window.innerWidth;
      const h = viewport.current.h || window.innerHeight;
      const traits = makePhysicalTraits();
      if (fresh) {
        const r = getSpawnRect();
        const cx = r ? r.left + r.width / 2 : w / 2;
        const cy = r ? r.top + r.height / 2 : h * 0.34;
        return {
          id,
          x: cx,
          y: cy,
          vx: rand(-80, 80) * traits.motionScale,
          vy: rand(60, 160) * traits.motionScale,
          angle: rand(-12, 12),
          va: rand(-120, 120) * traits.motionScale,
          ...traits,
          el: null,
        };
      }
      return {
        id,
        x: rand(traits.radius, w - traits.radius),
        y: rand(traits.radius, h - traits.radius),
        vx: 0,
        vy: 0,
        angle: rand(-10, 10),
        va: 0,
        ...traits,
        el: null,
      };
    },
    [getSpawnRect]
  );

  useEffect(() => {
    const incoming = photos.map((p) => p.id);
    const incomingSet = new Set(incoming);
    for (const id of Array.from(bodies.current.keys())) {
      if (!incomingSet.has(id)) bodies.current.delete(id);
    }
    for (const p of photos) {
      if (bodies.current.has(p.id)) continue;
      bodies.current.set(p.id, makeBody(p.id, p.id === freshId));
    }
    setIds(incoming);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [photos, freshId]);

  const bindEl = useCallback((id: string, el: HTMLImageElement | null) => {
    const b = bodies.current.get(id);
    if (b) b.el = el;
  }, []);

  const showSensorPrompt =
    !sensorPromptDismissed &&
    motionState.secure &&
    motionState.supported &&
    motionState.permissionApi &&
    motionState.permission !== "granted";

  // 物理主循环
  useEffect(() => {
    let raf = 0;
    let last = 0;

    const simulate = (dt: number) => {
      const w = viewport.current.w || window.innerWidth;
      const h = viewport.current.h || window.innerHeight;
      const gravityPower = GRAVITY * speedRef.current;
      const ax = gravityPower * grav.current.x;
      const ay = gravityPower * grav.current.y;
      const arr = Array.from(bodies.current.values());

      for (const b of arr) {
        const bax = ax * b.motionScale;
        const bay = ay * b.motionScale;
        b.vx = (b.vx + bax * dt) * AIR;
        b.vy = (b.vy + bay * dt) * AIR;
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        b.angle += b.va * dt;
        b.va *= ANG_DAMP;

        if (b.x < b.radius) {
          b.x = b.radius;
          b.vx = -b.vx * RESTITUTION;
          b.vy *= WALL_FRICTION;
        } else if (b.x > w - b.radius) {
          b.x = w - b.radius;
          b.vx = -b.vx * RESTITUTION;
          b.vy *= WALL_FRICTION;
        }
        if (b.y < b.radius) {
          b.y = b.radius;
          b.vy = -b.vy * RESTITUTION;
          b.vx *= WALL_FRICTION;
        } else if (b.y > h - b.radius) {
          b.y = h - b.radius;
          b.vy = -b.vy * RESTITUTION;
          b.vx *= WALL_FRICTION;
          b.va += b.vx * 0.6;
        }
        if (Math.abs(b.vy) < Math.abs(bay) * dt * 1.5) b.vy = 0;
        if (Math.abs(b.vx) < Math.abs(bax) * dt * 1.5) b.vx = 0;
      }

      for (let iter = 0; iter < COLLISION_ITERS; iter++) {
        for (let i = 0; i < arr.length; i++) {
          for (let j = i + 1; j < arr.length; j++) {
            const a = arr[i];
            const c = arr[j];
            const dx = c.x - a.x;
            const dy = c.y - a.y;
            const d2 = dx * dx + dy * dy;
            const minD = a.radius + c.radius;
            if (d2 >= minD * minD || d2 === 0) continue;
            const dist = Math.sqrt(d2);
            const nx = dx / dist;
            const ny = dy / dist;
            const totalRadius = a.radius + c.radius;
            const aShare = c.radius / totalRadius;
            const cShare = a.radius / totalRadius;
            const overlap = minD - dist;
            a.x -= nx * overlap * aShare;
            a.y -= ny * overlap * aShare;
            c.x += nx * overlap * cShare;
            c.y += ny * overlap * cShare;
            const vn = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny;
            if (vn < 0) {
              const aInvMass = 1 / a.radius;
              const cInvMass = 1 / c.radius;
              const imp = (-(1 + RESTITUTION) * vn) / (aInvMass + cInvMass);
              a.vx -= imp * aInvMass * nx;
              a.vy -= imp * aInvMass * ny;
              c.vx += imp * cInvMass * nx;
              c.vy += imp * cInvMass * ny;
            }
          }
        }
        for (const b of arr) {
          b.x = Math.min(Math.max(b.x, b.radius), w - b.radius);
          b.y = Math.min(Math.max(b.y, b.radius), h - b.radius);
        }
      }
    };

    const draw = () => {
      bodies.current.forEach((b) => {
        if (!b.el) return;
        b.el.style.transform = `translate3d(${b.x - STICKER / 2}px, ${
          b.y - STICKER / 2
        }px, 0) rotate(${b.angle}deg) scale(${b.size})`;
      });
    };

    const step = (tms: number) => {
      raf = requestAnimationFrame(step);
      if (!last) {
        last = tms;
        return;
      }
      let dt = (tms - last) / 1000;
      last = tms;
      if (dt > MAX_DT) dt = MAX_DT;
      simulate(dt);
      draw();
    };

    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <>
      <div className="pointer-events-none fixed inset-0 z-30 overflow-hidden">
        {ids.map((id) => {
          const p = byId.get(id);
          if (!p) return null;
          return (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={id}
              ref={(el) => bindEl(id, el)}
              src={p.cutoutImage || p.resultImage}
              alt=""
              draggable={false}
              className="absolute left-0 top-0 select-none object-contain drop-shadow-[0_6px_8px_rgba(0,0,0,0.3)] will-change-transform"
              style={{ width: STICKER, height: STICKER }}
            />
          );
        })}
      </div>

      {showSensorPrompt && (
        <section className="fixed inset-x-4 top-24 z-[65] rounded-2xl border border-black/5 bg-card p-3 text-label shadow-2xl dark:border-white/10">
          <div className="flex items-center gap-3">
            <div className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-klein/10 text-klein">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 2v4M12 18v4M4.9 4.9l2.8 2.8M16.2 16.2l2.9 2.9M2 12h4M18 12h4M4.9 19.1l2.8-2.8M16.2 7.8l2.9-2.9" />
              </svg>
            </div>
            <div className="min-w-0 flex-1">
              <h2 className="text-sm font-semibold">{t("启用方向感应")}</h2>
              <p className="mt-0.5 text-xs leading-relaxed text-label/60">{t("允许后，贴纸会跟随手机倾斜滑动。")}</p>
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            <button
              onClick={() => requestOrientationAccess()}
              className="flex-1 rounded-lg bg-klein px-3 py-2 text-center text-xs font-semibold text-white active:opacity-90"
            >
              {t("启用")}
            </button>
            <button
              onClick={() => setSensorPromptDismissed(true)}
              className="rounded-lg bg-chip px-3 py-2 text-xs font-semibold text-label active:opacity-90"
            >
              {t("稍后")}
            </button>
          </div>
        </section>
      )}
    </>
  );
}
