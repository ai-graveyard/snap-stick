"use client";

// 摇一摇检测（对应 iOS MotionManager 的 onShake）。
// 监听 devicemotion，当加速度突变超过阈值时回调一次（带去抖）。
// iOS 13+ 需要在用户手势里调用 DeviceMotionEvent.requestPermission；这里只负责监听，
// 权限请求复用 StickerSandbox 已有的方向授权（同一手势授权常一并放开 motion）。

import { useEffect, useRef } from "react";

interface Options {
  /** 是否启用监听（如仅在 developing 阶段） */
  enabled: boolean;
  /** 加速度变化阈值（m/s²），越大越难触发 */
  threshold?: number;
  onShake: () => void;
}

export function useShake({ enabled, threshold = 16, onShake }: Options) {
  const last = useRef({ x: 0, y: 0, z: 0, t: 0 });
  const cb = useRef(onShake);
  cb.current = onShake;

  useEffect(() => {
    if (!enabled || typeof window === "undefined") return;
    const handler = (e: DeviceMotionEvent) => {
      const acc = e.accelerationIncludingGravity;
      if (!acc) return;
      const now = Date.now();
      const { x = 0, y = 0, z = 0 } = acc as { x: number; y: number; z: number };
      const prev = last.current;
      if (prev.t && now - prev.t < 100) return; // 100ms 采样去抖
      const delta =
        Math.abs((x ?? 0) - prev.x) + Math.abs((y ?? 0) - prev.y) + Math.abs((z ?? 0) - prev.z);
      last.current = { x: x ?? 0, y: y ?? 0, z: z ?? 0, t: now };
      if (prev.t && delta > threshold) cb.current();
    };
    window.addEventListener("devicemotion", handler);
    return () => window.removeEventListener("devicemotion", handler);
  }, [enabled, threshold]);
}
