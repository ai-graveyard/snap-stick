"use client";

// 原创即时相机（拍立贴）+ 出纸 / 显影动画 + 最终展示。
// 对应 iOS PolaroidStudioView.swift。克莱因蓝品牌机身（炭灰取景面板、镉黄快门、
// 蓝饰条、蓝镜圈），相纸卡支持翻看历史、点击切原图/贴图、保存/分享/重拍、摇一摇加速显影。

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, useAnimation, AnimatePresence } from "framer-motion";
import PaperMat from "@/components/PaperMat";
import { paperStyle } from "@/lib/paperStyles";
import { useSettings } from "@/contexts/SettingsContext";
import { useShake } from "@/hooks/useShake";
import type { PhotoRecord } from "@/types";

export type StudioPhase = "idle" | "ejecting" | "developing" | "done";

interface PolaroidStudioProps {
  videoRef: React.RefObject<HTMLVideoElement | null>;
  windowRef?: React.Ref<HTMLDivElement>;
  phase: StudioPhase;
  photo: PhotoRecord | null;
  /** 出片卡可左右滑翻看的历史作品（新→旧；当前 photo 必在其中） */
  browsePhotos: PhotoRecord[];
  cameraReady: boolean;
  /** 撕纸连拍过渡：上一张正在脱离 */
  tearing: boolean;
  /** 新拍摄为 true（播放显影动画）；查看历史为 false（直接显示） */
  animateReveal: boolean;
  ejectDurationMs: number;
  /** 显影等待（出现摇一摇提示的时长） */
  developWaitMs: number;
  /** 揭晓动画（模糊→清晰）时长 */
  developRevealMs: number;
  onBeforeShutter?: () => void;
  onShutter: () => void;
  onRetake: () => void;
  onDownload: () => void;
  onShare: () => void;
  /** 翻看到另一张历史作品 */
  onBrowse: (photo: PhotoRecord) => void;
  /** 显影揭晓完成 → 落定为成品（写历史、收进沙盒） */
  onDevelopComplete: () => void;
}

export default function PolaroidStudio({
  videoRef,
  windowRef,
  phase,
  photo,
  browsePhotos,
  cameraReady,
  tearing,
  animateReveal,
  ejectDurationMs,
  developWaitMs,
  developRevealMs,
  onBeforeShutter,
  onShutter,
  onRetake,
  onDownload,
  onShare,
  onBrowse,
  onDevelopComplete,
}: PolaroidStudioProps) {
  const { t } = useSettings();
  const flash = useAnimation();
  const [showingOriginal, setShowingOriginal] = useState(false);
  // 显影揭晓态（模糊→清晰）。developing 阶段先等待再揭晓。
  const [revealActive, setRevealActive] = useState(false);
  const developCompleteRef = useRef(onDevelopComplete);
  developCompleteRef.current = onDevelopComplete;

  const busy = phase === "ejecting" || phase === "developing";
  const canShutter = cameraReady && !busy && !tearing;
  const paperOut = phase !== "idle";
  const waiting = phase === "developing" && !revealActive; // 显影等待（摇一摇提示）
  const matVisible = (phase === "developing" && revealActive) || phase === "done";
  const emulsionVisible = phase === "ejecting" || waiting;
  const shutterHint = busy
    ? t("冲印中")
    : phase === "done"
      ? t("再拍一张")
      : cameraReady
        ? t("按下快门")
        : t("启动相机…");

  const ejectSec = ejectDurationMs / 1000;
  const revealSec = developRevealMs / 1000;

  // 翻看到另一张时复位「原图/贴图」
  useEffect(() => {
    setShowingOriginal(false);
  }, [photo?.id]);

  // 揭晓显影：先等待（可被摇一摇打断），再做模糊→清晰，完成后落定
  const triggerReveal = useCallback(() => {
    setRevealActive((active) => {
      if (active) return active;
      window.setTimeout(() => developCompleteRef.current(), developRevealMs);
      return true;
    });
  }, [developRevealMs]);

  useEffect(() => {
    if (phase !== "developing") {
      setRevealActive(false);
      return;
    }
    if (!animateReveal) {
      // 历史回看：直接落定（理论上不会走到这里，phase 已是 done）
      triggerReveal();
      return;
    }
    const wait = window.setTimeout(triggerReveal, developWaitMs);
    return () => window.clearTimeout(wait);
  }, [phase, animateReveal, developWaitMs, triggerReveal]);

  // 摇一摇加速显影（仅在等待期生效）
  useShake({ enabled: waiting, onShake: triggerReveal });

  const handleShutter = useCallback(async () => {
    if (!canShutter) return;
    onBeforeShutter?.();
    flash.set({ opacity: 0 });
    await flash.start({ opacity: 0.95, transition: { duration: 0.08 } });
    await flash.start({ opacity: 0, transition: { duration: 0.4, ease: "easeOut" } });
    playShutter();
    onShutter();
  }, [canShutter, flash, onBeforeShutter, onShutter]);

  // 桌面端：空格拍照
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === "Space" && (phase === "idle" || phase === "done")) {
        e.preventDefault();
        handleShutter();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [handleShutter, phase]);

  // 出纸时播放马达声
  useEffect(() => {
    if (phase === "ejecting") playMotor(ejectSec);
  }, [phase, ejectSec]);

  // 翻看：水平滑动切换当前作品
  const browseIndex = browsePhotos.findIndex((p) => p.id === photo?.id);
  const handleSwipe = (dir: 1 | -1) => {
    if (phase !== "done" || browseIndex < 0) return;
    const next = browseIndex + dir;
    if (next < 0 || next >= browsePhotos.length) return;
    onBrowse(browsePhotos[next]);
  };

  const displayPhoto = photo;
  const displayImage = displayPhoto
    ? displayPhoto.cutoutImage || displayPhoto.resultImage
    : "";
  const style = paperStyle(displayPhoto?.paperStyleID);

  return (
    <div className="fixed inset-0 z-0 flex items-center justify-center overflow-hidden">
      {/* 快门白闪 */}
      <motion.div
        className="pointer-events-none fixed inset-0 z-[100] bg-white"
        initial={{ opacity: 0 }}
        animate={flash}
      />

      {/* 舞台：相机 + 相纸。向上出纸时整体下移 */}
      <motion.div
        className="relative"
        style={{ width: "var(--cam-w)", ["--cam-w" as string]: "min(76vw, 300px)" }}
        animate={{ y: paperOut ? "42%" : "0%" }}
        transition={{ duration: ejectSec, ease: [0.22, 0.61, 0.36, 1] }}
      >
        {/* ---------- 相纸（位于相机之后，从顶部出纸口向上吐出） ---------- */}
        <motion.div
          className="absolute bottom-full left-1/2 z-10"
          style={{ width: "calc(var(--cam-w) * 0.82)" }}
          initial={{ x: "-50%", y: "100%" }}
          animate={{
            x: "-50%",
            y: tearing ? "180%" : paperOut ? "0%" : "100%",
            opacity: tearing ? 0 : 1,
          }}
          transition={{
            duration: tearing ? 0.3 : paperOut ? ejectSec : 0.7,
            ease: tearing ? "easeIn" : paperOut ? [0.22, 0.61, 0.36, 1] : "easeIn",
          }}
        >
          <div className="rounded-[4px] p-[5%] pb-[8%] shadow-[0_18px_30px_-12px_rgba(0,0,0,0.4),0_4px_10px_rgba(0,0,0,0.18)]"
            style={{ background: "linear-gradient(160deg,#FDFCF8 0%,#F3EDE1 100%)" }}
          >
            {/* 顶部日期条 */}
            <div className="flex h-[8%] items-center justify-center pb-[3%]">
              {phase === "done" && displayPhoto && (
                <span className="text-[11px] font-medium tracking-wide text-stone-500">
                  {formatDate(displayPhoto.timestamp)}
                </span>
              )}
            </div>

            {/* 相片窗口（正方形） */}
            <div
              ref={windowRef}
              className="polaroid-window aspect-square"
              onClick={() => phase === "done" && setShowingOriginal((v) => !v)}
            >
              {/* 出纸口暗影 */}
              <div className="slot-shadow pointer-events-none absolute inset-x-0 top-0 z-20 h-1/4" />

              {/* 显影前：空白药膜 + 扫描线 */}
              {emulsionVisible && (
                <div className="emulsion absolute inset-0 z-10">
                  <div className="scanline" />
                  <div className="absolute inset-0 flex items-center justify-center">
                    <span className="animate-pulse-slow text-[11px] uppercase tracking-[0.45em] text-stone-400/60">
                      {t("冲印中")}
                    </span>
                  </div>
                </div>
              )}

              {/* 摇一摇加速提示 */}
              {waiting && (
                <div className="pointer-events-none absolute inset-x-0 bottom-[12%] z-20 flex justify-center">
                  <span className="text-[10px] font-medium tracking-[0.2em] text-white/55">
                    {t("摇一摇加速显影")}
                  </span>
                </div>
              )}

              {/* 显影 / 成品：相纸衬纸 + 贴纸（done 支持翻看与原图切换） */}
              {matVisible && displayPhoto && (
                <motion.div
                  key={displayPhoto.id}
                  className="absolute inset-0"
                  drag={phase === "done" && browsePhotos.length > 1 ? "x" : false}
                  dragConstraints={{ left: 0, right: 0 }}
                  dragElastic={0.2}
                  onDragEnd={(_, info) => {
                    if (info.offset.x < -60) handleSwipe(1); // 左滑看更旧
                    else if (info.offset.x > 60) handleSwipe(-1); // 右滑看更新
                  }}
                  initial={
                    animateReveal && phase === "developing"
                      ? { filter: "blur(16px) brightness(0.5) saturate(0.45)", opacity: 0 }
                      : false
                  }
                  animate={{ filter: "blur(0px) brightness(1) saturate(1)", opacity: 1 }}
                  transition={{ duration: animateReveal && phase === "developing" ? revealSec : 0, ease: "easeOut" }}
                >
                  {showingOriginal && phase === "done" ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={displayPhoto.originalImage}
                      alt={t("原图")}
                      draggable={false}
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <PaperMat style={style} image={displayImage} />
                  )}
                </motion.div>
              )}

              {/* 翻页计数（左上） */}
              {phase === "done" && browsePhotos.length > 1 && (
                <span className="absolute left-2 top-2 z-30 rounded-full bg-black/50 px-1.5 py-0.5 font-mono text-[10px] font-semibold text-white/85">
                  {browseIndex + 1} / {browsePhotos.length}
                </span>
              )}

              {/* 原图/贴图角标（左下） */}
              {phase === "done" && (
                <span className="pointer-events-none absolute bottom-2 left-2 z-30 rounded-full bg-black/55 px-2 py-1 text-[10px] font-medium text-white/80">
                  {showingOriginal ? t("原图") : t("贴图")}
                </span>
              )}
            </div>

            {/* 底部白边：操作按钮 / 字标 */}
            <div className="flex h-[14%] items-center justify-center pt-[6%]">
              {phase === "done" ? (
                <motion.div
                  className="flex items-center gap-6"
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.15, duration: 0.35 }}
                >
                  <IconButton label={t("保存")} onClick={onDownload} color="#595959">
                    <path d="M12 3v12" />
                    <path d="m7 11 5 5 5-5" />
                    <path d="M5 21h14" />
                  </IconButton>
                  <IconButton label={t("分享")} onClick={onShare} color="#002FA7">
                    <path d="M12 16V4" />
                    <path d="m7 9 5-5 5 5" />
                    <path d="M5 14v6h14v-6" />
                  </IconButton>
                  <IconButton label={t("重拍")} onClick={onRetake} color="#808080">
                    <path d="M3 12a9 9 0 1 0 3-6.7" />
                    <path d="M3 3v5h5" />
                  </IconButton>
                </motion.div>
              ) : (
                <span className="text-[12px] tracking-[0.3em] text-stone-400/70">SNAPSTICK</span>
              )}
            </div>
          </div>
        </motion.div>

        {/* ---------- 相机机身（克莱因蓝品牌；不透明，盖住未吐出的相纸） ---------- */}
        <div
          className="relative z-30 overflow-hidden rounded-[24px] border-[1.5px] border-klein/35 bg-gradient-to-b from-cream to-[#E5DBC8] shadow-[0_24px_50px_-18px_rgba(92,69,41,0.45),0_8px_18px_rgba(92,69,41,0.25)]"
          style={{ minHeight: "calc(var(--cam-w) * 1.16)" }}
        >
          {/* 顶部出纸口 */}
          <div className="absolute inset-x-[5%] top-[1.5%] h-[3px] rounded-full bg-black/55" />

          {/* 机身右上快门：白圈 + 镉黄实心 */}
          <div className="absolute right-[5%] top-[18%] z-40 flex flex-col items-center gap-1.5">
            <motion.button
              onClick={handleShutter}
              disabled={!canShutter}
              aria-label={phase === "done" ? t("再拍一张") : t("拍照")}
              className="relative grid h-14 w-14 place-items-center rounded-full disabled:opacity-45"
              whileTap={canShutter ? { scale: 0.88 } : undefined}
              transition={{ type: "spring", stiffness: 600, damping: 18 }}
            >
              <span className="absolute inset-0 rounded-full border-[3px] border-white shadow-[0_4px_10px_rgba(0,0,0,0.3)]" />
              <span className="h-11 w-11 rounded-full bg-cadmium shadow-inner" />
            </motion.button>
            <span className="max-w-14 rounded-full bg-white/75 px-1 py-0.5 text-center text-[8px] font-medium leading-tight text-stone-500 shadow-sm">
              {shutterHint}
            </span>
          </div>

          {/* 顶部炭灰取景面板 */}
          <div className="mx-[6%] mt-[6%] flex items-center justify-between rounded-[12px] bg-faceplate px-[5.5%] py-[4%]">
            <div className="h-3.5 w-7 rounded-[3px] border border-white/15 bg-black/70" />
            <span className="text-[10px] font-extrabold uppercase tracking-[0.25em] text-white/85">
              SnapStick
            </span>
            <span className="h-2.5 w-2.5 rounded-full bg-gradient-to-br from-klein to-klein-deep shadow-[0_0_6px_rgba(0,47,167,0.7)]" />
          </div>

          {/* 大镜头：实时取景 + 克莱因蓝镜圈 */}
          <div className="my-[6%] flex justify-center">
            <div
              className="relative shrink-0 rounded-full bg-gradient-to-br from-[#545454] to-[#212121] p-[2%] shadow-[0_6px_14px_rgba(0,0,0,0.4)]"
              style={{ width: "calc(var(--cam-w) * 0.62)", height: "calc(var(--cam-w) * 0.62)" }}
            >
              <div className="h-full w-full rounded-full bg-black p-[8%]">
                <div className="relative h-full w-full overflow-hidden rounded-full bg-black ring-2 ring-klein/60">
                  <video
                    ref={videoRef as React.RefObject<HTMLVideoElement>}
                    autoPlay
                    playsInline
                    muted
                    className="h-full w-full object-cover"
                  />
                  <AnimatePresence>
                    {busy && (
                      <motion.div
                        className="absolute inset-0 z-10 flex items-center justify-center rounded-full bg-[#090807]"
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 0.16 }}
                      >
                        <span className="text-[9px] font-semibold uppercase tracking-[0.42em] text-white/30">
                          Developing
                        </span>
                      </motion.div>
                    )}
                  </AnimatePresence>
                  <div className="pointer-events-none absolute inset-0 z-20 rounded-full ring-1 ring-inset ring-white/10" />
                </div>
              </div>
            </div>
          </div>

          {/* 品牌饰条：克莱因蓝渐变圆角条 + 白色竖点（替换彩虹条） */}
          <div className="mx-[9%] flex h-[3%] min-h-[10px] items-center justify-center gap-[2%] rounded-full bg-gradient-to-r from-klein to-klein-deep">
            {Array.from({ length: 7 }).map((_, i) => (
              <span key={i} className="h-[55%] w-[1.5px] rounded-full bg-white/25" />
            ))}
          </div>

          {/* 底部状态区 */}
          <div className="flex items-end justify-between px-[8%] pb-[7%] pt-[4%]">
            <span className="text-[10px] uppercase tracking-[0.2em] text-stone-500/70">
              Snap Ready
            </span>
            <span className="h-2 w-2 rounded-full bg-klein shadow-[0_0_8px_rgba(0,47,167,0.65)]" />
          </div>
        </div>
      </motion.div>
    </div>
  );
}

function IconButton({
  label,
  onClick,
  color,
  children,
}: {
  label: string;
  onClick: () => void;
  color: string;
  children: React.ReactNode;
}) {
  return (
    <button onClick={onClick} aria-label={label} className="grid h-8 w-8 place-items-center active:scale-90">
      <svg
        width="19"
        height="19"
        viewBox="0 0 24 24"
        fill="none"
        stroke={color}
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {children}
      </svg>
    </button>
  );
}

function formatDate(ts: number) {
  // 本地化日期：读取 <html lang>（由 SettingsContext 同步），避免逐处传参
  const lang =
    typeof document !== "undefined" && document.documentElement.lang.startsWith("en") ? "en-US" : "zh-CN";
  return new Date(ts).toLocaleDateString(lang, { year: "numeric", month: "long", day: "numeric" });
}

/* ---------- 音效（Web Audio，无需资源文件） ---------- */

function getAudioCtx(): AudioContext | null {
  try {
    const Ctx =
      window.AudioContext ||
      (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    return new Ctx();
  } catch {
    return null;
  }
}

function playShutter() {
  const ctx = getAudioCtx();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.type = "triangle";
  osc.frequency.value = 520;
  gain.gain.setValueAtTime(0.18, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.18);
  osc.start();
  osc.stop(ctx.currentTime + 0.18);
}

function playMotor(durationSec: number) {
  const ctx = getAudioCtx();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  const lfo = ctx.createOscillator();
  const lfoGain = ctx.createGain();
  osc.type = "sawtooth";
  osc.frequency.value = 78;
  lfo.frequency.value = 22;
  lfoGain.gain.value = 8;
  lfo.connect(lfoGain);
  lfoGain.connect(osc.frequency);
  osc.connect(gain);
  gain.connect(ctx.destination);
  const tt = ctx.currentTime;
  gain.gain.setValueAtTime(0.0001, tt);
  gain.gain.linearRampToValueAtTime(0.05, tt + 0.15);
  gain.gain.setValueAtTime(0.05, tt + durationSec - 0.25);
  gain.gain.exponentialRampToValueAtTime(0.0001, tt + durationSec);
  osc.start(tt);
  lfo.start(tt);
  osc.stop(tt + durationSec);
  lfo.stop(tt + durationSec);
}
