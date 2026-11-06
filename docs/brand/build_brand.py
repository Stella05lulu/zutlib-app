#!/usr/bin/env python3
"""Builds every ZutLib brand file from one master geometry.

    python docs/brand/build_brand.py

Writes the SVG masters in docs/brand/, the Android adaptive and themed
(monochrome) icon vectors, and prints the path the app draws
(ZutLibMark in lib/ui/widgets/brand.dart). PNG icons are then rendered from
the SVGs (render_icons.js next to this file).

The mark, on a 256 grid with every point on an 8 px grid:
  - bookmark  x 64..192, y 24..232, top corners radius 6, a sharp notch
              24 deep at the foot (the same as the Z's stroke)
  - Z (cut)   x 88..168, y 56..160, all three strokes 24 thick, outer
              corners radius 6, sitting 8 px above the body's centre so it
              looks centred despite the notch
"""
import math
import os

BLUE, PAPER, INK = '#1D5FC4', '#F6F9FD', '#1C2027'
R = 6  # corner radius on 256

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def f(v):
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return '0' if s == '-0' else s


# ------------------------------------------------------------------ the mark
def bookmark():
    return (f'M{64 + R} 24 H{192 - R} A{R} {R} 0 0 1 192 {24 + R} V232 L128 208 L64 232 '
            f'V{24 + R} A{R} {R} 0 0 1 {64 + R} 24 Z')


def zed():
    # Clockwise from the top-left. Outer corners (top-left, top-right,
    # bottom-right, bottom-left) are rounded; the inner ones stay sharp.
    return (f'M{88 + R} 56 H{168 - R} A{R} {R} 0 0 1 168 {56 + R} V80 L120 136 H168 V{160 - R} '
            f'A{R} {R} 0 0 1 {168 - R} 160 H{88 + R} A{R} {R} 0 0 1 88 {160 - R} V136 L136 80 H88 '
            f'V{56 + R} A{R} {R} 0 0 1 {88 + R} 56 Z')


MARK = bookmark() + ' ' + zed()

# The old mark, for the before-and-after sheet.
OLD_MARK = 'M64 24 H192 V232 L128 195 L64 232 Z M90 62 H166 V88 L128 126 H166 V152 H90 V126 L128 88 H90 Z'


def mark_path(fill, transform=None, d=MARK):
    t = f' transform="{transform}"' if transform else ''
    return f'<path fill="{fill}" fill-rule="evenodd"{t} d="{d}"/>'


# ------------------------------------------------------------- the wordmark
# Drawn lowercase "zutlib" with one stroke weight, round ends, outlined
# into filled shapes. x-height runs from y 99 to 173. The stroke (17 on
# this grid) comes out the same weight as the Z's strokes in the lockup.
W = 17  # stroke weight
H = W / 2
XT, XB = 99, 173  # x-height top and baseline
ASC = 51  # ascender top (l, b, t)


def capsule(x1, y1, x2, y2, r=H):
    """A straight stroke with round ends, as a filled outline."""
    a = math.atan2(y2 - y1, x2 - x1)
    nx, ny = -math.sin(a) * r, math.cos(a) * r
    return (f'M{f(x1 + nx)} {f(y1 + ny)} L{f(x2 + nx)} {f(y2 + ny)} '
            f'A{f(r)} {f(r)} 0 0 0 {f(x2 - nx)} {f(y2 - ny)} L{f(x1 - nx)} {f(y1 - ny)} '
            f'A{f(r)} {f(r)} 0 0 0 {f(x1 + nx)} {f(y1 + ny)} Z')


def ring(cx, cy, r, w=W):
    o, i = r + w / 2, r - w / 2
    # Outer clockwise, inner anticlockwise, so the centre stays empty
    # under the non-zero rule as well.
    return (f'M{f(cx - o)} {f(cy)} A{f(o)} {f(o)} 0 1 1 {f(cx + o)} {f(cy)} A{f(o)} {f(o)} 0 1 1 {f(cx - o)} {f(cy)} Z '
            f'M{f(cx - i)} {f(cy)} A{f(i)} {f(i)} 0 1 0 {f(cx + i)} {f(cy)} A{f(i)} {f(i)} 0 1 0 {f(cx - i)} {f(cy)} Z')


def u_bowl(x1, x2, top, w=W):
    """The bottom of the u: a half ring from x1 to x2, centred at y top."""
    r = (x2 - x1) / 2
    cx = x1 + r
    o, i = r + w / 2, r - w / 2
    return (f'M{f(cx - o)} {f(top)} A{f(o)} {f(o)} 0 0 0 {f(cx + o)} {f(top)} '
            f'L{f(cx + i)} {f(top)} A{f(i)} {f(i)} 0 0 1 {f(cx - i)} {f(top)} Z')


def dot(cx, cy, r):
    return f'M{f(cx - r)} {f(cy)} A{f(r)} {f(r)} 0 1 0 {f(cx + r)} {f(cy)} A{f(r)} {f(r)} 0 1 0 {f(cx - r)} {f(cy)} Z'


def wordmark():
    # Letters spaced 32 apart (stroke edge to stroke edge), tighter than the
    # first drawing's 40 to 46.
    gap = 32
    parts = []
    x = 11  # left edge of the z's stroke centre line
    # z
    zw = 54
    parts += [capsule(x, XT, x + zw, XT), capsule(x + zw, XT, x, XB), capsule(x, XB, x + zw, XB)]
    x += zw + W + gap
    # u
    uw = 64
    parts += [capsule(x, XT, x, XB - 32), u_bowl(x, x + uw, XB - 32), capsule(x + uw, XT, x + uw, XB)]
    x += uw + W + gap
    # t (crossbar 38 wide, stem off centre like the drawing)
    parts += [capsule(x + 18, 54, x + 18, XB), capsule(x, XT, x + 38, XT)]
    x += 38 + W + gap
    # l
    parts += [capsule(x, ASC, x, XB)]
    x += W + gap
    # i
    parts += [capsule(x, XT, x, XB), dot(x, 58, 12)]
    x += W + gap
    # b
    parts += [capsule(x, ASC, x, XB), ring(x + 37, 136, 37)]
    right = x + 37 + 37 + H
    return parts, right + 1


WORD, WORD_RIGHT = wordmark()


# ------------------------------------------------------------- composition
def lockup(mark_fill, word_fill):
    # The Z's top and bottom (y 56 and 160 on the mark) line up with the
    # x-height (99 and 173 on the wordmark): the wordmark is scaled so its
    # x-height equals the Z's height.
    ws = 104 / (XB - XT)  # wordmark scale relative to the mark's grid
    ms = 0.72
    word_scale = ms * ws
    mark_dy = 0
    word_x = (192 - 64) * ms + 40
    word_dy = (56 - 24) * ms + mark_dy - XT * word_scale
    width = word_x + WORD_RIGHT * word_scale
    top = min(0, word_dy + (ASC - H) * word_scale)  # ascenders rise above the mark
    height = 208 * ms - top
    pad = 8
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{f(-pad)} {f(top - pad)} {f(width + 2 * pad)} {f(height + 2 * pad)}" '
            f'width="{f(width + 2 * pad)}" height="{f(height + 2 * pad)}" role="img"><title>ZutLib</title>'
            + mark_path(mark_fill, f'scale({ms}) translate(-64 -24)')
            + f'<g fill="{word_fill}" transform="translate({f(word_x)} {f(word_dy)}) scale({f(word_scale)})">'
            + ''.join(f'<path d="{d}"/>' for d in WORD) + '</g></svg>\n')


def symbol(fill):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img">'
            f'<title>ZutLib</title>{mark_path(fill)}</svg>\n')


def tile(rx, mark_height):
    """The mark in Paper on a blue square of 512, mark_height tall."""
    s = mark_height / 208
    tx = 256 - 128 * s / 2 - 64 * s  # centre the 128 wide bookmark
    ty = 256 - 208 * s / 2 - 24 * s
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            f'<title>ZutLib app icon</title><rect width="512" height="512" rx="{rx}" fill="{BLUE}"/>'
            + mark_path(PAPER, f'translate({f(tx)} {f(ty)}) scale({f(s)})') + '</svg>\n')


def favicon():
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="24 24 208 208" width="208" height="208">'
            f'<title>ZutLib</title>{mark_path(BLUE)}</svg>\n')


# --------------------------------------------------------- Android vectors
def android_vector(fill, name):
    """A 108 dp adaptive icon layer with the mark in the 66 dp safe zone."""
    # Mark 42 dp tall, centred: about 60% of the 72 dp the launcher shows,
    # with blue all round it (56 dp crowded the edges of the circle).
    s = 42 / 208
    tx = 54 - 128 * s
    ty = 54 - 128 * s
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- ZutLib {name}: generated by docs/brand/build_brand.py. Do not edit by hand. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:translateX="{f(tx)}"
        android:translateY="{f(ty)}"
        android:scaleX="{f(s)}"
        android:scaleY="{f(s)}">
        <path
            android:fillColor="{fill}"
            android:fillType="evenOdd"
            android:pathData="{MARK}" />
    </group>
</vector>
'''


def write(rel, text):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write(text)
    print('wrote', rel)


def comparison():
    """Old and refined marks side by side, large and small, on Paper."""
    cells = []
    for i, (label, d) in enumerate([('Before', OLD_MARK), ('Refined', MARK)]):
        x = 40 + i * 420
        cells.append(f'<text x="{x}" y="44" font-family="IBM Plex Sans, sans-serif" font-size="22" fill="{INK}">{label}</text>')
        cells.append(mark_path(BLUE, f'translate({x - 40} 60) scale(1.25)', d))
        for j, size in enumerate([64, 32, 16]):
            s = size / 208
            cells.append(mark_path(BLUE, f'translate({x + 10 + j * 90} {420 - 24 * s}) scale({f(s)}) translate(-64 -24)', d))
        # on blue
        cells.append(f'<rect x="{x}" y="520" width="140" height="140" rx="31" fill="{BLUE}"/>')
        s = 92 / 208
        cells.append(mark_path(PAPER, f'translate({f(x + 70 - 64 * s - 64 * s)} {f(590 - 104 * s - 24 * s)}) scale({f(s)})', d))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 840 700" width="840" height="700">'
            f'<rect width="840" height="700" fill="{PAPER}"/>' + ''.join(cells) + '</svg>\n')


if __name__ == '__main__':
    write('docs/brand/zutlib-symbol.svg', symbol(BLUE))
    write('docs/brand/zutlib-symbol-black.svg', symbol(INK))
    write('docs/brand/zutlib-symbol-reversed.svg', symbol(PAPER))
    write('docs/brand/zutlib-lockup.svg', lockup(BLUE, INK))
    write('docs/brand/zutlib-lockup-black.svg', lockup(INK, INK))
    write('docs/brand/zutlib-lockup-reversed.svg', lockup(PAPER, PAPER))
    write('docs/brand/zutlib-app-icon.svg', tile(113, 264))
    write('docs/brand/zutlib-maskable.svg', tile(0, 208))
    write('docs/brand/favicon.svg', favicon())
    write('docs/brand/refinement-before-after.svg', comparison())
    write('android/app/src/main/res/drawable/ic_launcher_foreground.xml', android_vector(PAPER, 'launcher foreground'))
    write('android/app/src/main/res/drawable/ic_launcher_monochrome.xml', android_vector('#FFFFFFFF', 'themed icon (Android 13)'))
    print('\nMARK =', MARK)
