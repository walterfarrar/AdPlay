"""Offline preview of the auto tapper geometry from HomeView.swift.

Renders the wheel plus a filmstrip of hammer poses so the arm placement and
easing can be checked without a simulator. Not shipped with the app.
"""

import math
import os

from PIL import Image, ImageDraw

SCALE = 2
W, H = 400, 300

WHEEL_SHIFT = -22.0
PIVOT = (150.0, -72.0)
CONTACT = (117.1, -9.7)
STRIKE_POINT = (112.0, 0.0)
SWEEP_DEGREES = 42.0
HEAD_HALF_LENGTH = 11.0
HEAD_HALF_WIDTH = 15.0
PLATE = (128.0, -110.0, 50.0, 56.0)
GEAR_WINDOW = (133.0, -105.0, 40.0, 26.0)
DRIVE = (146.0, -92.0, 11.0)
IDLER = (164.0, -92.0, 7.0)
STOP = (163.0, -53.0, 8.0, 14.0)

ARM_LENGTH = math.hypot(CONTACT[0] - PIVOT[0], CONTACT[1] - PIVOT[1])
STRIKE_ANGLE = math.atan2(CONTACT[1] - PIVOT[1], CONTACT[0] - PIVOT[0])

INK = (244, 245, 250)
ACCENT = (247, 147, 26)
ACCENT_HOT = (255, 107, 44)
FILL = (61, 220, 151)
BG = (14, 15, 26)

BOUNCE = 0.42
WIND_UP = 0.07
IMPACT_FADE = 0.16


def arm_angle(arm):
    return STRIKE_ANGLE - math.radians(SWEEP_DEGREES) * (1 - arm)


def ease_out_quad(t):
    x = min(1.0, max(0.0, t))
    return 1 - (1 - x) ** 2


def ease_in_out_cubic(t):
    x = min(1.0, max(0.0, t))
    return 4 * x**3 if x < 0.5 else 1 - ((-2 * x + 2) ** 3) / 2


def strike_duration(tap_power):
    return max(0.07, 0.16 / max(tap_power, 0.01))


def pose(phase, taps_per_sec, tap_power):
    period = 1.0 / taps_per_sec
    strike = min(0.34, max(0.06, strike_duration(tap_power) / period))
    recoil = min(0.20, max(0.05, 0.07 / period))
    wind_up = max(min(0.09, (1 - strike - recoil) * 0.2), 0.0001)
    reset = max(1 - strike - recoil - wind_up, 0.001)

    fade = min(IMPACT_FADE, period * 0.55)
    impact = max(0.0, 1 - (phase * period) / fade) ** 1.7
    if phase < recoil:
        arm = 1 - BOUNCE * ease_out_quad(phase / recoil)
    elif phase < recoil + reset:
        arm = (1 - BOUNCE) * (1 - ease_in_out_cubic((phase - recoil) / reset))
    elif phase < 1 - strike:
        arm = -WIND_UP * ease_out_quad((phase - recoil - reset) / wind_up)
    else:
        t = min(1.0, (phase - (1 - strike)) / strike)
        arm = -WIND_UP + (1 + WIND_UP) * t**2.3
    return arm, impact


def rgba(color, alpha):
    """Flatten against the flat backdrop — PIL will not blend overlapping alphas."""
    a = max(0.0, min(1.0, alpha))
    return tuple(int(BG[i] + (color[i] - BG[i]) * a) for i in range(3)) + (255,)


def draw_wheel(draw, ox, oy, fraction=0.35):
    def box(r):
        return [(ox - r) * SCALE, (oy - r) * SCALE, (ox + r) * SCALE, (oy + r) * SCALE]

    draw.ellipse(box(110), outline=rgba(INK, 0.08), width=int(13.2 * SCALE))
    draw.arc(box(110), -90, -90 + 360 * fraction, fill=rgba(FILL, 0.9), width=int(13.2 * SCALE))
    draw.ellipse(box(92), fill=rgba(INK, 0.06))
    draw.ellipse(box(30), fill=rgba(INK, 0.10))
    draw.rounded_rectangle(
        [(ox + 110 - 4.5) * SCALE, (oy - 13) * SCALE, (ox + 110 + 4.5) * SCALE, (oy + 13) * SCALE],
        radius=3 * SCALE,
        fill=rgba(INK, 0.30),
        outline=rgba(INK, 0.35),
        width=max(1, SCALE // 2),
    )


def rotate(px, py, angle, ox, oy):
    c, s = math.cos(angle), math.sin(angle)
    return (ox + px * c - py * s, oy + px * s + py * c)


def draw_gear(draw, cx, cy, radius, teeth, rotation, alpha):
    pts = []
    for i in range(teeth * 2):
        r = radius if i % 2 == 0 else radius * 0.72
        a = rotation + i * math.pi / teeth
        pts.append(((cx + math.cos(a) * r) * SCALE, (cy + math.sin(a) * r) * SCALE))
    draw.polygon(pts, fill=rgba(INK, alpha))
    hub = radius * 0.26
    draw.ellipse(
        [(cx - hub) * SCALE, (cy - hub) * SCALE, (cx + hub) * SCALE, (cy + hub) * SCALE],
        fill=rgba(INK, alpha + 0.16),
    )


def draw_tapper(draw, ox, oy, arm, impact, phase):
    kx = -math.cos(STRIKE_ANGLE) * impact * 3
    ky = -math.sin(STRIKE_ANGLE) * impact * 3
    px, py = PIVOT[0] + ox + kx, PIVOT[1] + oy + ky

    def rect(r, inset=0.0):
        return [
            (r[0] + ox + kx + inset) * SCALE,
            (r[1] + oy + ky + inset) * SCALE,
            (r[0] + r[2] + ox + kx - inset) * SCALE,
            (r[1] + r[3] + oy + ky - inset) * SCALE,
        ]

    draw.rounded_rectangle(rect(PLATE), radius=8 * SCALE, fill=rgba(INK, 0.14), outline=rgba(INK, 0.22), width=SCALE)
    draw.rounded_rectangle(rect(PLATE, 5), radius=5 * SCALE, outline=rgba(INK, 0.10), width=SCALE)
    draw.rounded_rectangle(rect(GEAR_WINDOW), radius=13 * SCALE, fill=rgba((0, 0, 0), 0.35))

    turn = phase * 2 * math.pi
    draw_gear(draw, DRIVE[0] + ox + kx, DRIVE[1] + oy + ky, DRIVE[2], 9, turn, 0.34)
    draw_gear(draw, IDLER[0] + ox + kx, IDLER[1] + oy + ky, IDLER[2], 6, -turn * (11 / 7) + math.pi / 6, 0.28)

    for bx in (PLATE[0] + 9, PLATE[0] + PLATE[2] - 9):
        b = ((bx + ox + kx) * SCALE, (PLATE[1] + PLATE[3] - 9 + oy + ky) * SCALE)
        draw.ellipse([b[0] - 3 * SCALE, b[1] - 3 * SCALE, b[0] + 3 * SCALE, b[1] + 3 * SCALE], fill=rgba(INK, 0.26))

    draw.rounded_rectangle(rect(STOP), radius=3 * SCALE, fill=rgba(INK, 0.30))

    angle = arm_angle(arm)
    L = ARM_LENGTH

    def arm_pts(pts, cx=None, cy=None):
        ax, ay = (px, py) if cx is None else (cx, cy)
        return [tuple(v * SCALE for v in rotate(x, y, angle, ax, ay)) for x, y in pts]

    draw.polygon(
        arm_pts([(-11, -9), (L - 8, -5.5), (L - 8, 5.5), (-11, 9)]),
        fill=rgba(INK, 0.42),
    )
    draw.line(arm_pts([(-8, -7), (L - 8, -4)]), fill=rgba(INK, 0.72), width=int(1.5 * SCALE))
    for f in (0.34, 0.56):
        hx0, hy0 = rotate(L * f, 0, angle, px, py)
        draw.ellipse(
            [(hx0 - 3.2) * SCALE, (hy0 - 3.2) * SCALE, (hx0 + 3.2) * SCALE, (hy0 + 3.2) * SCALE],
            fill=rgba(BG, 1.0),
        )

    hl, hw = HEAD_HALF_LENGTH, HEAD_HALF_WIDTH
    sx, sy = 1 - 0.18 * impact, 1 + 0.16 * impact
    hx, hy = rotate(L, 0, angle, px, py)
    draw.polygon(
        arm_pts([(-14 * sx, -9 * sy), (-6 * sx, -9 * sy), (-6 * sx, 9 * sy), (-14 * sx, 9 * sy)], hx, hy),
        fill=rgba(INK, 0.45),
    )
    draw.polygon(
        arm_pts([(-hl * sx, -hw * sy), (hl * sx, -hw * sy), (hl * sx, hw * sy), (-hl * sx, hw * sy)], hx, hy),
        fill=rgba(ACCENT, 1.0),
    )
    draw.polygon(
        arm_pts(
            [
                (hl * sx - 6, -hw * sy + 3),
                (hl * sx, -hw * sy + 3),
                (hl * sx, hw * sy - 3),
                (hl * sx - 6, hw * sy - 3),
            ],
            hx,
            hy,
        ),
        fill=rgba((255, 255, 255), 0.28 + 0.55 * impact),
    )

    draw.ellipse(
        [(px - 9) * SCALE, (py - 9) * SCALE, (px + 9) * SCALE, (py + 9) * SCALE],
        fill=rgba(INK, 0.34),
        outline=rgba(INK, 0.30),
        width=SCALE,
    )
    draw.ellipse(
        [(px - 3.5) * SCALE, (py - 3.5) * SCALE, (px + 3.5) * SCALE, (py + 3.5) * SCALE],
        fill=rgba(INK, 0.55),
    )

    if impact <= 0.01:
        return
    sxp, syp = ox + STRIKE_POINT[0], oy + STRIKE_POINT[1]
    ring = 10 + 24 * (1 - impact)
    draw.ellipse(
        [(sxp - ring) * SCALE, (syp - ring) * SCALE, (sxp + ring) * SCALE, (syp + ring) * SCALE],
        outline=rgba(ACCENT, 0.6 * impact),
        width=2 * SCALE,
    )
    for i in range(4):
        a = math.radians(45 + i * 90)
        near = 10 + 8 * (1 - impact)
        far = near + 8 + 14 * (1 - impact)
        draw.line(
            [
                (sxp + math.cos(a) * near) * SCALE,
                (syp + math.sin(a) * near) * SCALE,
                (sxp + math.cos(a) * far) * SCALE,
                (syp + math.sin(a) * far) * SCALE,
            ],
            fill=rgba(ACCENT, 0.85 * impact),
            width=2 * SCALE,
        )
    flash = 4 + 7 * impact
    draw.ellipse(
        [(sxp - flash) * SCALE, (syp - flash) * SCALE, (sxp + flash) * SCALE, (syp + flash) * SCALE],
        fill=rgba((255, 255, 255), 0.75 * impact),
    )


def frame(phase, taps_per_sec, tap_power):
    img = Image.new("RGBA", (W * SCALE, H * SCALE), BG + (255,))
    draw = ImageDraw.Draw(img, "RGBA")
    ox, oy = W / 2 + WHEEL_SHIFT, H / 2
    draw_wheel(draw, ox, oy)
    arm, impact = pose(phase, taps_per_sec, tap_power)
    draw_tapper(draw, ox, oy, arm, impact, phase)
    return img, arm, impact


def report_bounds():
    """Widest drawn point after the wheel shift, vs. the narrowest phone we support."""
    worst = max(PLATE[0] + PLATE[2], STOP[0] + STOP[2])
    for i in range(200):
        arm = -0.07 + i / 199.0 * 1.07
        a = arm_angle(arm)
        hx = PIVOT[0] + ARM_LENGTH * math.cos(a)
        span = HEAD_HALF_LENGTH * abs(math.cos(a)) + HEAD_HALF_WIDTH * abs(math.sin(a))
        worst = max(worst, hx + span)
    # iPhone SE / small Android: 375pt wide minus the 16pt stage padding each side.
    limit = (375 - 32) / 2
    print(f"widest drawn x = {worst + WHEEL_SHIFT:.1f} (limit {limit:.1f})")


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "build-preview")
    os.makedirs(out, exist_ok=True)
    report_bounds()

    phases = [0.995, 0.0, 0.03, 0.09, 0.25, 0.5, 0.75, 0.9, 0.96]
    strip = Image.new("RGBA", (W * SCALE * 3, H * SCALE * 3), BG + (255,))
    for i, p in enumerate(phases):
        img, arm, impact = frame(p, 1.2, 1.0)
        strip.paste(img, ((i % 3) * W * SCALE, (i // 3) * H * SCALE))
        print(f"phase={p:.3f} arm={arm:+.3f} impact={impact:.2f}")
    strip.convert("RGB").save(os.path.join(out, "tapper_strip.png"))

    frames = [frame(i / 60, 1.2, 1.0)[0].convert("P", palette=Image.ADAPTIVE) for i in range(60)]
    frames[0].save(
        os.path.join(out, "tapper.gif"),
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / 60),
        loop=0,
    )
    print("wrote", out)


if __name__ == "__main__":
    main()
