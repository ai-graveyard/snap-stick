// 把当前相纸卡渲染成 PNG 并分享（对应 iOS 的 PaperRenderer + ShareSheet）。
// 优先 navigator.share({ files })；不支持则回退为下载。

import { paperStyle, type PaperStyle } from "@/lib/paperStyles";

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function drawDeco(ctx: CanvasRenderingContext2D, style: PaperStyle, mx: number, my: number, side: number) {
  if (style.deco === "perforations") {
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    const cols = [mx + side * 0.03, mx + side - side * 0.03 - side * 0.03];
    const holeW = side * 0.03;
    const holeH = side * 0.05;
    for (const cx of cols) {
      for (let i = 0; i < 8; i++) {
        const y = my + side * 0.04 + i * (side * 0.085);
        ctx.fillRect(cx, y, holeW, holeH);
      }
    }
  } else if (style.deco === "dots") {
    ctx.fillStyle = "rgba(255,255,255,0.5)";
    const r = side * 0.009;
    const gap = side * 0.05;
    const total = 6 * (r * 2) + 5 * gap;
    let x = mx + (side - total) / 2 + r;
    const y = my + side * 0.06;
    for (let i = 0; i < 6; i++) {
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      x += r * 2 + gap;
    }
  } else if (style.deco === "washiTape") {
    ctx.save();
    ctx.translate(mx + side * 0.13, my + side * 0.1);
    ctx.rotate((-18 * Math.PI) / 180);
    ctx.fillStyle = "rgba(0,47,167,0.35)";
    ctx.strokeStyle = "rgba(255,255,255,0.4)";
    ctx.lineWidth = side * 0.004;
    ctx.fillRect(-side * 0.05, 0, side * 0.36, side * 0.07);
    ctx.strokeRect(-side * 0.05, 0, side * 0.36, side * 0.07);
    ctx.restore();
  }
}

/** 渲染相纸卡为 PNG Blob。 */
export async function renderPaperImage(
  styleID: string,
  image: string,
  date: number,
  lang: "zh" | "en"
): Promise<Blob | null> {
  const style = paperStyle(styleID);
  const W = 1080;
  const pad = W * 0.055;
  const inner = W - pad * 2;
  const captionH = W * 0.2;
  const H = pad + inner + captionH + pad;

  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  // 边框底
  ctx.fillStyle = style.border;
  roundRect(ctx, 0, 0, W, H, W * 0.02);
  ctx.fill();

  // 衬纸渐变（方形）
  const mx = pad;
  const my = pad;
  const grad = ctx.createLinearGradient(0, my, 0, my + inner);
  grad.addColorStop(0, style.matTop);
  grad.addColorStop(1, style.matBottom);
  ctx.save();
  roundRect(ctx, mx, my, inner, inner, W * 0.012);
  ctx.clip();
  ctx.fillStyle = grad;
  ctx.fillRect(mx, my, inner, inner);

  // 贴纸（object-contain，inset 10%）
  try {
    const img = await loadImage(image);
    const innerInset = inner * 0.1;
    const box = inner - innerInset * 2;
    const scale = Math.min(box / img.width, box / img.height);
    const dw = img.width * scale;
    const dh = img.height * scale;
    ctx.drawImage(img, mx + (inner - dw) / 2, my + (inner - dh) / 2, dw, dh);
  } catch {
    // 图片加载失败则只留底色
  }

  drawDeco(ctx, style, mx, my, inner);
  ctx.restore();

  // 底部日期
  ctx.fillStyle = style.captionInk;
  ctx.font = `500 ${W * 0.045}px var(--font-inter), system-ui, sans-serif`;
  ctx.textBaseline = "middle";
  const dateStr = new Date(date).toLocaleDateString(lang === "zh" ? "zh-CN" : "en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  ctx.fillText(dateStr, mx + W * 0.01, my + inner + captionH / 2);

  return new Promise((resolve) => canvas.toBlob((b) => resolve(b), "image/png"));
}

/** 渲染并分享（或下载）相纸卡。返回 false 表示渲染失败。 */
export async function sharePaperImage(
  styleID: string,
  image: string,
  date: number,
  lang: "zh" | "en"
): Promise<boolean> {
  const blob = await renderPaperImage(styleID, image, date, lang);
  if (!blob) return false;
  const file = new File([blob], `snapstick-${date}.png`, { type: "image/png" });

  const nav = navigator as Navigator & {
    canShare?: (data: { files: File[] }) => boolean;
    share?: (data: { files: File[] }) => Promise<void>;
  };
  if (nav.share && nav.canShare?.({ files: [file] })) {
    try {
      await nav.share({ files: [file] });
      return true;
    } catch {
      // 用户取消分享：当作完成，不回退下载
      return true;
    }
  }

  // 回退：触发下载
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = file.name;
  a.click();
  URL.revokeObjectURL(url);
  return true;
}
