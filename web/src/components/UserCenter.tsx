"use client";

// 设置中心（对应 iOS UserCenterView.swift）：上半作品统计，下半设置列表
// —— 主题外观、界面语言、历史记录、贴纸物理、关于。

import { useMemo } from "react";
import {
  useSettings,
  type Appearance,
  type Language,
} from "@/contexts/SettingsContext";
import type { PhotoRecord } from "@/types";

interface UserCenterProps {
  photos: PhotoRecord[];
  onOpenHistory: () => void;
  onOpenSettings: () => void;
}

const APP_VERSION = "1.0";

export default function UserCenter({ photos, onOpenHistory, onOpenSettings }: UserCenterProps) {
  const { t, appearance, setAppearance, language, setLanguage } = useSettings();

  const { thisMonth, activeDays } = useMemo(() => {
    const now = new Date();
    const month = photos.filter((p) => {
      const d = new Date(p.timestamp);
      return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
    }).length;
    const days = new Set(
      photos.map((p) => {
        const d = new Date(p.timestamp);
        d.setHours(0, 0, 0, 0);
        return d.getTime();
      })
    ).size;
    return { thisMonth: month, activeDays: days };
  }, [photos]);

  const appearanceOptions: [Appearance, string][] = [
    ["system", t("跟随系统")],
    ["light", t("白天")],
    ["dark", t("黑夜")],
  ];
  const languageOptions: [Language, string][] = [
    ["system", t("跟随系统")],
    ["zh", t("中文")],
    ["en", t("English")],
  ];

  return (
    <div className="absolute inset-0 overflow-y-auto bg-surface pt-[env(safe-area-inset-top)] text-label">
      <div className="space-y-5 px-5 pb-28 pt-6">
        {/* 统计 */}
        <div className="flex gap-3">
          <StatCard value={photos.length} label={t("总贴纸")} />
          <StatCard value={thisMonth} label={t("本月")} />
          <StatCard value={activeDays} label={t("活跃天数")} />
        </div>

        {/* 设置列表 */}
        <div className="overflow-hidden rounded-2xl bg-card shadow-[0_6px_16px_rgba(61,51,38,0.06)]">
          <Row icon={<HalfCircle />}>
            <div className="flex flex-col gap-2">
              <span className="text-[15px] font-medium">{t("主题外观")}</span>
              <Segmented value={appearance} options={appearanceOptions} onChange={setAppearance} />
            </div>
          </Row>
          <Divider />
          <Row icon={<Globe />}>
            <div className="flex flex-col gap-2">
              <span className="text-[15px] font-medium">{t("界面语言")}</span>
              <Segmented value={language} options={languageOptions} onChange={setLanguage} />
            </div>
          </Row>
          <Divider />
          <MenuRow
            icon={<HistoryIcon />}
            title={t("历史记录")}
            subtitle={t("回看与管理全部贴纸")}
            onClick={onOpenHistory}
          />
          <Divider />
          <MenuRow
            icon={<Sliders />}
            title={t("贴纸物理")}
            subtitle={t("移动速度与倾斜灵敏度")}
            onClick={onOpenSettings}
          />
          <Divider />
          <Row icon={<Info />}>
            <div className="flex flex-1 items-center justify-between">
              <div className="flex flex-col gap-0.5">
                <span className="text-[15px] font-medium">{t("关于拍立贴")}</span>
                <span className="text-[11px] text-label/50">{t("对准、按下快门，AI 把此刻冲印成贴纸")}</span>
              </div>
              <span className="font-mono text-xs text-label/40">v{APP_VERSION}</span>
            </div>
          </Row>
        </div>
      </div>
    </div>
  );
}

function StatCard({ value, label }: { value: number; label: string }) {
  return (
    <div className="flex flex-1 flex-col items-center gap-1 rounded-2xl bg-card py-4 shadow-[0_6px_16px_rgba(61,51,38,0.06)]">
      <span className="text-[22px] font-bold text-klein">{value}</span>
      <span className="text-[11px] text-label/50">{label}</span>
    </div>
  );
}

function Segmented<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: [T, string][];
  onChange: (v: T) => void;
}) {
  return (
    <div className="flex rounded-[10px] bg-chip p-0.5">
      {options.map(([key, label]) => {
        const sel = key === value;
        return (
          <button
            key={key}
            onClick={() => onChange(key)}
            className={`flex-1 rounded-lg py-2 text-sm transition-colors ${
              sel ? "bg-klein font-semibold text-white" : "font-normal text-label"
            }`}
          >
            {label}
          </button>
        );
      })}
    </div>
  );
}

function Row({ icon, children }: { icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3.5 px-4 py-3">
      <IconBubble>{icon}</IconBubble>
      <div className="flex-1">{children}</div>
    </div>
  );
}

function MenuRow({
  icon,
  title,
  subtitle,
  onClick,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  onClick: () => void;
}) {
  return (
    <button onClick={onClick} className="flex w-full items-center gap-3.5 px-4 py-3.5 text-left active:bg-chip/40">
      <IconBubble>{icon}</IconBubble>
      <div className="flex flex-1 flex-col gap-0.5">
        <span className="text-[15px] font-medium">{title}</span>
        <span className="text-[11px] text-label/50">{subtitle}</span>
      </div>
      <span className="text-label/40">›</span>
    </button>
  );
}

function IconBubble({ children }: { children: React.ReactNode }) {
  return (
    <span className="grid h-[30px] w-[30px] place-items-center rounded-full bg-klein/10 text-klein">
      {children}
    </span>
  );
}

function Divider() {
  return <div className="ml-14 border-t border-black/5 dark:border-white/10" />;
}

const sv = { width: 16, height: 16, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };

function HalfCircle() {
  return (
    <svg {...sv}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 3v18a9 9 0 0 0 0-18Z" fill="currentColor" />
    </svg>
  );
}
function Globe() {
  return (
    <svg {...sv}>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" />
    </svg>
  );
}
function HistoryIcon() {
  return (
    <svg {...sv}>
      <path d="M3 12a9 9 0 1 0 3-6.7" />
      <path d="M3 3v5h5" />
      <path d="M12 7v5l3 2" />
    </svg>
  );
}
function Sliders() {
  return (
    <svg {...sv}>
      <path d="M4 6h16M4 12h16M4 18h16" />
      <circle cx="9" cy="6" r="2" fill="currentColor" />
      <circle cx="15" cy="12" r="2" fill="currentColor" />
      <circle cx="8" cy="18" r="2" fill="currentColor" />
    </svg>
  );
}
function Info() {
  return (
    <svg {...sv}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5M12 8h.01" />
    </svg>
  );
}
