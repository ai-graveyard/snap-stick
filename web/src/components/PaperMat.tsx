"use client";

// 照片窗口内的衬纸：渐变底 + 居中贴纸 + 可选装饰。
// 对应 iOS PaperFrameView.swift 的 PaperMat / PaperDecoView。
// 复用于结果页相纸窗口、选择器缩略图与日历代表图。

import type { PaperDeco, PaperStyle } from "@/lib/paperStyles";

interface PaperMatProps {
  style: PaperStyle;
  /** 贴纸图（优先抠图） */
  image: string;
  /** 贴纸相对衬纸的内边距比例 */
  insetRatio?: number;
  className?: string;
}

export default function PaperMat({ style, image, insetRatio = 0.1, className }: PaperMatProps) {
  return (
    <div
      className={`relative h-full w-full overflow-hidden ${className ?? ""}`}
      style={{ background: `linear-gradient(to bottom, ${style.matTop}, ${style.matBottom})` }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={image}
        alt=""
        draggable={false}
        className="absolute inset-0 h-full w-full object-contain"
        style={{ padding: `${insetRatio * 100}%` }}
      />
      <PaperDecoLayer deco={style.deco} />
    </div>
  );
}

/** 相纸装饰层 */
function PaperDecoLayer({ deco }: { deco: PaperDeco }) {
  if (deco === "none") return null;

  if (deco === "perforations") {
    // 左右两列胶片齿孔
    const holes = Array.from({ length: 8 });
    const column = (
      <div className="flex h-full flex-col items-center justify-between py-[3%]">
        {holes.map((_, i) => (
          <span key={i} className="h-[5%] w-[8px] rounded-sm bg-black/55" />
        ))}
      </div>
    );
    return (
      <div className="pointer-events-none absolute inset-0 flex justify-between px-[2%]">
        {column}
        {column}
      </div>
    );
  }

  if (deco === "dots") {
    // 顶部一排手帐圆点
    return (
      <div className="pointer-events-none absolute inset-x-0 top-[4%] flex justify-center gap-[4%]">
        {Array.from({ length: 6 }).map((_, i) => (
          <span key={i} className="h-[3px] w-[3px] rounded-full bg-white/50" />
        ))}
      </div>
    );
  }

  // washiTape：左上角一条仿和纸胶带（容器为正方形，% 宽高等比）
  return (
    <div
      className="pointer-events-none absolute left-[-4%] top-[5%] z-10 -rotate-[18deg] border border-white/40"
      style={{ width: "36%", height: "7%", backgroundColor: "rgba(0,47,167,0.35)" }}
    />
  );
}
