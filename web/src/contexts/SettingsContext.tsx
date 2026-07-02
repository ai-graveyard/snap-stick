"use client";

// 全局应用设置（对应 iOS 的 AppSettings.swift）。
// 持有：主题外观、界面语言、贴纸物理（速度/灵敏度）、历史显示数量。
// 持久化到 localStorage（替代 UserDefaults）；并把 dark class 同步到 <html>。

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { translate, type Lang } from "@/lib/i18n";

export type Appearance = "system" | "light" | "dark";
export type Language = "system" | "zh" | "en";

export const DEFAULT_SPEED = 3.6;
export const DEFAULT_SENSITIVITY = 2.2;
export const DEFAULT_VISIBLE_COUNT = 6;

const KEYS = {
  appearance: "app.appearance",
  language: "app.language",
  speed: "sticker.speed",
  sensitivity: "sticker.sensitivity",
  visibleCount: "history.visibleCount",
} as const;

interface SettingsValue {
  appearance: Appearance;
  setAppearance: (a: Appearance) => void;
  language: Language;
  setLanguage: (l: Language) => void;
  speed: number;
  setSpeed: (n: number) => void;
  sensitivity: number;
  setSensitivity: (n: number) => void;
  visibleCount: number;
  setVisibleCount: (n: number) => void;
  /** 实际生效的语言（system → 浏览器语言判定） */
  lang: Lang;
  /** 取译文便捷函数 */
  t: (key: string, ...args: (string | number)[]) => string;
}

const SettingsContext = createContext<SettingsValue | null>(null);

function readString<T extends string>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  const v = window.localStorage.getItem(key);
  return (v as T) ?? fallback;
}

function readNumber(key: string, fallback: number): number {
  if (typeof window === "undefined") return fallback;
  const v = window.localStorage.getItem(key);
  const n = v == null ? NaN : Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function resolveLang(language: Language): Lang {
  if (language === "zh" || language === "en") return language;
  if (typeof navigator !== "undefined" && navigator.language?.toLowerCase().startsWith("zh")) {
    return "zh";
  }
  // system 且非中文环境时默认中文（本应用以中文为主），仅明确英文环境走 en
  if (typeof navigator !== "undefined" && navigator.language) {
    return navigator.language.toLowerCase().startsWith("en") ? "en" : "zh";
  }
  return "zh";
}

export function SettingsProvider({ children }: { children: React.ReactNode }) {
  // 初值在 SSR 用默认，挂载后从 localStorage 读取（避免 hydration 报错）
  const [appearance, setAppearanceState] = useState<Appearance>("system");
  const [language, setLanguageState] = useState<Language>("system");
  const [speed, setSpeedState] = useState(DEFAULT_SPEED);
  const [sensitivity, setSensitivityState] = useState(DEFAULT_SENSITIVITY);
  const [visibleCount, setVisibleCountState] = useState(DEFAULT_VISIBLE_COUNT);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setAppearanceState(readString<Appearance>(KEYS.appearance, "system"));
    setLanguageState(readString<Language>(KEYS.language, "system"));
    setSpeedState(readNumber(KEYS.speed, DEFAULT_SPEED));
    setSensitivityState(readNumber(KEYS.sensitivity, DEFAULT_SENSITIVITY));
    setVisibleCountState(readNumber(KEYS.visibleCount, DEFAULT_VISIBLE_COUNT));
    setMounted(true);
  }, []);

  const persist = useCallback((key: string, value: string | number) => {
    if (typeof window !== "undefined") window.localStorage.setItem(key, String(value));
  }, []);

  const setAppearance = useCallback(
    (a: Appearance) => {
      setAppearanceState(a);
      persist(KEYS.appearance, a);
    },
    [persist]
  );
  const setLanguage = useCallback(
    (l: Language) => {
      setLanguageState(l);
      persist(KEYS.language, l);
    },
    [persist]
  );
  const setSpeed = useCallback(
    (n: number) => {
      setSpeedState(n);
      persist(KEYS.speed, n);
    },
    [persist]
  );
  const setSensitivity = useCallback(
    (n: number) => {
      setSensitivityState(n);
      persist(KEYS.sensitivity, n);
    },
    [persist]
  );
  const setVisibleCount = useCallback(
    (n: number) => {
      setVisibleCountState(n);
      persist(KEYS.visibleCount, n);
    },
    [persist]
  );

  // 主题：按 appearance 给 <html> 切 dark class；system 时跟随 prefers-color-scheme
  useEffect(() => {
    if (!mounted) return;
    const root = document.documentElement;
    const mql = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark = appearance === "dark" || (appearance === "system" && mql.matches);
      root.classList.toggle("dark", dark);
    };
    apply();
    if (appearance === "system") {
      mql.addEventListener("change", apply);
      return () => mql.removeEventListener("change", apply);
    }
  }, [appearance, mounted]);

  // 挂载前用固定 "zh"，确保 SSR 与首帧客户端渲染一致（避免 hydration 不匹配）；
  // 挂载后再按设置/浏览器语言解析。
  const lang = useMemo<Lang>(() => (mounted ? resolveLang(language) : "zh"), [language, mounted]);

  // 语言同步到 <html lang>
  useEffect(() => {
    if (mounted) document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
  }, [lang, mounted]);

  const t = useCallback(
    (key: string, ...args: (string | number)[]) => translate(key, lang, ...args),
    [lang]
  );

  const value = useMemo<SettingsValue>(
    () => ({
      appearance,
      setAppearance,
      language,
      setLanguage,
      speed,
      setSpeed,
      sensitivity,
      setSensitivity,
      visibleCount,
      setVisibleCount,
      lang,
      t,
    }),
    [
      appearance,
      setAppearance,
      language,
      setLanguage,
      speed,
      setSpeed,
      sensitivity,
      setSensitivity,
      visibleCount,
      setVisibleCount,
      lang,
      t,
    ]
  );

  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsValue {
  const ctx = useContext(SettingsContext);
  if (!ctx) throw new Error("useSettings must be used within SettingsProvider");
  return ctx;
}
