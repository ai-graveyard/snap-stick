// 「相纸」目录（单一来源，对应 iOS 的 PaperStyle.swift / PaperCatalog）。
// 相纸只决定最终产出的边框 / 衬纸 / 版式外观，不影响抠图、物理与音效。全部免费、随时可切换。

export type PaperDeco = "none" | "perforations" | "washiTape" | "dots";

export interface PaperStyle {
  id: string;
  /** 名称（i18n key，中文原文） */
  name: string;
  /** 照片衬纸渐变上 / 下色；纯色时两者相同 */
  matTop: string;
  matBottom: string;
  /** 相纸边框 / 底部白边色 */
  border: string;
  /** 日期等文字色 */
  captionInk: string;
  /** 装饰 */
  deco: PaperDeco;
}

export const DEFAULT_PAPER_ID = "cream";

export const PAPER_CATALOG: PaperStyle[] = [
  {
    id: "cream",
    name: "经典奶油白",
    matTop: "#F6EFDF",
    matBottom: "#F3EDE1",
    border: "#FCFCF8",
    captionInk: "#666666",
    deco: "none",
  },
  {
    id: "kraft",
    name: "牛皮手帐",
    matTop: "#D5C4A8",
    matBottom: "#C7B296",
    border: "#B8A385",
    captionInk: "#3D3326",
    deco: "dots",
  },
  {
    id: "klein",
    name: "克莱因蓝",
    matTop: "#F6EFDF",
    matBottom: "#F6EFDF",
    border: "#002FA7",
    captionInk: "#002FA7",
    deco: "none",
  },
  {
    id: "amber-glow",
    name: "琥珀暖光",
    matTop: "#F5A845",
    matBottom: "#D18529",
    border: "#DB9438",
    captionInk: "#FFFFFF",
    deco: "none",
  },
  {
    id: "deep-sea",
    name: "深海渐变",
    matTop: "#002FA7",
    matBottom: "#001F77",
    border: "#001F77",
    captionInk: "#FFFFFF",
    deco: "none",
  },
  {
    id: "film-charcoal",
    name: "炭灰胶片",
    matTop: "#212121",
    matBottom: "#0F0F0F",
    border: "#29292E",
    captionInk: "#FFFFFF",
    deco: "perforations",
  },
  {
    id: "journal-washi",
    name: "手帐胶带",
    matTop: "#F6EFDF",
    matBottom: "#F6EFDF",
    border: "#F7F2E8",
    captionInk: "#3D3326",
    deco: "washiTape",
  },
];

export function paperStyle(id: string | undefined): PaperStyle {
  return PAPER_CATALOG.find((s) => s.id === id) ?? PAPER_CATALOG[0];
}
