"""
Generates the Cloud Kitchen app icon (assets/icon/icon.png + icon_foreground.png)
by rasterizing the exact same flame+dot mark used by the in-app vector logo
(lib/widgets/app_logo.dart), so the launcher icon and the in-app mark are the
same shape, not two different logos. Run with: python tool/generate_app_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageOps

SIZE = 1024
S = SIZE / 100.0  # scale factor: shape is authored in a 100x100 unit box

BASE = (232, 93, 44)      # ember orange (scheme.primary, light theme)
TIP = (255, 151, 82)      # lighter tip
INNER = (255, 246, 236)   # warm cream counter-flame
DOT = (27, 42, 47)        # charcoal slate (secondary)
BG_TOP = (44, 74, 85)     # lighter charcoal
BG_BOTTOM = (13, 21, 23)  # near-black charcoal


def cubic_bezier_points(p0, p1, p2, p3, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = (mt**3) * p0[0] + 3 * (mt**2) * t * p1[0] + 3 * mt * (t**2) * p2[0] + (t**3) * p3[0]
        y = (mt**3) * p0[1] + 3 * (mt**2) * t * p1[1] + 3 * mt * (t**2) * p2[1] + (t**3) * p3[1]
        pts.append((x, y))
    return pts


def path_from_cubics(start, cubics):
    """cubics: list of (c1, c2, end) tuples, mirroring Flutter's Path.cubicTo chain."""
    pts = [start]
    cur = start
    for c1, c2, end in cubics:
        pts.extend(cubic_bezier_points(cur, c1, c2, end)[1:])
        cur = end
    return pts


def scaled(pts):
    return [(x * S, y * S) for x, y in pts]


def make_gradient(size, top_color, bottom_color):
    grad = Image.new("RGB", (1, size), 0)
    for y in range(size):
        t = y / (size - 1)
        r = round(top_color[0] * (1 - t) + bottom_color[0] * t)
        g = round(top_color[1] * (1 - t) + bottom_color[1] * t)
        b = round(top_color[2] * (1 - t) + bottom_color[2] * t)
        grad.putpixel((0, y), (r, g, b))
    return grad.resize((size, size))


def flame_path():
    # Mirrors the exact cubicTo control points in lib/widgets/app_logo.dart _LogoPainter.
    start = (50, 93)
    cubics = [
        ((24, 88), (10, 70), (13, 54)),
        ((15, 43), (24, 36), (27, 24)),
        ((29, 34), (36, 40), (40, 36)),
        ((35, 22), (40, 8), (55, 2)),
        ((50, 16), (58, 20), (63, 28)),
        ((66, 20), (65, 12), (62, 4)),
        ((78, 12), (90, 28), (88, 46)),
        ((87, 40), (82, 36), (78, 34)),
        ((82, 46), (88, 58), (84, 70)),
        ((80, 82), (66, 90), (50, 93)),
    ]
    return path_from_cubics(start, cubics)


def inner_flame_path():
    start = (50, 82)
    cubics = [
        ((36, 76), (30, 63), (34, 52)),
        ((38, 44), (46, 40), (48, 32)),
        ((56, 38), (62, 48), (60, 58)),
        ((64, 54), (66, 48), (65, 42)),
        ((72, 50), (74, 62), (68, 72)),
        ((63, 80), (56, 82), (50, 82)),
    ]
    return path_from_cubics(start, cubics)


def build_mark(canvas_size, transparent_bg):
    """Draws just the flame mark (no background), for the adaptive-icon foreground."""
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0) if transparent_bg else (0, 0, 0, 0))
    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mdraw = ImageDraw.Draw(mask)

    scale = canvas_size / 100.0
    flame_pts = [(x * scale, y * scale) for x, y in flame_path()]
    mdraw.polygon(flame_pts, fill=255)

    grad = make_gradient(canvas_size, TIP, BASE)  # tip (top) -> base (bottom)
    flame_layer = Image.composite(grad.convert("RGBA"), Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0)), mask)
    img = Image.alpha_composite(img, flame_layer)

    inner_mask = Image.new("L", (canvas_size, canvas_size), 0)
    idraw = ImageDraw.Draw(inner_mask)
    inner_pts = [(x * scale, y * scale) for x, y in inner_flame_path()]
    idraw.polygon(inner_pts, fill=255)
    inner_layer = Image.new("RGBA", (canvas_size, canvas_size), INNER + (255,))
    inner_layer.putalpha(inner_mask)
    img = Image.alpha_composite(img, inner_layer)

    # Delivery/motion dot
    ddraw = ImageDraw.Draw(img)
    cx, cy, r = 83 * scale, 22 * scale, 6.5 * scale
    ddraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=DOT + (255,))

    return img


def build_full_icon():
    bg = make_gradient(SIZE, BG_TOP, BG_BOTTOM).convert("RGBA")
    # Rounded-square mask (standard app-icon convention; platforms re-mask anyway).
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.22), fill=255)
    bg.putalpha(mask)

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas = Image.alpha_composite(canvas, bg)

    mark = build_mark(int(SIZE * 0.62), transparent_bg=True)
    offset = ((SIZE - mark.width) // 2, (SIZE - mark.height) // 2 + int(SIZE * 0.02))
    canvas.alpha_composite(mark, offset)
    return canvas


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
    os.makedirs(out_dir, exist_ok=True)

    full = build_full_icon()
    full.convert("RGB").save(os.path.join(out_dir, "icon.png"), "PNG")

    # Adaptive-icon foreground: mark only, transparent background, centered
    # with extra padding since Android crops adaptive icons to a smaller safe zone.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mark_fg = build_mark(int(SIZE * 0.46), transparent_bg=True)
    off = ((SIZE - mark_fg.width) // 2, (SIZE - mark_fg.height) // 2)
    fg.alpha_composite(mark_fg, off)
    fg.save(os.path.join(out_dir, "icon_foreground.png"), "PNG")

    print("Wrote", os.path.join(out_dir, "icon.png"), "and icon_foreground.png")


if __name__ == "__main__":
    main()
