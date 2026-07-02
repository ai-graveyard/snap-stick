"use client";

// 从底部弹出的相纸选择面板（对应 iOS PaperUI.swift 的 PaperPickerSheet）。
// 全部相纸均可直接选用，选中即套用并关闭。

import { motion, AnimatePresence } from "framer-motion";
import PaperFrame from "@/components/PaperFrame";
import { PAPER_CATALOG, type PaperStyle } from "@/lib/paperStyles";
import { useSettings } from "@/contexts/SettingsContext";

interface PaperPickerSheetProps {
  open: boolean;
  selectedID: string;
  /** 缩略图预览用的贴纸图（当前作品的展示图） */
  sampleImage: string;
  onPick: (style: PaperStyle) => void;
  onClose: () => void;
}

export default function PaperPickerSheet({
  open,
  selectedID,
  sampleImage,
  onPick,
  onClose,
}: PaperPickerSheetProps) {
  const { t } = useSettings();
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
            className="safe-bottom absolute inset-x-0 bottom-0 max-h-[80vh] overflow-hidden rounded-t-3xl bg-card text-label shadow-2xl"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", damping: 30, stiffness: 300 }}
          >
            <div className="flex justify-center pt-2.5">
              <span className="h-1.5 w-9 rounded-full bg-black/20" />
            </div>
            <div className="flex items-center justify-between px-5 pb-2 pt-3.5">
              <h2 className="text-[17px] font-bold">{t("选择相纸")}</h2>
              <button
                onClick={onClose}
                aria-label={t("完成")}
                className="text-2xl leading-none text-label/30 active:text-label/50"
              >
                ⊗
              </button>
            </div>
            <div className="grid max-h-[60vh] grid-cols-3 gap-4 overflow-y-auto px-5 py-2 sm:grid-cols-4">
              {PAPER_CATALOG.map((style) => {
                const selected = style.id === selectedID;
                return (
                  <button
                    key={style.id}
                    onClick={() => {
                      onPick(style);
                      onClose();
                    }}
                    className="flex flex-col items-center gap-1.5"
                  >
                    <div
                      className={`w-full overflow-hidden rounded-lg ${
                        selected ? "ring-[3px] ring-klein" : ""
                      }`}
                    >
                      <PaperFrame style={style} image={sampleImage} date={Date.now()} showDate={false} />
                    </div>
                    <span
                      className={`truncate text-[11px] ${
                        selected ? "font-bold text-klein" : "text-label/75"
                      }`}
                    >
                      {t(style.name)}
                    </span>
                  </button>
                );
              })}
            </div>
          </motion.section>
        </div>
      )}
    </AnimatePresence>
  );
}
