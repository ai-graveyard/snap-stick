// 把 AI 生成的「白底贴纸」抠成一张单独的贴纸：
// 纯前端 canvas 实现 —— 从四条边做洪水填充，移除与边缘相连的近背景色像素
// （保留主体内部的浅色/白色细节），再裁切到主体外接框，最后补一圈白色模切边。
// 之所以从边缘填充而不是全局去白，是为了不误删主体里的白色（眼睛高光、衣服等）。

const WORK_MAX = 512; // 抠图工作分辨率上限（兼顾效果与性能）
const T1 = 40; // 距背景色 < T1 视为纯背景（alpha 0）
const T2 = 128; // T1~T2 之间按距离做羽化，减少白边毛刺
const BORDER_RATIO = 0.02; // 白色模切描边宽度（相对工作尺寸）

export async function cutoutSticker(dataUrl: string): Promise<string> {
  const img = await loadImage(dataUrl);
  const scale = Math.min(1, WORK_MAX / Math.max(img.width, img.height));
  const w = Math.max(1, Math.round(img.width * scale));
  const h = Math.max(1, Math.round(img.height * scale));

  const src = document.createElement("canvas");
  src.width = w;
  src.height = h;
  const sctx = src.getContext("2d", { willReadFrequently: true });
  if (!sctx) return dataUrl;
  sctx.drawImage(img, 0, 0, w, h);
  const imageData = sctx.getImageData(0, 0, w, h);
  const px = imageData.data;

  // 以四角平均色作为背景色，容忍非纯白（轻微偏色/压缩噪点）
  const bg = sampleBackground(px, w, h);
  const dist = (i: number) => {
    const dr = px[i] - bg.r;
    const dg = px[i + 1] - bg.g;
    const db = px[i + 2] - bg.b;
    return Math.sqrt(dr * dr + dg * dg + db * db);
  };

  // 从四条边做洪水填充，标记「与边缘相连且接近背景色」的像素
  const isBg = new Uint8Array(w * h);
  const stack: number[] = [];
  const visit = (x: number, y: number) => {
    const p = y * w + x;
    if (isBg[p]) return;
    if (dist(p * 4) <= T2) {
      isBg[p] = 1;
      stack.push(p);
    }
  };
  for (let x = 0; x < w; x++) {
    visit(x, 0);
    visit(x, h - 1);
  }
  for (let y = 0; y < h; y++) {
    visit(0, y);
    visit(w - 1, y);
  }
  while (stack.length) {
    const p = stack.pop() as number;
    const x = p % w;
    const y = (p / w) | 0;
    if (x > 0) visit(x - 1, y);
    if (x < w - 1) visit(x + 1, y);
    if (y > 0) visit(x, y - 1);
    if (y < h - 1) visit(x, y + 1);
  }

  // 写入 alpha：背景相连像素按距离羽化；并顺便求主体外接框
  let minX = w;
  let minY = h;
  let maxX = -1;
  let maxY = -1;
  for (let p = 0; p < w * h; p++) {
    const i = p * 4;
    if (isBg[p]) {
      const d = dist(i);
      const a = d <= T1 ? 0 : Math.min(1, (d - T1) / (T2 - T1));
      px[i + 3] = Math.round(px[i + 3] * a);
    }
    if (px[i + 3] > 8) {
      const x = p % w;
      const y = (p / w) | 0;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < minX) return dataUrl; // 没抠出主体，回退原图
  sctx.putImageData(imageData, 0, 0);

  // 裁切到主体外接框
  const cropW = maxX - minX + 1;
  const cropH = maxY - minY + 1;
  const cut = document.createElement("canvas");
  cut.width = cropW;
  cut.height = cropH;
  cut.getContext("2d")?.drawImage(src, minX, minY, cropW, cropH, 0, 0, cropW, cropH);

  const border = Math.max(2, Math.round(Math.max(w, h) * BORDER_RATIO));
  return addStickerBorder(cut, border);
}

// 在抠好的主体外补一圈实心白色模切边，做出贴纸质感
function addStickerBorder(cut: HTMLCanvasElement, b: number): string {
  // 主体白色剪影
  const sil = document.createElement("canvas");
  sil.width = cut.width;
  sil.height = cut.height;
  const silCtx = sil.getContext("2d");
  if (!silCtx) return cut.toDataURL("image/png");
  silCtx.drawImage(cut, 0, 0);
  silCtx.globalCompositeOperation = "source-in";
  silCtx.fillStyle = "#ffffff";
  silCtx.fillRect(0, 0, sil.width, sil.height);

  const out = document.createElement("canvas");
  out.width = cut.width + b * 2;
  out.height = cut.height + b * 2;
  const octx = out.getContext("2d");
  if (!octx) return cut.toDataURL("image/png");
  // 在半径 b 的圆盘范围内多次偏移绘制剪影，叠出实心白边
  const b2 = b * b;
  for (let dy = -b; dy <= b; dy++) {
    for (let dx = -b; dx <= b; dx++) {
      if (dx * dx + dy * dy <= b2) octx.drawImage(sil, b + dx, b + dy);
    }
  }
  octx.drawImage(cut, b, b); // 主体绘制在白边之上
  return out.toDataURL("image/png");
}

function sampleBackground(px: Uint8ClampedArray, w: number, h: number) {
  const corners = [0, (w - 1) * 4, (h - 1) * w * 4, ((h - 1) * w + w - 1) * 4];
  let r = 0;
  let g = 0;
  let b = 0;
  for (const i of corners) {
    r += px[i];
    g += px[i + 1];
    b += px[i + 2];
  }
  return { r: r / 4, g: g / 4, b: b / 4 };
}

function loadImage(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = dataUrl;
  });
}
