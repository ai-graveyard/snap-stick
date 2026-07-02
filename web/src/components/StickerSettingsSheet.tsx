"use client";

// 贴纸物理设置弹层（对应 iOS SettingsView.swift）：移动速度 / 倾斜灵敏度 + 重置。
// 读写全局 SettingsContext。

import { motion, AnimatePresence } from "framer-motion";
import {
  useSettings,
  DEFAULT_SPEED,
  DEFAULT_SENSITIVITY,
} from "@/contexts/SettingsContext";

interface StickerSettingsSheetProps {
  open: boolean;
  onClose: () => void;
}

export default function StickerSettingsSheet({ open, onClose }: StickerSettingsSheetProps) {
  const { t, speed, setSpeed, sensitivity, setSensitivity } = useSettings();

  return (
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-[80]">
          <motion.button
            type="button"
            aria-label={t("取消")}
            onClick={onClose}
            className="absolute inset-0 bg-black/40"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          />
          <motion.section
            className="safe-bottom absolute inset-x-0 bottom-0 rounded-t-3xl bg-card text-label shadow-2xl"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", damping: 30, stiffness: 300 }}
          >
            <div className="flex justify-center pt-2.5">
              <span className="h-1.5 w-9 rounded-full bg-black/20" />
            </div>
            <div className="flex items-center justify-between px-5 pb-2 pt-3.5">
              <h2 className="text-[17px] font-bold">{t("贴纸设置")}</h2>
              <button onClick={onClose} className="text-sm font-semibold text-klein">
                {t("完成")}
              </button>
            </div>

            <div className="space-y-5 px-5 pb-8 pt-3">
              <Slider
                label={t("移动速度")}
                value={speed}
                min={0.5}
                max={6}
                step={0.05}
                onChange={setSpeed}
              />
              <Slider
                label={t("倾斜灵敏度")}
                value={sensitivity}
                min={0.5}
                max={3}
                step={0.05}
                onChange={setSensitivity}
              />
              <button
                onClick={() => {
                  setSpeed(DEFAULT_SPEED);
                  setSensitivity(DEFAULT_SENSITIVITY);
                }}
                className="w-full rounded-xl bg-chip py-2.5 text-sm font-semibold text-label active:opacity-80"
              >
                {t("重置为默认")}
              </button>
            </div>
          </motion.section>
        </div>
      )}
    </AnimatePresence>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (n: number) => void;
}) {
  return (
    <label className="block">
      <div className="mb-1.5 flex items-center justify-between text-sm">
        <span>{label}</span>
        <span className="font-mono text-label/50">{value.toFixed(2)}x</span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.currentTarget.value))}
        className="w-full accent-klein"
      />
    </label>
  );
}
