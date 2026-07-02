"use client";

import { useState, useRef, useEffect, useCallback, useMemo } from "react";
import PolaroidStudio, { type StudioPhase } from "@/components/PolaroidStudio";
import StickerSandbox from "@/components/StickerSandbox";
import BottomTabBar, { type Tab } from "@/components/BottomTabBar";
import CalendarView from "@/components/CalendarView";
import UserCenter from "@/components/UserCenter";
import HistoryView from "@/components/HistoryView";
import PaperPickerSheet from "@/components/PaperPickerSheet";
import StickerSettingsSheet from "@/components/StickerSettingsSheet";
import { usePhotoHistory } from "@/hooks/usePhotoHistory";
import { useSettings } from "@/contexts/SettingsContext";
import { generateSticker } from "@/lib/api";
import { cutoutSticker } from "@/lib/cutout";
import { sharePaperImage } from "@/lib/shareImage";
import { DEFAULT_PAPER_ID, type PaperStyle } from "@/lib/paperStyles";
import type { PhotoRecord } from "@/types";

const EJECT_MS = 2000; // 相纸吐出耗时
const DEVELOP_WAIT_MS = 2500; // 显影等待（摇一摇提示）
const DEVELOP_REVEAL_MS = 1000; // 揭晓动画（模糊→清晰）
const PAPER_KEY = "paper.lastStyle";

type CameraError = {
  kind: "denied" | "notfound" | "inuse" | "insecure" | "unknown";
  message: string;
};

function makeDemoStream(): MediaStream {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 720;
  const cx = canvas.getContext("2d")!;
  let tt = 0;
  const draw = () => {
    tt += 0.03;
    const g = cx.createLinearGradient(0, 0, 720, 720);
    g.addColorStop(0, `hsl(${(tt * 40) % 360}, 70%, 60%)`);
    g.addColorStop(1, `hsl(${(tt * 40 + 90) % 360}, 70%, 55%)`);
    cx.fillStyle = g;
    cx.fillRect(0, 0, 720, 720);
    cx.fillStyle = "rgba(255,255,255,0.9)";
    cx.beginPath();
    cx.arc(360 + Math.sin(tt) * 120, 360 + Math.cos(tt * 1.3) * 120, 90, 0, Math.PI * 2);
    cx.fill();
    requestAnimationFrame(draw);
  };
  draw();
  return canvas.captureStream(30);
}

export default function Home() {
  const { t, lang, visibleCount } = useSettings();

  const [tab, setTab] = useState<Tab>("home");
  const [phase, setPhase] = useState<StudioPhase>("idle");
  const [photo, setPhoto] = useState<PhotoRecord | null>(null);
  const [animateReveal, setAnimateReveal] = useState(true);
  const [cameraReady, setCameraReady] = useState(false);
  const [cameraError, setCameraError] = useState<CameraError | null>(null);
  const [requesting, setRequesting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [paperSheetOpen, setPaperSheetOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [hiddenPhotoIds, setHiddenPhotoIds] = useState<Set<string>>(() => new Set());
  const [tearing, setTearing] = useState(false);
  const [selectedPaperID, setSelectedPaperID] = useState(DEFAULT_PAPER_ID);

  // 出纸动画完成 & AI 返回 两个信号，都就绪后才进入显影
  const [ejectDone, setEjectDone] = useState(false);
  const [aiReady, setAiReady] = useState(false);
  const [freshId, setFreshId] = useState<string | null>(null);
  const pendingPhotoRef = useRef<PhotoRecord | null>(null);

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const orientationRequesterRef = useRef<(() => void) | null>(null);
  const windowRef = useRef<HTMLDivElement>(null);

  const { photos, addPhoto, clearPhotos, deletePhoto, setPaperStyle } = usePhotoHistory();

  // 载入上次选用的相纸
  useEffect(() => {
    const saved = typeof window !== "undefined" ? window.localStorage.getItem(PAPER_KEY) : null;
    if (saved) setSelectedPaperID(saved);
  }, []);

  const visibleSandboxPhotos = useMemo(() => {
    return [...photos]
      .sort((a, b) => b.timestamp - a.timestamp)
      .filter((p) => !hiddenPhotoIds.has(p.id))
      .slice(0, visibleCount);
  }, [hiddenPhotoIds, photos, visibleCount]);

  // 出片卡可翻看的列表（当前 photo 必在其中）
  const browsePhotos = useMemo(() => {
    const list = [...visibleSandboxPhotos];
    if (photo && !list.some((p) => p.id === photo.id)) list.unshift(photo);
    return list;
  }, [visibleSandboxPhotos, photo]);

  const registerOrientationRequester = useCallback((requester: (() => void) | null) => {
    orientationRequesterRef.current = requester;
  }, []);

  // 摄像头
  const requestCamera = useCallback(async () => {
    setRequesting(true);
    setCameraError(null);
    const attach = (stream: MediaStream) => {
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.onloadedmetadata = () => setCameraReady(true);
      }
    };
    try {
      if (typeof window !== "undefined" && new URLSearchParams(window.location.search).has("demo")) {
        attach(makeDemoStream());
        return;
      }
      if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
        setCameraError({ kind: "insecure", message: t("当前页面无法调用摄像头。请用 HTTPS 或 localhost 打开本应用。") });
        return;
      }
      const base = { width: { ideal: 1280 }, height: { ideal: 1280 } };
      try {
        attach(
          await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, ...base }, audio: false })
        );
      } catch (envErr) {
        try {
          attach(await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", ...base }, audio: false }));
        } catch {
          setCameraError(describeCameraError(envErr, t));
        }
      }
    } finally {
      setRequesting(false);
    }
  }, [t]);

  useEffect(() => {
    requestCamera();
    const stream = streamRef;
    return () => stream.current?.getTracks().forEach((tk) => tk.stop());
  }, [requestCamera]);

  // 切到非拍照 Tab 时暂停取景，回到拍照恢复（省电）
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (tab === "home") v.play?.().catch(() => {});
    else v.pause?.();
  }, [tab]);

  // 删除的照片从隐藏集合里清掉
  useEffect(() => {
    const photoIds = new Set(photos.map((p) => p.id));
    setHiddenPhotoIds((prev) => {
      const next = new Set(Array.from(prev).filter((id) => photoIds.has(id)));
      return next.size === prev.size ? prev : next;
    });
  }, [photos]);

  // 出纸 + AI 都就绪 → 进入显影
  useEffect(() => {
    if (phase === "ejecting" && ejectDone && aiReady) setPhase("developing");
  }, [phase, ejectDone, aiReady]);

  // 显影揭晓完成（由 PolaroidStudio 回调）→ 落定为成品，写历史 + 收进沙盒
  const handleDevelopComplete = useCallback(() => {
    const pending = pendingPhotoRef.current;
    pendingPhotoRef.current = null;
    if (pending) {
      const record: PhotoRecord = { ...pending, paperStyleID: selectedPaperID };
      setPhoto(record);
      setFreshId(record.id);
      addPhoto(record);
    }
    setPhase("done");
  }, [addPhoto, selectedPaperID]);

  const captureSquare = useCallback((): string | null => {
    const video = videoRef.current;
    if (!video || !video.videoWidth) return null;
    const size = Math.min(video.videoWidth, video.videoHeight);
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(
      video,
      (video.videoWidth - size) / 2,
      (video.videoHeight - size) / 2,
      size,
      size,
      0,
      0,
      size,
      size
    );
    return canvas.toDataURL("image/jpeg", 0.9);
  }, []);

  const beginShot = useCallback(
    (originalImage: string) => {
      const tempPhoto: PhotoRecord = {
        id: crypto.randomUUID(),
        originalImage,
        resultImage: originalImage,
        timestamp: Date.now(),
        paperStyleID: selectedPaperID,
      };
      setPhoto(tempPhoto);
      setAnimateReveal(true);
      setEjectDone(false);
      setAiReady(false);
      setFreshId(null);
      pendingPhotoRef.current = null;
      setPhase("ejecting");

      setTimeout(() => setEjectDone(true), EJECT_MS);

      generateSticker(originalImage)
        .then(async (resultImage) => {
          let cutoutImage: string | undefined;
          try {
            cutoutImage = await cutoutSticker(resultImage);
          } catch {
            cutoutImage = undefined;
          }
          const finalPhoto: PhotoRecord = { ...tempPhoto, resultImage, cutoutImage };
          setPhoto(finalPhoto);
          pendingPhotoRef.current = finalPhoto;
        })
        .catch(() => {
          setError(t("贴纸生成失败，已保留原图"));
          pendingPhotoRef.current = tempPhoto;
        })
        .finally(() => setAiReady(true));
    },
    [selectedPaperID, t]
  );

  const handleShutter = useCallback(() => {
    if (tearing) return;
    const originalImage = captureSquare();
    if (!originalImage) {
      setError(t("没抓到画面，请重试"));
      return;
    }
    setError(null);
    if (phase === "done") {
      // 撕纸连拍：让上一张落入沙盒淡出后再出新纸
      setTearing(true);
      setTimeout(() => {
        setTearing(false);
        beginShot(originalImage);
      }, 300);
    } else {
      beginShot(originalImage);
    }
  }, [beginShot, captureSquare, phase, t, tearing]);

  const handleRetake = useCallback(() => {
    setPhase("idle");
    setPhoto(null);
    setEjectDone(false);
    setAiReady(false);
    pendingPhotoRef.current = null;
    setError(null);
  }, []);

  const handleDownload = useCallback(() => {
    if (!photo) return;
    const a = document.createElement("a");
    a.href = photo.cutoutImage || photo.resultImage;
    a.download = `snapstick-${photo.timestamp}.png`;
    a.click();
    showToast(t("已保存到相册"));
  }, [photo, t]);

  const handleShare = useCallback(async () => {
    if (!photo) return;
    const ok = await sharePaperImage(
      photo.paperStyleID || selectedPaperID,
      photo.cutoutImage || photo.resultImage,
      photo.timestamp,
      lang
    );
    if (!ok) setError(t("生成分享图失败，请重试"));
  }, [photo, selectedPaperID, lang, t]);

  const handleBrowse = useCallback(
    (p: PhotoRecord) => {
      if (phase !== "done" || photo?.id === p.id) return;
      setPhoto(p);
      setSelectedPaperID(p.paperStyleID || DEFAULT_PAPER_ID);
      setError(null);
    },
    [phase, photo?.id]
  );

  const handlePickPaper = useCallback(
    (style: PaperStyle) => {
      setSelectedPaperID(style.id);
      if (typeof window !== "undefined") window.localStorage.setItem(PAPER_KEY, style.id);
      if (photo) {
        setPhoto({ ...photo, paperStyleID: style.id });
        setPaperStyle(photo.id, style.id);
      }
    },
    [photo, setPaperStyle]
  );

  const handleSelectHistory = useCallback((p: PhotoRecord) => {
    setPhoto(p);
    setSelectedPaperID(p.paperStyleID || DEFAULT_PAPER_ID);
    setAnimateReveal(false);
    setEjectDone(true);
    setAiReady(true);
    setPhase("done");
    setHistoryOpen(false);
    setTab("home");
    setError(null);
  }, []);

  const handleDeleteHistory = useCallback(
    (p: PhotoRecord) => {
      deletePhoto(p.id);
      setHiddenPhotoIds((prev) => {
        if (!prev.has(p.id)) return prev;
        const next = new Set(prev);
        next.delete(p.id);
        return next;
      });
      if (photo?.id === p.id) handleRetake();
    },
    [deletePhoto, handleRetake, photo?.id]
  );

  const handleToggleVisibility = useCallback((p: PhotoRecord) => {
    setHiddenPhotoIds((prev) => {
      const next = new Set(prev);
      if (next.has(p.id)) next.delete(p.id);
      else next.add(p.id);
      return next;
    });
  }, []);

  const handleClearHistory = useCallback(() => {
    clearPhotos();
    setHiddenPhotoIds(new Set());
    handleRetake();
  }, [clearPhotos, handleRetake]);

  const handleBeforeShutter = useCallback(() => {
    orientationRequesterRef.current?.();
  }, []);

  const toastTimer = useRef<number | null>(null);
  function showToast(msg: string) {
    setToast(msg);
    if (toastTimer.current) window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 2000);
  }

  return (
    <main className="fixed inset-0 overflow-hidden bg-surface">
      {/* 拍照层（始终挂载以保持取景，切 Tab 时隐藏） */}
      <div className={tab === "home" ? "contents" : "hidden"}>
        <PolaroidStudio
          videoRef={videoRef}
          windowRef={windowRef}
          phase={phase}
          photo={photo}
          browsePhotos={browsePhotos}
          cameraReady={cameraReady}
          tearing={tearing}
          animateReveal={animateReveal}
          ejectDurationMs={EJECT_MS}
          developWaitMs={DEVELOP_WAIT_MS}
          developRevealMs={DEVELOP_REVEAL_MS}
          onBeforeShutter={handleBeforeShutter}
          onShutter={handleShutter}
          onRetake={handleRetake}
          onDownload={handleDownload}
          onShare={handleShare}
          onBrowse={handleBrowse}
          onDevelopComplete={handleDevelopComplete}
        />

        <StickerSandbox
          photos={visibleSandboxPhotos}
          freshId={freshId}
          getSpawnRect={() => windowRef.current?.getBoundingClientRect() ?? null}
          registerOrientationRequester={registerOrientationRequester}
        />

        {/* 顶栏 */}
        <header className="safe-top fixed inset-x-0 top-3 z-40 flex items-center justify-between px-4 py-3">
          <button
            onClick={() => setHistoryOpen(true)}
            aria-label={t("历史记录")}
            className="grid h-10 w-10 place-items-center rounded-full bg-card/85 text-label/70 shadow-[0_2px_6px_rgba(61,51,38,0.12)] backdrop-blur-md active:scale-90"
          >
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M7 4h13v13" />
              <path d="M4 7h13v13H4z" />
              <path d="M7.5 16.5l2.7-3.1 2.1 2.1 1.4-1.5 2.8 2.5" />
              <circle cx="13.5" cy="10.5" r="1.2" />
            </svg>
          </button>

          <h1 className="text-base font-bold tracking-[0.35em] text-klein">{t("拍 立 贴")}</h1>

          {phase === "done" ? (
            <button
              onClick={() => setPaperSheetOpen(true)}
              aria-label={t("相纸")}
              className="grid h-10 w-10 place-items-center rounded-full bg-card/85 text-label/70 shadow-[0_2px_6px_rgba(61,51,38,0.12)] backdrop-blur-md active:scale-90"
            >
              <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3 3 8l9 5 9-5-9-5Z" />
                <path d="m3 12 9 5 9-5M3 16l9 5 9-5" />
              </svg>
            </button>
          ) : (
            <span className="h-10 w-10" />
          )}
        </header>

        {/* 错误提示 */}
        {error && (
          <div className="fixed inset-x-0 top-24 z-[60] flex justify-center px-4" onClick={() => setError(null)}>
            <div className="max-w-sm rounded-lg bg-red-500/90 px-4 py-2 text-sm text-white shadow-lg backdrop-blur-sm">
              {error}
            </div>
          </div>
        )}
      </div>

      {/* 日历 / 用户中心 */}
      {tab === "calendar" && <CalendarView photos={photos} onSelect={handleSelectHistory} />}
      {tab === "profile" && (
        <UserCenter photos={photos} onOpenHistory={() => setHistoryOpen(true)} onOpenSettings={() => setSettingsOpen(true)} />
      )}

      {/* 底部 Tab 栏 */}
      <BottomTabBar tab={tab} onChange={setTab} />

      {/* 整页历史 */}
      <HistoryView
        open={historyOpen}
        photos={photos}
        hiddenPhotoIds={hiddenPhotoIds}
        onSelect={handleSelectHistory}
        onDelete={handleDeleteHistory}
        onToggleVisibility={handleToggleVisibility}
        onClear={handleClearHistory}
        onClose={() => setHistoryOpen(false)}
      />

      {/* 相纸选择 */}
      <PaperPickerSheet
        open={paperSheetOpen}
        selectedID={photo?.paperStyleID || selectedPaperID}
        sampleImage={photo ? photo.cutoutImage || photo.resultImage : ""}
        onPick={handlePickPaper}
        onClose={() => setPaperSheetOpen(false)}
      />

      {/* 贴纸物理设置 */}
      <StickerSettingsSheet open={settingsOpen} onClose={() => setSettingsOpen(false)} />

      {/* 摄像头权限提示 */}
      {cameraError && !cameraReady && tab === "home" && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/75 px-6 backdrop-blur-sm">
          <div className="w-full max-w-xs rounded-3xl bg-card p-6 text-center text-label shadow-2xl">
            <div className="mx-auto mb-4 grid h-16 w-16 place-items-center rounded-full bg-chip text-label/60">
              <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3Z" />
                <circle cx="12" cy="13" r="3.5" />
              </svg>
            </div>
            <h2 className="text-base font-bold">{t("需要摄像头权限")}</h2>
            <p className="mt-2 text-sm leading-relaxed text-label/60">{cameraError.message}</p>
            {cameraError.kind !== "insecure" && (
              <button
                onClick={requestCamera}
                disabled={requesting}
                className="mt-5 w-full rounded-full bg-klein py-3 text-sm font-medium text-white active:bg-klein-deep disabled:opacity-60"
              >
                {requesting ? t("正在请求…") : t("允许使用摄像头")}
              </button>
            )}
          </div>
        </div>
      )}

      {/* toast */}
      {toast && (
        <div className="pointer-events-none fixed inset-x-0 bottom-24 z-[90] flex justify-center">
          <span className="rounded-full bg-black/80 px-4 py-2 text-sm text-white">{toast}</span>
        </div>
      )}
    </main>
  );
}

function describeCameraError(err: unknown, t: (k: string) => string): CameraError {
  const name = (err as { name?: string } | null)?.name ?? "";
  switch (name) {
    case "NotAllowedError":
    case "PermissionDeniedError":
    case "SecurityError":
      return { kind: "denied", message: t("摄像头权限被拒绝。请在浏览器地址栏或系统设置里允许访问摄像头，然后重试。") };
    case "NotFoundError":
    case "DevicesNotFoundError":
    case "OverconstrainedError":
      return { kind: "notfound", message: t("没有找到可用的摄像头设备。") };
    case "NotReadableError":
    case "TrackStartError":
      return { kind: "inuse", message: t("摄像头正被其他应用占用，请关闭后重试。") };
    default:
      return { kind: "unknown", message: t("无法访问摄像头，请检查浏览器权限设置后重试。") };
  }
}
