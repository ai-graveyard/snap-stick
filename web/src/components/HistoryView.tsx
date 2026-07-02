"use client";

// 历史记录整页（对应 iOS HistoryView.swift）：左上返回、显示数量滑杆、
// 按 今天/昨天/日期 分组，每条可回看 / 隐藏 / 删除；底部清空（需输入「我确认」）。

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import ConfirmDialog from "@/components/ConfirmDialog";
import { useSettings } from "@/contexts/SettingsContext";
import type { PhotoRecord } from "@/types";

interface HistoryViewProps {
  open: boolean;
  photos: PhotoRecord[];
  hiddenPhotoIds: Set<string>;
  onSelect: (p: PhotoRecord) => void;
  onDelete: (p: PhotoRecord) => void;
  onToggleVisibility: (p: PhotoRecord) => void;
  onClear: () => void;
  onClose: () => void;
}

function display(p: PhotoRecord) {
  return p.cutoutImage || p.resultImage;
}

export default function HistoryView({
  open,
  photos,
  hiddenPhotoIds,
  onSelect,
  onDelete,
  onToggleVisibility,
  onClear,
  onClose,
}: HistoryViewProps) {
  const { t, lang, visibleCount, setVisibleCount } = useSettings();
  const locale = lang === "zh" ? "zh-CN" : "en-US";
  const [deleteTarget, setDeleteTarget] = useState<PhotoRecord | null>(null);
  const [clearOpen, setClearOpen] = useState(false);
  const [clearText, setClearText] = useState("");

  const groups = groupByDate(photos, locale, t);

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[70] flex flex-col bg-surface pt-[env(safe-area-inset-top)] text-label"
          initial={{ x: "100%" }}
          animate={{ x: 0 }}
          exit={{ x: "100%" }}
          transition={{ type: "tween", duration: 0.25 }}
        >
          {/* 顶栏 */}
          <div className="flex items-center gap-2 px-2 py-2.5">
            <button onClick={onClose} aria-label={t("返回")} className="grid h-10 w-10 place-items-center text-xl">
              ‹
            </button>
            <div className="flex flex-col">
              <span className="text-lg font-bold tracking-wide">{t("历史记录")}</span>
              <span className="text-xs text-label/50">{t("共 {0} 张", photos.length)}</span>
            </div>
          </div>
          <div className="border-t border-black/5 dark:border-white/10" />

          {/* 显示数量 */}
          <div className="px-4 py-3">
            <div className="mb-2 flex items-center justify-between text-xs">
              <span className="font-semibold">{t("显示贴纸")}</span>
              <span className="font-mono text-label/50">{visibleCount} / 20</span>
            </div>
            <input
              type="range"
              min={1}
              max={20}
              step={1}
              value={visibleCount}
              onChange={(e) => setVisibleCount(Number(e.currentTarget.value))}
              className="w-full accent-klein"
            />
          </div>
          <div className="border-t border-black/5 dark:border-white/10" />

          {/* 时间线 */}
          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            {photos.length === 0 ? (
              <div className="pt-16 text-center text-sm leading-relaxed text-label/40">
                {t("还没有贴纸")}
                <br />
                {t("按下快门拍一张吧")}
              </div>
            ) : (
              <div className="space-y-5">
                {groups.map((group) => (
                  <section key={group.label}>
                    <div className="pb-1.5 text-[11px] font-semibold tracking-wider text-label/45">
                      {group.label}
                    </div>
                    <div className="space-y-2">
                      {group.photos.map((p) => {
                        const hidden = hiddenPhotoIds.has(p.id);
                        return (
                          <div
                            key={p.id}
                            className="flex items-center gap-3 rounded-xl bg-card p-2 shadow-[0_2px_6px_rgba(0,0,0,0.05)]"
                          >
                            <button onClick={() => onSelect(p)} className="flex min-w-0 flex-1 items-center gap-3 text-left">
                              <span className="grid h-14 w-14 shrink-0 place-items-center overflow-hidden rounded-lg bg-chip">
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img
                                  src={display(p)}
                                  alt=""
                                  draggable={false}
                                  className={`h-full w-full ${p.cutoutImage ? "object-contain p-1" : "object-cover"} ${
                                    hidden ? "opacity-35 grayscale" : ""
                                  }`}
                                />
                              </span>
                              <span className="min-w-0 flex-1">
                                <span className="block text-sm font-medium">{t("贴纸快照")}</span>
                                <span className="mt-0.5 block font-mono text-xs text-label/50">
                                  {new Date(p.timestamp).toLocaleTimeString(locale, {
                                    hour: "2-digit",
                                    minute: "2-digit",
                                  })}
                                </span>
                              </span>
                            </button>
                            <button
                              onClick={() => onToggleVisibility(p)}
                              aria-label={hidden ? t("展示这张贴纸") : t("隐藏这张贴纸")}
                              className={`grid h-8 w-8 shrink-0 place-items-center rounded-full bg-chip ${
                                hidden ? "text-label/40" : "text-label/60"
                              }`}
                            >
                              {hidden ? "◌" : "◉"}
                            </button>
                            <button
                              onClick={() => setDeleteTarget(p)}
                              aria-label={t("删除")}
                              className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-chip text-label/50 active:text-red-500"
                            >
                              ✕
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </section>
                ))}
              </div>
            )}
          </div>

          {photos.length > 0 && (
            <div className="safe-bottom border-t border-black/5 dark:border-white/10">
              <button
                onClick={() => setClearOpen(true)}
                className="w-full py-3 text-sm text-label/50 active:text-red-500"
              >
                {t("清空所有记录")}
              </button>
            </div>
          )}

          {deleteTarget && (
            <ConfirmDialog
              title={t("删除这张贴纸？")}
              message={t("删除后会从历史记录和散落贴纸中移除。")}
              confirmLabel={t("删除")}
              danger
              onCancel={() => setDeleteTarget(null)}
              onConfirm={() => {
                onDelete(deleteTarget);
                setDeleteTarget(null);
              }}
            />
          )}

          {clearOpen && (
            <ConfirmDialog
              title={t("清空所有记录？")}
              message={`${t("这个操作会删除全部历史贴纸，无法撤销。")}`}
              confirmLabel={t("清空")}
              danger
              confirmDisabled={clearText.trim() !== t("我确认")}
              onCancel={() => {
                setClearOpen(false);
                setClearText("");
              }}
              onConfirm={() => {
                if (clearText.trim() !== t("我确认")) return;
                onClear();
                setClearOpen(false);
                setClearText("");
              }}
            >
              <label className="mt-3 block">
                <span className="text-xs font-semibold text-label/60">{t("输入「我确认」继续")}</span>
                <input
                  type="text"
                  value={clearText}
                  onChange={(e) => setClearText(e.currentTarget.value)}
                  autoFocus
                  className="mt-2 w-full rounded-lg border border-black/15 bg-surface px-3 py-2 text-sm text-label outline-none focus:border-klein dark:border-white/15"
                />
              </label>
            </ConfirmDialog>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function groupByDate(
  photos: PhotoRecord[],
  locale: string,
  t: (k: string, ...a: (string | number)[]) => string
) {
  const sorted = [...photos].sort((a, b) => b.timestamp - a.timestamp);
  const groups: { label: string; photos: PhotoRecord[] }[] = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const yesterday = today.getTime() - 86400000;

  for (const p of sorted) {
    const d = new Date(p.timestamp);
    d.setHours(0, 0, 0, 0);
    let label: string;
    if (d.getTime() === today.getTime()) label = t("今天");
    else if (d.getTime() === yesterday) label = t("昨天");
    else label = new Date(p.timestamp).toLocaleDateString(locale, { year: "numeric", month: "long", day: "numeric" });
    const last = groups[groups.length - 1];
    if (last?.label === label) last.photos.push(p);
    else groups.push({ label, photos: [p] });
  }
  return groups;
}
