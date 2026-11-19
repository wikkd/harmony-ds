# -*- coding: utf-8 -*-
"""
gen_icon.py — 生成 harmony DS 应用图标（分层图标 + 启动窗图标）。

设计：HD 大写艺术字连字（H 右竖与 D 左竖共杆）+ AI 星芒点缀（右上）
     + 气泡尾巴点缀（左下，点出"聊天"身份），
     白字落在 DeepSeek 蓝对角渐变背景上，符合鸿蒙分层图标规范。
产物：
  AppScope/resources/base/media/background.png  1024x1024 渐变底
  AppScope/resources/base/media/foreground.png  1024x1024 白鲸（透明留白，安全圈内）
  AppScope/resources/base/media/startIcon.png   512x512   压平+圆角（启动窗）
  scripts/_icon_preview.png                     预览拼图（小尺寸可读性检查，不入库）

用法：python scripts/gen_icon.py
"""
import argparse
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media')

BASE = 1024          # 分层图标画布
SS = 4               # 超采样倍数（抗锯齿）
W = BASE * SS

# ── 配色（DeepSeek 蓝系，与鸿蒙蓝同族）────────────────────────────
C_TOP = (91, 125, 255)     # 左上亮部 #5B7DFF
C_BOT = (43, 63, 214)      # 右下深部 #2B3FD6
GLOW_POS = (0.28, 0.24)    # 高光圆心（画布比例）
GLOW_ALPHA = 26            # 高光峰值 alpha

# ── HD 连字排版（1024 坐标系，整体水平居中于 512）────────────────
STROKE = 76            # 笔画宽
H_TOP, H_BOT = 324, 708
R_TERM = 26            # 竖笔端头圆角
X_L0, X_L1 = 265, 341  # H 左竖
X_M0, X_M1 = 517, 593  # H 右竖 = D 左竖（共杆）
BAR_Y0, BAR_Y1 = 468, 544  # H 横杠（光学中心略高于几何中心）
D_R = 180              # D 外弧半径（右缘为半圆）
ARC_C = (759 - D_R, (H_TOP + H_BOT) // 2)  # 外弧圆心 (579, 516)
# 扁平化放大：字面绕 (512,516) 整体缩放（笔画同步加粗）；点缀用绝对坐标另收位
SC = 1.12
CEN = (512.0, 516.0)
FLAT_BG = (77, 107, 254)       # 扁平纯色底 DeepSeek 蓝 #4D6BFE
SPARK = ((788, 344), 24, 8.5)  # 星芒点缀：中心, 外半径, 内半径（放大后收进安全圆）
TAIL = [(236, 710), (322, 710), (286, 782)]  # 气泡尾（绝对坐标，贴放大后左竖底部）


def make_background():
    """对角渐变 + 左上柔光。"""
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    t = ((xs + ys) / (2 * (W - 1))).astype(np.float32)
    top = np.array(C_TOP, dtype=np.float32)
    bot = np.array(C_BOT, dtype=np.float32)
    rgb = top[None, None, :] * (1 - t[..., None]) + bot[None, None, :] * t[..., None]

    # 柔光：以 GLOW_POS 为圆心的径向衰减
    gx, gy = GLOW_POS[0] * W, GLOW_POS[1] * W
    d = np.sqrt((xs - gx) ** 2 + (ys - gy) ** 2) / (0.85 * W)
    glow = np.clip(1 - d, 0, 1) ** 2 * (GLOW_ALPHA / 255.0)
    alpha = np.full((W, W), 255, dtype=np.float32)

    img = np.dstack([rgb, alpha[..., None] * 1.0]).astype(np.uint8)
    arr = img.copy()
    arr[..., :3] = np.clip(arr[..., :3] + (255 - arr[..., :3]) * glow[..., None], 0, 255).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA').resize((BASE, BASE), Image.LANCZOS)


def make_foreground(shadow=False):
    """HD 连字白稿（RGBA 透明底）：D 字碗挖竖椭圆字腔，缀星芒与气泡尾。
    字面绕 CEN 按 SC 缩放（放大且笔画同步加粗）；shadow=True 时垫柔投影。"""
    layer = Image.new('L', (W, W), 0)
    dr = ImageDraw.Draw(layer)
    k = SS

    def sx(v):
        return (CEN[0] + (v - CEN[0]) * SC) * k

    def sy(v):
        return (CEN[1] + (v - CEN[1]) * SC) * k

    def rrect(x0, y0, x1, y1, r=0, corners=None):
        dr.rounded_rectangle([sx(x0), sy(y0), sx(x1), sy(y1)],
                             radius=r * SC * k, corners=corners, fill=255)

    # H：左竖 + 横杠 + 共杆（顶端圆角、底端平角齐基线，横杠两端埋进竖笔）
    stem_c = (True, False, False, False)
    rrect(X_L0, H_TOP, X_L1, H_BOT, R_TERM, corners=stem_c)
    rrect(X_M0, H_TOP, X_M1, H_BOT, R_TERM, corners=stem_c)
    rrect(X_L0, BAR_Y0, X_M0, BAR_Y1)
    # D：杆右接半圆字碗（半径 180 超出圆角矩形上限，用矩形 + 半圆盘求并）
    dr.rounded_rectangle([sx(X_M0), sy(H_TOP), sx(579), sy(H_BOT)], fill=255)
    dr.pieslice([sx(579 - D_R), sy(516 - D_R), sx(579 + D_R), sy(516 + D_R)],
                start=270, end=90, fill=255)
    # 点缀：星芒（右上，绝对坐标）
    (scx, scy), rout, rin = SPARK
    pts = []
    for i in range(8):
        ang = math.radians(90 + i * 45)
        rr = rout if i % 2 == 0 else rin
        pts.append(((scx + rr * math.cos(ang)) * k, (scy + rr * math.sin(ang)) * k))
    dr.polygon(pts, fill=255)
    # 点缀：气泡尾（左下，顶边压进左竖底部连成一体）
    dr.polygon([(x * k, y * k) for x, y in TAIL], fill=255)

    # 字腔：D 碗内竖椭圆（右缘留一笔宽，保证横向笔画均匀）
    holes = Image.new('L', (W, W), 0)
    hd = ImageDraw.Draw(holes)
    inset = H_BOT - H_TOP - 2 * STROKE      # 腔高 208
    ccx = (X_M1 + 759 - STROKE) / 2         # 腔心 x = 638
    rx = (759 - STROKE - X_M1) / 2          # 腔半宽 45
    hd.ellipse([sx(ccx - rx), sy(516 - inset / 2), sx(ccx + rx), sy(516 + inset / 2)],
               fill=255)

    alpha = ImageChops.subtract(layer, holes)
    rgba = Image.new('RGBA', (W, W), (255, 255, 255, 0))
    rgba.putalpha(alpha)
    white = rgba

    if not shadow:
        return white.resize((BASE, BASE), Image.LANCZOS)

    # 柔投影垫在白稿下（烘进前景层：系统合成 background→foreground 时自然出现）
    blur_a = alpha.filter(ImageFilter.GaussianBlur(56))          # 4x 画布，56 = 基准 14
    shadow_img = Image.new('RGBA', (W, W), (8, 14, 48, 0))
    shadow_img.putalpha(blur_a.point(lambda v: int(v * 0.32)))
    out = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    out.alpha_composite(shadow_img, (0, 40))                     # 4x 画布，40 = 基准 10
    out.alpha_composite(white)
    return out.resize((BASE, BASE), Image.LANCZOS)


def make_start_icon(bg, fg):
    """压平成 512 圆角方形（启动窗用）。"""
    size = 512
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    icon.alpha_composite(bg.resize((size, size), Image.LANCZOS))
    icon.alpha_composite(fg.resize((size, size), Image.LANCZOS))
    r = 110
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    return out


def make_preview(bg, fg, path):
    """小尺寸可读性拼图。"""
    full = Image.new('RGBA', (BASE, BASE), (0, 0, 0, 0))
    full.alpha_composite(bg)
    full.alpha_composite(fg)
    sizes = [1024, 216, 128, 96, 64, 48, 32]
    row_h = 1024 + 8
    total_w = sum(s for s in sizes) + 12 * (len(sizes) + 1)
    sheet = Image.new('RGB', (total_w, row_h), (245, 245, 245))
    x = 12
    for s in sizes:
        im = full.resize((s, s), Image.LANCZOS)
        m = Image.new('L', (s, s), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], radius=max(s // 5, 4), fill=255)
        sheet.paste(im, (x, 4), m)
        x += s + 12
    sheet.save(path)


def make_flat_background():
    """扁平纯色底。"""
    img = Image.new('RGBA', (BASE, BASE), FLAT_BG + (255,))
    return img


def main():
    ap = argparse.ArgumentParser(description='生成 harmony DS 图标资产')
    ap.add_argument('--bg', help='AI 生成底图路径（缺省用程序渐变）')
    ap.add_argument('--shade', type=float, default=1.0, help='底图亮度系数（<1 压暗提对比）')
    ap.add_argument('--sat', type=float, default=1.0, help='底图饱和度系数')
    ap.add_argument('--flat', action='store_true', help='扁平化：纯色底 + 无投影')
    args = ap.parse_args()

    if args.flat:
        bg = make_flat_background()
        fg = make_foreground(shadow=False)
    else:
        if args.bg:
            bg = Image.open(args.bg).convert('RGBA')
            if bg.width != BASE or bg.height != BASE:
                bg = bg.resize((BASE, BASE), Image.LANCZOS)
            if args.shade != 1.0:
                bg = ImageEnhance.Brightness(bg).enhance(args.shade)
            if args.sat != 1.0:
                bg = ImageEnhance.Color(bg).enhance(args.sat)
        else:
            bg = make_background()
        fg = make_foreground(shadow=True)
    bg.save(os.path.join(MEDIA, 'background.png'))
    fg.save(os.path.join(MEDIA, 'foreground.png'))
    make_start_icon(bg, fg).save(os.path.join(MEDIA, 'startIcon.png'))
    make_preview(bg, fg, os.path.join(ROOT, 'scripts', '_icon_preview.png'))
    print('icon assets generated ->', MEDIA)


if __name__ == '__main__':
    main()
