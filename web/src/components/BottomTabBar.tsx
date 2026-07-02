"use client";

// 底部悬浮玻璃 Tab 栏（对应 iOS TabView 的 Liquid Glass 底栏）：
// 日历 / 拍照 / 设置，选中项克莱因蓝。

import { useSettings } from "@/contexts/SettingsContext";

export type Tab = "calendar" | "home" | "profile";

interface BottomTabBarProps {
  tab: Tab;
  onChange: (tab: Tab) => void;
}

export default function BottomTabBar({ tab, onChange }: BottomTabBarProps) {
  const { t } = useSettings();

  const items: { key: Tab; label: string; icon: React.ReactNode }[] = [
    {
      key: "calendar",
      label: t("日历"),
      icon: (
        <>
          <rect x="3" y="4" width="18" height="18" rx="2" />
          <path d="M16 2v4M8 2v4M3 10h18" />
        </>
      ),
    },
    {
      key: "home",
      label: t("拍照"),
      icon: (
        <>
          <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3Z" />
          <circle cx="12" cy="13" r="3.5" />
        </>
      ),
    },
    {
      key: "profile",
      label: t("设置"),
      icon: (
        <>
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.03 1.56V21a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-1.03-1.56 1.7 1.7 0 0 0-1.88.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.56-1.03H3a2 2 0 1 1 0-4h.09A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.34-1.88l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.56V3a2 2 0 1 1 4 0v.09A1.7 1.7 0 0 0 15 4.6a1.7 1.7 0 0 0 1.88-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.4 9c.13.53.74.97 1.56.97H21a2 2 0 1 1 0 4h-.09A1.7 1.7 0 0 0 19.4 15Z" />
        </>
      ),
    },
  ];

  return (
    <nav className="safe-bottom pointer-events-none fixed inset-x-0 bottom-0 z-50 flex justify-center pb-3">
      <div className="pointer-events-auto flex items-center gap-1 rounded-full border border-black/5 bg-card/80 px-2 py-1.5 shadow-[0_8px_24px_rgba(0,0,0,0.15)] backdrop-blur-xl dark:border-white/10">
        {items.map((item) => {
          const active = tab === item.key;
          return (
            <button
              key={item.key}
              onClick={() => onChange(item.key)}
              aria-label={item.label}
              aria-current={active}
              className={`flex flex-col items-center gap-0.5 rounded-full px-5 py-1.5 transition-colors ${
                active ? "text-klein" : "text-label/45"
              }`}
            >
              <svg
                width="22"
                height="22"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                {item.icon}
              </svg>
              <span className={`text-[10px] ${active ? "font-semibold" : "font-medium"}`}>
                {item.label}
              </span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}
