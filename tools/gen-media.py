"""Textures for the PartyLens interface, drawn procedurally into Media/.

    python -I tools/gen-media.py            write every texture
    python -I tools/gen-media.py --check    exit 1 if a file in Media/ differs from what this script draws

Standard library only. Output is deterministic: uncompressed 32-bit TGA (type 2, 8 alpha bits, bottom-left
origin, the same layout as GuildOS Media/*.tga), power-of-two sizes. Every texture except logo.tga is white with
the shape in the alpha channel, so the Lua side tints it with SetVertexColor and one file serves every state.
Shapes are signed distance fields: coverage = clamp(0.5 - d) gives a one-pixel antialiased edge.
"""
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Media")


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def cov(d):
    """Coverage of a pixel whose centre is d pixels outside a shape (negative: inside)."""
    return clamp(0.5 - d)


# Signed distances; (x, y) in pixels, y down, pixel centres at +0.5.
def circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r


def ring(x, y, cx, cy, r, w):
    return abs(math.hypot(x - cx, y - cy) - r) - w / 2.0


def seg(x, y, ax, ay, bx, by, r):
    px, py, vx, vy = x - ax, y - ay, bx - ax, by - ay
    t = clamp((px * vx + py * vy) / (vx * vx + vy * vy))
    return math.hypot(px - vx * t, py - vy * t) - r


def box(x, y, cx, cy, hw, hh, rad=0.0):
    qx, qy = abs(x - cx) - hw + rad, abs(y - cy) - hh + rad
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - rad


def poly(x, y, pts):
    """Convex polygon, points clockwise on screen (y down)."""
    d = -1e9
    n = len(pts)
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        length = math.hypot(ex, ey)
        # Outward normal of a clockwise (screen) polygon edge.
        nx, ny = ey / length, -ex / length
        d = max(d, (x - ax) * nx + (y - ay) * ny)
    return d


def rot(x, y, cx, cy, deg):
    a = math.radians(deg)
    dx, dy = x - cx, y - cy
    return cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a)


def union(*ds):
    return min(ds)


def cut(a, b):
    return max(a, -b)


def clockwise_from_top(x, y, cx, cy):
    """Angle in [0, 2pi) of (x, y) around (cx, cy), 0 at twelve o'clock, growing clockwise on screen."""
    return math.atan2(x - cx, cy - y) % (2 * math.pi)


# ── images ─────────────────────────────────────────────────────────────────
def white(w, h, alpha_at, ss=1):
    """A white texture whose alpha is alpha_at(x, y), averaged over ss x ss samples per pixel."""
    rows = []
    for j in range(h):
        row = []
        for i in range(w):
            if ss == 1:
                a = alpha_at(i + 0.5, j + 0.5)
            else:
                a = 0.0
                for sj in range(ss):
                    for si in range(ss):
                        a += alpha_at(i + (si + 0.5) / ss, j + (sj + 0.5) / ss)
                a /= ss * ss
            row.append((1.0, 1.0, 1.0, clamp(a)))
        rows.append(row)
    return rows


def layers(w, h, stack):
    """Straight-alpha 'over' of (rgb, alpha_at) layers, bottom first."""
    rows = []
    for j in range(h):
        row = []
        for i in range(w):
            r = g = b = a = 0.0
            for rgb, alpha_at in stack:
                sa = clamp(alpha_at(i + 0.5, j + 0.5))
                if sa <= 0.0:
                    continue
                na = sa + a * (1.0 - sa)
                r = (rgb[0] * sa + r * a * (1.0 - sa)) / na
                g = (rgb[1] * sa + g * a * (1.0 - sa)) / na
                b = (rgb[2] * sa + b * a * (1.0 - sa)) / na
                a = na
            row.append((r, g, b, a))
        rows.append(row)
    return rows


def tga(rows):
    h, w = len(rows), len(rows[0])
    assert w & (w - 1) == 0 and h & (h - 1) == 0, "power-of-two sizes only"
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
    for row in reversed(rows):  # bottom-left origin
        for r, g, b, a in row:
            out += bytes((int(round(b * 255)), int(round(g * 255)), int(round(r * 255)), int(round(a * 255))))
    return bytes(out)


def hexrgb(s):
    return (int(s[0:2], 16) / 255.0, int(s[2:4], 16) / 255.0, int(s[4:6], 16) / 255.0)


# ── the radar ──────────────────────────────────────────────────────────────
def radar_sweep():
    """Conic wedge: brightest on the leading edge at twelve o'clock, fading over 100 degrees counterclockwise."""
    c, R, tail = 128.0, 126.0, math.radians(100)

    def a(x, y):
        r = math.hypot(x - c, y - c)
        inside = cov(r - R)
        if inside <= 0.0:
            return 0.0
        behind = (-clockwise_from_top(x, y, c, c)) % (2 * math.pi)  # 0 on the edge, growing counterclockwise
        wash = (1.0 - behind / tail) ** 2 * 0.5 if behind < tail else 0.0
        # The leading edge: a bright line along the twelve o'clock ray.
        line = 0.0
        if y < c:
            line = clamp(1.25 - abs(x - c)) * 0.9
        return max(wash, line) * inside * clamp(r / 18.0)

    return white(256, 256, a, ss=2)


def radar_grid():
    """Three rings and a faint crosshair, drawn for a radar shown at about 150-190 px."""
    c = 128.0

    def a(x, y):
        r = math.hypot(x - c, y - c)
        rings = max(cov(ring(x, y, c, c, 126.0, 1.7)), 0.75 * cov(ring(x, y, c, c, 84.0, 1.6)),
                    0.75 * cov(ring(x, y, c, c, 42.0, 1.6)))
        cross = 0.0
        if 7.0 < r < 125.0:
            cross = 0.35 * max(cov(abs(x - c) - 0.6), cov(abs(y - c) - 0.6))
        return max(rings, cross)

    return white(256, 256, a)


def blip():
    c = 32.0

    def a(x, y):
        r = math.hypot(x - c, y - c)
        return max(cov(r - 6.0), 0.55 * math.exp(-((r / 11.0) ** 2)))

    return white(64, 64, a)


def dot():
    return white(32, 32, lambda x, y: cov(circle(x, y, 16.0, 16.0, 15.0)))


def thin_ring():
    return white(128, 128, lambda x, y: cov(ring(x, y, 64.0, 64.0, 61.5, 2.5)))


def thick_ring():
    return white(64, 64, lambda x, y: cov(ring(x, y, 32.0, 32.0, 26.0, 9.0)))


def gradient():
    return white(64, 16, lambda x, y: (1.0 - x / 64.0) ** 1.6)


def mark_alpha(x, y):
    """The PartyLens mark: a small radar with its sweep and one blip."""
    c = 32.0
    r = math.hypot(x - c, y - c)
    outer = cov(ring(x, y, c, c, 27.0, 4.0))
    inner = 0.55 * cov(ring(x, y, c, c, 15.0, 2.6))
    behind = (-clockwise_from_top(x, y, c, c)) % (2 * math.pi)
    tail = math.radians(75)
    wedge = 0.0
    if behind < tail and r < 25.0:
        wedge = 0.7 * (1.0 - behind / tail) ** 1.5 * cov(r - 24.5)
    centre = cov(r - 4.0)
    bl = cov(circle(x, y, 43.0, 20.0, 3.6))
    return max(outer, inner, wedge, centre, bl)


def mark():
    return white(64, 64, mark_alpha, ss=2)


def logo():
    """The mark in amber on the slate disc, for places that cannot tint (the addon compartment)."""
    c = 32.0
    return layers(64, 64, [
        (hexrgb("0F1626"), lambda x, y: cov(circle(x, y, c, c, 31.0))),
        (hexrgb("FFB547"), mark_alpha),
    ])


# ── icons (64 px, shown at 16-20 px) ───────────────────────────────────────
def icon_groups(x, y):
    head = circle(x, y, 32, 21, 8.5)
    body = box(x, y, 32, 47, 14, 9, 7)
    centre = union(head, body)
    sides = union(circle(x, y, 14, 25, 6.5), box(x, y, 14, 46, 10, 7.5, 6),
                  circle(x, y, 50, 25, 6.5), box(x, y, 50, 46, 10, 7.5, 6))
    return cov(union(centre, cut(sides, centre - 3.5)))


def icon_announce(x, y):
    horn = poly(x, y, [(14, 25), (42, 12), (42, 52), (14, 39)])
    mouth = box(x, y, 11, 32, 4, 7, 1.5)
    handle = seg(x, y, 22, 40, 25, 53, 3.2)
    arc = max(ring(x, y, 44, 32, 12, 4.2), 50 - x)
    return cov(union(horn, mouth, handle, arc))


def rhombus(x, y, cy):
    return poly(x, y, [(32, cy - 10), (55, cy), (32, cy + 10), (9, cy)])


def icon_layer(x, y):
    top = rhombus(x, y, 20)
    mid = abs(rhombus(x, y, 32)) - 2.4
    low = abs(rhombus(x, y, 44)) - 2.4
    return cov(union(top, cut(mid, top - 3.0), cut(cut(low, rhombus(x, y, 32) - 3.0), top - 3.0)))


def icon_summon(x, y):
    portal = ring(x, y, 32, 32, 21, 5)
    star = union(poly(x, y, [(32, 19), (35.5, 32), (32, 45), (28.5, 32)]),
                 poly(x, y, [(19, 32), (32, 28.5), (45, 32), (32, 35.5)]))
    return cov(union(portal, star))


def icon_network(x, y):
    a, b, c = (32, 16), (15, 46), (49, 46)
    nodes = union(circle(x, y, a[0], a[1], 7.5), circle(x, y, b[0], b[1], 7.5), circle(x, y, c[0], c[1], 7.5))
    edges = union(seg(x, y, a[0], a[1], b[0], b[1], 2.6), seg(x, y, a[0], a[1], c[0], c[1], 2.6),
                  seg(x, y, b[0], b[1], c[0], c[1], 2.6))
    return cov(union(nodes, edges))


def icon_settings(x, y):
    teeth = 1e9
    for k in range(8):
        rx, ry = rot(x, y, 32, 32, k * 45)
        teeth = min(teeth, box(rx, ry, 32, 13, 5, 6, 1.5))
    gear = union(circle(x, y, 32, 32, 17), teeth)
    return cov(cut(gear, circle(x, y, 32, 32, 7.5)))


def icon_more(x, y):
    return cov(union(circle(x, y, 15, 32, 5.5), circle(x, y, 32, 32, 5.5), circle(x, y, 49, 32, 5.5)))


def icon_chevron(x, y):
    return cov(union(seg(x, y, 17, 25, 32, 40, 4.2), seg(x, y, 32, 40, 47, 25, 4.2)))


def icon_check(x, y):
    return cov(union(seg(x, y, 15, 33, 27, 45, 5.2), seg(x, y, 27, 45, 49, 20, 5.2)))


def icon_close(x, y):
    return cov(union(seg(x, y, 18, 18, 46, 46, 4.2), seg(x, y, 46, 18, 18, 46, 4.2)))


def icon_plus(x, y):
    return cov(union(seg(x, y, 32, 17, 32, 47, 4.2), seg(x, y, 17, 32, 47, 32, 4.2)))


def icon_minus(x, y):
    return cov(seg(x, y, 17, 32, 47, 32, 4.2))


def icon_search(x, y):
    return cov(union(ring(x, y, 27, 27, 14, 6), seg(x, y, 38, 38, 50, 50, 4.8)))


def role_tank(x, y):
    return cov(poly(x, y, [(14, 13), (50, 13), (50, 33), (32, 55), (14, 33)]) - 1.5)


def role_heal(x, y):
    return cov(union(box(x, y, 32, 32, 7.5, 21, 2), box(x, y, 32, 32, 21, 7.5, 2)))


def role_dps(x, y):
    rx, ry = rot(x, y, 32, 32, -45)  # a sword lying on the diagonal, unlike the upright cross of the healer
    blade = poly(rx, ry, [(32, 4), (37.5, 12), (37.5, 38), (26.5, 38), (26.5, 12)])
    guard = box(rx, ry, 32, 41, 13, 3.6, 1.5)
    grip = box(rx, ry, 32, 50, 3.2, 6, 1)
    pommel = circle(rx, ry, 32, 58, 3.8)
    return cov(union(blade, guard, grip, pommel))


# A layer as an isometric plate, 256 x 128: the top face is a 2:1 rhombus (T, R, B, L), with a 10 px edge under its
# two front sides. White with the shading in the alpha (top face brighter at the back, the edge dimmer), so one tint
# colours the whole plate. slab-edge is the top face's outline, for the selected, hovered and own plate.
SLAB_T, SLAB_R, SLAB_B, SLAB_L, SLAB_DEPTH = (128, 8), (248, 56), (128, 104), (8, 56), 10


def slab_top(x, y):
    return poly(x, y, [SLAB_T, SLAB_R, SLAB_B, SLAB_L])


def slab_side(x, y):
    d = SLAB_DEPTH
    left = poly(x, y, [SLAB_L, SLAB_B, (SLAB_B[0], SLAB_B[1] + d), (SLAB_L[0], SLAB_L[1] + d)])
    right = poly(x, y, [SLAB_B, SLAB_R, (SLAB_R[0], SLAB_R[1] + d), (SLAB_B[0], SLAB_B[1] + d)])
    return union(left, right)


def slab():
    def a(x, y):
        top = cov(slab_top(x, y))
        if top > 0.0:
            depth = clamp((y - SLAB_T[1]) / float(SLAB_B[1] - SLAB_T[1]))
            return top * (0.95 - 0.25 * depth) + (1.0 - top) * 0.5 * cov(slab_side(x, y))
        side = cov(slab_side(x, y))
        shade = 0.42 if x < SLAB_B[0] else 0.55  # the right front side catches more light
        return side * shade

    return white(256, 128, a, ss=2)


def slab_edge():
    return white(256, 128, lambda x, y: cov(abs(slab_top(x, y)) - 1.4), ss=2)


def icon(fn):
    return lambda: white(64, 64, fn, ss=2)


TEXTURES = [
    ("radar-sweep", radar_sweep),
    ("radar-grid", radar_grid),
    ("blip", blip),
    ("dot", dot),
    ("ring", thin_ring),
    ("ring-thick", thick_ring),
    ("gradient", gradient),
    ("slab", slab),
    ("slab-edge", slab_edge),
    ("mark", mark),
    ("logo", logo),
    ("icon-groups", icon(icon_groups)),
    ("icon-announce", icon(icon_announce)),
    ("icon-layer", icon(icon_layer)),
    ("icon-summon", icon(icon_summon)),
    ("icon-network", icon(icon_network)),
    ("icon-settings", icon(icon_settings)),
    ("icon-more", icon(icon_more)),
    ("chevron", icon(icon_chevron)),
    ("check", icon(icon_check)),
    ("close", icon(icon_close)),
    ("search", icon(icon_search)),
    ("plus", icon(icon_plus)),
    ("minus", icon(icon_minus)),
    ("role-tank", icon(role_tank)),
    ("role-heal", icon(role_heal)),
    ("role-dps", icon(role_dps)),
]


def main(argv):
    check = "--check" in argv
    os.makedirs(MEDIA, exist_ok=True)
    stale = []
    for name, draw in TEXTURES:
        data = tga(draw())
        path = os.path.join(MEDIA, name + ".tga")
        if check:
            try:
                with open(path, "rb") as f:
                    if f.read() != data:
                        stale.append(name)
            except OSError:
                stale.append(name)
            continue
        with open(path, "wb") as f:
            f.write(data)
    if check:
        if stale:
            sys.stderr.write("gen-media: out of date: %s\n" % ", ".join(stale))
            return 1
        print("gen-media: %d textures up to date" % len(TEXTURES))
        return 0
    print("gen-media: wrote %d textures to Media/" % len(TEXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
