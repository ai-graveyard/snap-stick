"use client";

// 贴纸日历（对应 iOS CalendarView.swift）：月/周/日 三视图。
// 月视图用代表贴纸铺满有作品的日子；周视图把每天叠成一摞拍立得；日视图平铺当天全部作品。
// 月视图可「撒一把」：把当月贴纸倒进物理沙盒随手机倾斜到处跑。

import { useMemo, useState } from "react";
import StickerSandbox from "@/components/StickerSandbox";
import { useSettings } from "@/contexts/SettingsContext";
import type { PhotoRecord } from "@/types";

type Mode = "month" | "week" | "day";

interface CalendarViewProps {
  photos: PhotoRecord[];
  onSelect: (photo: PhotoRecord) => void;
}

const ACCENT = "#D4853F"; // 今天描边色（暖琥珀）
const DAY_MS = 86400000;

function startOfDay(ts: number): number {
  const d = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}
function sameMonth(a: number, b: number): boolean {
  const da = new Date(a), db = new Date(b);
  return da.getFullYear() === db.getFullYear() && da.getMonth() === db.getMonth();
}
function display(photo: PhotoRecord): string {
  return photo.cutoutImage || photo.resultImage;
}

export default function CalendarView({ photos, onSelect }: CalendarViewProps) {
  const { t, lang } = useSettings();
  const locale = lang === "zh" ? "zh-CN" : "en-US";
  const [mode, setMode] = useState<Mode>("month");
  const [anchor, setAnchor] = useState<number>(() => Date.now());
  const [playing, setPlaying] = useState(false);

  // 以「当天 00:00」为 key 的贴纸字典
  const byDay = useMemo(() => {
    const map = new Map<number, PhotoRecord[]>();
    for (const p of photos) {
      const k = startOfDay(p.timestamp);
      const arr = map.get(k);
      if (arr) arr.push(p);
      else map.set(k, [p]);
    }
    return map;
  }, [photos]);

  const monthPhotos = useMemo(
    () => photos.filter((p) => sameMonth(p.timestamp, anchor)).sort((a, b) => a.timestamp - b.timestamp),
    [photos, anchor]
  );

  const todayStart = startOfDay(Date.now());
  const isAnchorToday = useMemo(() => {
    if (mode === "day") return startOfDay(anchor) === todayStart;
    if (mode === "month") return sameMonth(anchor, Date.now());
    // week
    return Math.abs(anchor - Date.now()) < 7 * DAY_MS && weekStart(anchor) === weekStart(Date.now());
  }, [anchor, mode, todayStart]);

  function step(dir: number) {
    const d = new Date(anchor);
    if (mode === "month") d.setMonth(d.getMonth() + dir);
    else if (mode === "week") d.setDate(d.getDate() + dir * 7);
    else d.setDate(d.getDate() + dir);
    setPlaying(false);
    setAnchor(d.getTime());
  }

  function weekStart(ts: number): number {
    const d = new Date(startOfDay(ts));
    d.setDate(d.getDate() - d.getDay()); // 周日为一周起点
    return d.getTime();
  }

  const periodTitle = useMemo(() => {
    const d = new Date(anchor);
    if (mode === "month") return d.toLocaleDateString(locale, { year: "numeric", month: "long" });
    if (mode === "day") return d.toLocaleDateString(locale, { year: "numeric", month: "long", day: "numeric", weekday: "long" });
    const ws = new Date(weekStart(anchor));
    const we = new Date(weekStart(anchor) + 6 * DAY_MS);
    const f = (x: Date) => x.toLocaleDateString(locale, { month: "short", day: "numeric" });
    return `${f(ws)} – ${f(we)}`;
  }, [anchor, mode, locale]);

  return (
    <div className="absolute inset-0 flex flex-col bg-surface pt-[env(safe-area-inset-top)] text-label">
      <div className="flex flex-col gap-2.5 px-4 pb-2 pt-6">
        {/* 模式切换 */}
        <div className="flex gap-1 rounded-xl bg-chip p-1">
          {(["month", "week", "day"] as Mode[]).map((m) => {
            const sel = mode === m;
            const label = t(m === "month" ? "月" : m === "week" ? "周" : "日");
            return (
              <button
                key={m}
                onClick={() => {
                  setMode(m);
                  setPlaying(false);
                }}
                className={`flex-1 rounded-lg py-2 text-sm font-semibold transition-colors ${
                  sel ? "bg-klein text-white" : "text-label"
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>
        {/* 翻页 */}
        <div className="flex items-center justify-between px-1">
          <button onClick={() => step(-1)} aria-label="prev" className="grid h-9 w-9 place-items-center text-label/70">
            ‹
          </button>
          <span className="text-[15px] font-semibold">{periodTitle}</span>
          <button onClick={() => step(1)} aria-label="next" className="grid h-9 w-9 place-items-center text-label/70">
            ›
          </button>
        </div>
        {!isAnchorToday && (
          <button onClick={() => setAnchor(Date.now())} className="text-center text-xs font-medium" style={{ color: ACCENT }}>
            {t("回到今天")}
          </button>
        )}
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto pb-28">
        {mode === "month" && (
          <MonthView
            anchor={anchor}
            byDay={byDay}
            locale={locale}
            onPickDay={(day) => {
              setAnchor(day);
              setMode("day");
            }}
          />
        )}
        {mode === "week" && (
          <WeekView
            anchor={anchor}
            byDay={byDay}
            weekStart={weekStart}
            locale={locale}
            onPickDay={(day) => {
              setAnchor(day);
              setMode("day");
            }}
          />
        )}
        {mode === "day" && (
          <DayView items={byDay.get(startOfDay(anchor)) ?? []} locale={locale} onSelect={onSelect} emptyText={t("这一天还没有贴纸")} />
        )}
      </div>

      {/* 撒一把游乐场 */}
      {playing && (
        <div className="absolute inset-0 z-40 bg-surface">
          <div className="absolute inset-x-0 top-[env(safe-area-inset-top)] z-10 pt-2 text-center text-xs text-label/60">
            {t("倾斜手机，贴纸会到处跑")}
          </div>
          <StickerSandbox
            photos={monthPhotos}
            freshId={null}
            getSpawnRect={() => null}
            registerOrientationRequester={() => {}}
          />
        </div>
      )}

      {mode === "month" && monthPhotos.length > 0 && (
        <button
          onClick={() => setPlaying((v) => !v)}
          aria-label="playground"
          className="absolute bottom-28 right-5 z-50 grid h-13 w-13 place-items-center rounded-full bg-klein text-white shadow-[0_6px_14px_rgba(0,47,167,0.35)]"
          style={{ height: 52, width: 52 }}
        >
          {playing ? "✕" : "✦"}
        </button>
      )}
    </div>
  );
}

function MonthView({
  anchor,
  byDay,
  locale,
  onPickDay,
}: {
  anchor: number;
  byDay: Map<number, PhotoRecord[]>;
  locale: string;
  onPickDay: (day: number) => void;
}) {
  const first = new Date(anchor);
  first.setDate(1);
  first.setHours(0, 0, 0, 0);
  const leading = first.getDay(); // 周日起
  const daysInMonth = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  const cells: (number | null)[] = [];
  for (let i = 0; i < leading; i++) cells.push(null);
  for (let d = 0; d < daysInMonth; d++) cells.push(first.getTime() + d * DAY_MS);
  while (cells.length % 7 !== 0) cells.push(null);

  const weekdays = Array.from({ length: 7 }, (_, i) =>
    new Date(2023, 0, 1 + i).toLocaleDateString(locale, { weekday: "narrow" })
  );
  const todayStart = startOfDay(Date.now());

  return (
    <div className="px-3 py-2">
      <div className="grid grid-cols-7">
        {weekdays.map((w, i) => (
          <div key={i} className="pb-1 text-center text-[11px] font-medium text-label/50">
            {w}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1.5">
        {cells.map((day, i) => {
          if (day == null) return <div key={i} className="aspect-square" />;
          const items = byDay.get(startOfDay(day)) ?? [];
          const isToday = startOfDay(day) === todayStart;
          const dayNum = new Date(day).getDate();
          return (
            <button
              key={i}
              onClick={() => items.length && onPickDay(day)}
              className="relative aspect-square"
              style={isToday ? { outline: `2px solid ${ACCENT}`, outlineOffset: -1, borderRadius: 8 } : undefined}
            >
              {items.length ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={display(items[0])}
                  alt=""
                  className="h-full w-full rounded-lg border-2 border-white object-cover shadow-sm"
                  draggable={false}
                />
              ) : (
                <div className="h-full w-full rounded-lg bg-chip" />
              )}
              <span
                className={`absolute left-0.5 top-0.5 rounded-full px-1 font-mono text-[10px] ${
                  items.length ? "bg-black/45 text-white" : "text-label/40"
                } ${isToday ? "font-bold" : ""}`}
              >
                {dayNum}
              </span>
              {items.length > 1 && (
                <span className="absolute bottom-0.5 right-0.5 rounded-full bg-card px-1 text-[9px] font-bold text-label">
                  {items.length}
                </span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function WeekView({
  anchor,
  byDay,
  weekStart,
  locale,
  onPickDay,
}: {
  anchor: number;
  byDay: Map<number, PhotoRecord[]>;
  weekStart: (ts: number) => number;
  locale: string;
  onPickDay: (day: number) => void;
}) {
  const ws = weekStart(anchor);
  const days = Array.from({ length: 7 }, (_, i) => ws + i * DAY_MS);
  const tilt = [-3, 2.5, -1.5, 3, -2, 1.5];
  const todayStart = startOfDay(Date.now());
  return (
    <div className="flex gap-1 px-2.5 py-3">
      {days.map((day, di) => {
        const items = byDay.get(startOfDay(day)) ?? [];
        const isToday = startOfDay(day) === todayStart;
        return (
          <div key={di} className="flex flex-1 flex-col items-center gap-2">
            <div className="flex flex-col items-center">
              <span className="text-[10px] text-label/50">
                {new Date(day).toLocaleDateString(locale, { weekday: "narrow" })}
              </span>
              <span
                className={`grid h-6 w-6 place-items-center rounded-full font-mono text-[13px] font-bold ${
                  isToday ? "text-white" : "text-label"
                }`}
                style={isToday ? { backgroundColor: ACCENT } : undefined}
              >
                {new Date(day).getDate()}
              </span>
            </div>
            <div className="flex flex-col gap-1.5">
              {items.map((p, idx) => (
                <button key={p.id} onClick={() => onPickDay(day)} style={{ transform: `rotate(${tilt[idx % tilt.length]}deg)` }}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={display(p)}
                    alt=""
                    className="w-full rounded-md bg-card p-0.5 shadow-sm"
                    draggable={false}
                  />
                </button>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function DayView({
  items,
  locale,
  onSelect,
  emptyText,
}: {
  items: PhotoRecord[];
  locale: string;
  onSelect: (p: PhotoRecord) => void;
  emptyText: string;
}) {
  const sorted = [...items].sort((a, b) => b.timestamp - a.timestamp);
  if (sorted.length === 0) {
    return <div className="pt-16 text-center text-sm text-label/50">{emptyText}</div>;
  }
  return (
    <div className="grid grid-cols-2 gap-3.5 p-4">
      {sorted.map((p) => (
        <button key={p.id} onClick={() => onSelect(p)} className="flex flex-col items-center gap-1.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={display(p)}
            alt=""
            className="w-full rounded-xl bg-card p-2 shadow-md"
            draggable={false}
          />
          <span className="font-mono text-[11px] text-label/50">
            {new Date(p.timestamp).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" })}
          </span>
        </button>
      ))}
    </div>
  );
}
