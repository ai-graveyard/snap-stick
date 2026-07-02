#!/usr/bin/env python3
"""Render the SnapStick instant-camera as the app icon (light / dark / tinted).

Faithful to the in-app `PolaroidStudioView` camera body:
  cream rounded body · charcoal faceplate (viewfinder + SNAPSTICK + klein dot) ·
  film-counter wheel (剩余, top-left) · cadmium shutter (按下快门, top-right) ·
  big lens (metallic ring → klein ring → black bezel → live preview) ·
  klein brand strip with centered white ticks · "Snap Ready" + klein dot.
The lens preview (a real shot in-app) is filled here with a warm mini-landscape.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SS = 4
N = 1024 * SS

# ---- brand palette (Palette.swift) ----
KLEIN      = (0, 47, 167)
KLEIN_DEEP = (0, 31, 119)
KLEIN_DARK = (0, 18, 70)
CADMIUM    = (252, 217, 54)
CREAM      = (248, 241, 225)
CREAM_DK   = (229, 219, 198)
FACEPLATE  = (41, 42, 46)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vgrad(w, h, stops):
    """stops: list of (pos0..1, color). Returns RGB image (1px col stretched)."""
    col = Image.new("RGB", (1, h))
    p = col.load()
    for y in range(h):
        t = y / max(1, h - 1)
        # find segment
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if t <= p1 or i == len(stops) - 2:
                lt = 0 if p1 == p0 else max(0, min(1, (t - p0) / (p1 - p0)))
                p[0, y] = lerp(c0, c1, lt)
                break
    return col.resize((w, h))


def load_font(size):
    for c in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/System/Library/Fonts/Helvetica.ttc"]:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def load_cjk(size):
    for c in ["/System/Library/Fonts/PingFang.ttc",
              "/System/Library/Fonts/STHeiti Medium.ttc",
              "/System/Library/Fonts/Hiragino Sans GB.ttc"]:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return load_font(size)


def tracked_text(d, center, text, font, fill, tracking):
    """Draw letter-spaced text centered at center=(cx, cy)."""
    widths = [d.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    asc, desc = font.getmetrics()
    x = center[0] - total / 2
    y = center[1] - (asc + desc) / 2
    for ch, w in zip(text, widths):
        d.text((x, y), ch, font=font, fill=fill)
        x += w + tracking


def disk_grad(img, cx, cy, r, stops):
    box = (int(cx - r), int(cy - r), int(cx + r), int(cy + r))
    w = box[2] - box[0]
    g = vgrad(w, w, stops)
    m = Image.new("L", (w, w), 0)
    ImageDraw.Draw(m).ellipse([0, 0, w - 1, w - 1], fill=255)
    img.paste(g, (box[0], box[1]), m)


def make_lens_glass(size):
    """Dark glass with an iridescent multi-colour lens-coating sheen / flare.
    Built small then upscaled (it's all soft blur)."""
    from PIL import ImageChops
    s0 = 360
    # dark glass base: deep-blue centre fading to near-black edge (radial)
    base = Image.new("RGB", (s0, s0))
    px = base.load()
    c0, c1 = (20, 24, 40), (4, 4, 9)
    cx = cy = s0 / 2
    maxd = (s0 / 2) * 1.05
    for y in range(s0):
        for x in range(s0):
            dd = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd
            dd = min(1.0, dd)
            px[x, y] = lerp(c0, c1, dd)

    # iridescent glints — soft colour blobs, screen-blended so they glow
    glints = Image.new("RGB", (s0, s0), (0, 0, 0))
    gd = ImageDraw.Draw(glints)
    blobs = [
        (0.30, 0.30, 0.26, (0, 150, 190)),    # cyan
        (0.68, 0.40, 0.22, (190, 50, 150)),   # magenta
        (0.58, 0.66, 0.24, (220, 160, 40)),   # gold
        (0.38, 0.62, 0.20, (90, 60, 200)),    # violet
        (0.74, 0.66, 0.16, (40, 180, 110)),   # green
        (0.50, 0.50, 0.30, (30, 60, 120)),    # broad blue wash
    ]
    for fx, fy, fr, col in blobs:
        bx, by, r = fx * s0, fy * s0, fr * s0
        gd.ellipse([bx - r, by - r, bx + r, by + r], fill=col)
    glints = glints.filter(ImageFilter.GaussianBlur(s0 * 0.07))
    out = ImageChops.screen(base, glints)

    # bright specular reflections (the glass catching light)
    spec = Image.new("RGB", (s0, s0), (0, 0, 0))
    sd = ImageDraw.Draw(spec)
    sd.ellipse([s0 * 0.20, s0 * 0.16, s0 * 0.44, s0 * 0.40], fill=(180, 205, 255))
    sd.ellipse([s0 * 0.62, s0 * 0.72, s0 * 0.72, s0 * 0.82], fill=(150, 170, 230))
    spec = spec.filter(ImageFilter.GaussianBlur(s0 * 0.04))
    out = ImageChops.screen(out, spec)

    # faint concentric element-reflection ring
    ring = Image.new("RGB", (s0, s0), (0, 0, 0))
    ImageDraw.Draw(ring).ellipse([s0 * 0.16, s0 * 0.16, s0 * 0.84, s0 * 0.84],
                                 outline=(40, 70, 120), width=int(s0 * 0.012))
    ring = ring.filter(ImageFilter.GaussianBlur(s0 * 0.01))
    out = ImageChops.screen(out, ring)

    return out.resize((size, size), Image.LANCZOS)


def draw_camera(bg_top, bg_bot, warm_glow=True):
    img = vgrad(N, N, [(0, bg_top), (1, bg_bot)])
    d = ImageDraw.Draw(img, "RGBA")
    s = SS

    bw = int(630 * s)
    bh = int(bw * 1.25)
    bx = (N - bw) // 2
    by = (N - bh) // 2
    camW = bw                       # proportional base == body width
    br = int(camW * 0.087)

    def cw(f):  # camW fraction -> px
        return int(camW * f)

    # warm glow halo behind body (echoes the app's amber bloom)
    if warm_glow:
        gl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(gl).rounded_rectangle(
            [bx - cw(0.04), by - cw(0.04), bx + bw + cw(0.04), by + bh + cw(0.04)],
            radius=br, fill=(255, 196, 92, 150))
        gl = gl.filter(ImageFilter.GaussianBlur(34 * s))
        img.paste(Image.new("RGB", (N, N), (255, 190, 90)), (0, 0), gl)

    # body shadow
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [bx, by + int(22 * s), bx + bw, by + bh + int(22 * s)], radius=br,
        fill=(15, 10, 4, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(26 * s))
    img.paste(Image.new("RGB", (N, N), (0, 0, 0)), (0, 0), sh)

    # body
    bmask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(bmask).rounded_rectangle([bx, by, bx + bw, by + bh], radius=br, fill=255)
    bg = vgrad(bw, bh, [(0, CREAM), (1, CREAM_DK)])
    img.paste(bg, (bx, by), bmask.crop((bx, by, bx + bw, by + bh)))
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=br,
                        outline=(*lerp(KLEIN, CREAM, 0.55), 255), width=max(2, int(2.5 * s)))

    # top paper slot (thin dark line near very top)
    d.rounded_rectangle([bx + cw(0.05), by + cw(0.02), bx + bw - cw(0.05), by + cw(0.02) + int(5 * s)],
                        radius=int(4 * s), fill=(28, 26, 22))

    # ---- faceplate ----
    fp_x0, fp_x1 = bx + cw(0.06), bx + bw - cw(0.06)
    fp_y0 = by + cw(0.06)
    fp_y1 = fp_y0 + cw(0.135)
    d.rounded_rectangle([fp_x0, fp_y0, fp_x1, fp_y1], radius=cw(0.04), fill=FACEPLATE)
    # viewfinder
    vf_w, vf_h = cw(0.1), cw(0.05)
    vf_x, vf_cy = fp_x0 + cw(0.05), (fp_y0 + fp_y1) // 2
    d.rounded_rectangle([vf_x, vf_cy - vf_h // 2, vf_x + vf_w, vf_cy + vf_h // 2],
                        radius=int(4 * s), fill=(10, 10, 12),
                        outline=(255, 255, 255, 46), width=max(1, int(1.5 * s)))
    # SNAPSTICK
    f_brand = load_font(cw(0.05))
    tracked_text(d, ((fp_x0 + fp_x1) // 2, vf_cy), "SNAPSTICK", f_brand,
                 (236, 236, 236), tracking=cw(0.022))
    # klein indicator
    ind_r, ind_x = cw(0.025), fp_x1 - cw(0.05)
    d.ellipse([ind_x - ind_r, vf_cy - ind_r, ind_x + ind_r, vf_cy + ind_r], fill=KLEIN)

    # ---- film-counter wheel (top-left), low opacity ----
    well_w, well_h = cw(0.113), cw(0.133)
    well_x = bx + cw(0.1)
    well_y = by + int(camW * 1.25 * 0.18)   # padding top camH*0.18
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ld_ = ImageDraw.Draw(layer, "RGBA")
    wg = vgrad(well_w, well_h, [(0, (20, 20, 20)), (1, (41, 41, 41))])
    wm = Image.new("L", (well_w, well_h), 0)
    ImageDraw.Draw(wm).rounded_rectangle([0, 0, well_w - 1, well_h - 1], radius=int(8 * s), fill=255)
    layer.paste(wg, (well_x, well_y), wm)
    ld_.rounded_rectangle([well_x, well_y, well_x + well_w, well_y + well_h],
                          radius=int(8 * s), outline=(0, 0, 0, 170), width=max(1, int(1.5 * s)))
    # ∞ glyph (member) in cadmium
    f_inf = load_font(cw(0.05))
    tb = ld_.textbbox((0, 0), "∞", font=f_inf)
    ld_.text((well_x + well_w / 2 - (tb[2] - tb[0]) / 2 - tb[0],
              well_y + well_h / 2 - (tb[3] - tb[1]) / 2 - tb[1]),
             "∞", font=f_inf, fill=CADMIUM)
    # 剩余 label
    f_lab = load_cjk(cw(0.03))
    tracked_text(ld_, (well_x + well_w / 2, well_y + well_h + cw(0.035)), "剩余",
                 f_lab, (132, 132, 132), tracking=cw(0.006))
    layer = Image.blend(Image.new("RGBA", (N, N), (0, 0, 0, 0)), layer, 0.62)
    img.paste(layer, (0, 0), layer)

    # ---- shutter (top-right) ----
    ring_r = cw(0.0935)
    sh_cx = bx + bw - cw(0.04) - ring_r
    sh_cy = by + int(camW * 1.25 * 0.17) + ring_r
    d.ellipse([sh_cx - ring_r, sh_cy - ring_r, sh_cx + ring_r, sh_cy + ring_r], fill=(255, 255, 255))
    fill_r = cw(0.073)
    d.ellipse([sh_cx - fill_r, sh_cy - fill_r, sh_cx + fill_r, sh_cy + fill_r], fill=CADMIUM)
    f_hint = load_cjk(cw(0.034))
    tracked_text(d, (sh_cx, sh_cy + ring_r + cw(0.058)), "按下快门",
                 f_hint, (110, 110, 110), tracking=cw(0.004))

    # ---- lens ----
    lr = cw(0.62) // 2
    lcx = bx + bw // 2
    fp_bottom_frac = 0.06 + 0.135
    lcy = by + cw(fp_bottom_frac + 0.06) + lr
    disk_grad(img, lcx, lcy, lr, [(0, (96, 96, 99)), (1, (28, 28, 31))])         # metallic
    d.ellipse([lcx - int(lr * 0.96), lcy - int(lr * 0.96),                         # klein ring
               lcx + int(lr * 0.96), lcy + int(lr * 0.96)],
              outline=lerp(KLEIN, (255, 255, 255), 0.08), width=max(3, int(camW * 0.012)))
    d.ellipse([lcx - int(lr * 0.84), lcy - int(lr * 0.84),                         # black bezel
               lcx + int(lr * 0.84), lcy + int(lr * 0.84)], fill=(8, 8, 9))
    # preview scene
    pr = int(lr * 0.74)
    scene = make_lens_glass(2 * pr)
    sm = Image.new("L", (2 * pr, 2 * pr), 0)
    ImageDraw.Draw(sm).ellipse([0, 0, 2 * pr - 1, 2 * pr - 1], fill=255)
    img.paste(scene, (lcx - pr, lcy - pr), sm)
    # glass specular highlight (top-left)
    hl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse([lcx - int(pr * 0.85), lcy - int(pr * 0.95),
                                lcx + int(pr * 0.15), lcy - int(pr * 0.1)],
                               fill=(255, 255, 255, 70))
    hl = hl.filter(ImageFilter.GaussianBlur(12 * s))
    img.paste(Image.new("RGB", (N, N), (255, 255, 255)), (0, 0), hl)
    # subtle edge vignette + thin glass rim
    d.ellipse([lcx - pr, lcy - pr, lcx + pr, lcy + pr],
              outline=(255, 255, 255, 28), width=max(1, int(2 * s)))

    # ---- brand strip (klein capsule + centered white ticks) ----
    st_x0, st_x1 = bx + cw(0.09), bx + bw - cw(0.09)
    st_y0 = lcy + lr + cw(0.06)
    st_h = cw(0.075)
    cap = vgrad(st_x1 - st_x0, st_h, [(0, KLEIN), (1, KLEIN_DEEP)])  # vertical sheen
    cm = Image.new("L", (st_x1 - st_x0, st_h), 0)
    ImageDraw.Draw(cm).rounded_rectangle([0, 0, st_x1 - st_x0 - 1, st_h - 1], radius=st_h // 2, fill=255)
    # horizontal klein->deep gradient overlay
    hcap = Image.new("RGB", (st_x1 - st_x0, st_h))
    pp = hcap.load()
    for x in range(st_x1 - st_x0):
        c = lerp(KLEIN, KLEIN_DEEP, x / max(1, st_x1 - st_x0 - 1))
        for y in range(st_h):
            pp[x, y] = c
    img.paste(hcap, (st_x0, st_y0), cm)
    # ticks: 7, clustered in the center
    n_tick, tw, gap = 7, cw(0.012), cw(0.018)
    cluster = n_tick * tw + (n_tick - 1) * gap
    tx = (st_x0 + st_x1) / 2 - cluster / 2
    tcy = st_y0 + st_h // 2
    for _ in range(n_tick):
        d.rounded_rectangle([tx, tcy - int(st_h * 0.28), tx + tw, tcy + int(st_h * 0.28)],
                            radius=tw // 2, fill=(255, 255, 255, 220))
        tx += tw + gap

    # ---- bottom status ----
    bs_y = st_y0 + st_h + cw(0.05)
    f_st = load_font(cw(0.036))
    asc, desc = f_st.getmetrics()
    x = bx + cw(0.09)
    for ch in "Snap Ready":
        d.text((x, bs_y), ch, font=f_st, fill=(120, 120, 120))
        x += d.textlength(ch, font=f_st) + cw(0.008)
    sdr = cw(0.018)
    d.ellipse([st_x1 - sdr * 2, bs_y + (asc) / 2 - sdr, st_x1, bs_y + (asc) / 2 + sdr], fill=KLEIN)

    return img


def finalize(img, name):
    out = img.resize((1024, 1024), Image.LANCZOS)
    path = os.path.join(OUT, name)
    out.save(path)
    print("wrote", path)


OUT = "/Users/ailln/Workspace/github/ios-ws/SnapStick/SnapStick/Assets.xcassets/AppIcon.appiconset"

# white background, no warm-glow halo
finalize(draw_camera((255, 255, 255), (246, 246, 246), warm_glow=False), "icon-light.png")
# dark variant: neutral dark (no klein blue), still no halo
finalize(draw_camera((30, 30, 32), (12, 12, 14), warm_glow=False), "icon-dark.png")
tint = draw_camera((12, 12, 14), (3, 3, 4), warm_glow=False).convert("L").convert("RGB")
finalize(tint, "icon-tinted.png")
