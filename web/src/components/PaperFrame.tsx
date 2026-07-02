"use client";

// 一张完整的「相纸」卡：边框 + 方形衬纸照片 + 底部日期。
// 对应 iOS PaperFrameView.swift。用于相纸选择器缩略图。

import PaperMat from "@/components/PaperMat";
import type { PaperStyle } from "@/lib/paperStyles";
import { useSettings } from "@/contexts/SettingsContext";

interface PaperFrameProps {
  style: PaperStyle;
  image: string;
  date: number;
  /** 是否显示底部日期（缩略图可隐藏以保持紧凑） */
  showDate?: boolean;
  className?: string;
}

export default function PaperFrame({ style, image, date, showDate = true, className }: PaperFrameProps) {
  const { lang } = useSettings();
  return (
    <div
      className={`overflow-hidden ${className ?? ""}`}
      style={{ backgroundColor: style.border, padding: "5.5%", borderRadius: "4px" }}
    >
      <div className="aspect-square w-full overflow-hidden rounded-[2px]">
        <PaperMat style={style} image={image} />
      </div>
      {showDate && (
        <div className="flex items-center px-[1%]" style={{ height: "20%" }}>
          <span className="truncate text-[9px] font-medium" style={{ color: style.captionInk }}>
            {formatDate(date, lang)}
          </span>
        </div>
      )}
    </div>
  );
}

function formatDate(ts: number, lang: "zh" | "en") {
  return new Date(ts).toLocaleDateString(lang === "zh" ? "zh-CN" : "en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}
