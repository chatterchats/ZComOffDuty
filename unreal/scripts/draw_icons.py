"""Draw Off Duty's fatigue tier icons: white "Zzz" glyphs on transparency, like the game's status icons
(the HUD tints them). One Z for Tired, two for Exhausted, three for Spent, rising and growing.

    python3 unreal/scripts/draw_icons.py   ->  src/OffDuty{,Probe}/icons/T_OffDuty_Fatigue_{1,2,3}.png (128x128)

They ship as PNG files in the Lua mod and are loaded at runtime with
KismetRenderingLibrary.ImportFileAsTexture2D: a texture cooked on Linux didn't load in the Windows game.
"""
import os

from PIL import Image, ImageDraw

SIZE, SCALE = 128, 8  # draw at 8x, then downsample for clean edges
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUTS = [os.path.join(REPO, "src", mod, "icons") for mod in ("OffDuty", "OffDutyProbe")]

# (centre x, centre y, height) per Z, in 128-px units; each tier adds a bigger, higher Z.
LAYOUTS = {
    1: [(64, 64, 70)],
    2: [(32, 90, 38), (80, 48, 60)],
    3: [(21, 102, 27), (53, 75, 38), (96, 38, 52)],
}


def draw_z(draw, cx, cy, height):
    """A bold Z: top bar, diagonal, bottom bar, with a stroke ~22% of its height."""
    s = SCALE
    w, h, t = height * 0.9, height, max(5.0, height * 0.22)
    left, right, top, bottom = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
    draw.rectangle([left * s, top * s, right * s, (top + t) * s], fill=255)
    draw.rectangle([left * s, (bottom - t) * s, right * s, bottom * s], fill=255)
    draw.polygon([((right - t * 1.15) * s, (top + t) * s), (right * s, (top + t) * s),
                  ((left + t * 1.15) * s, (bottom - t) * s), (left * s, (bottom - t) * s)], fill=255)


def main():
    for out in OUTS:
        os.makedirs(out, exist_ok=True)
    for tier, zs in LAYOUTS.items():
        alpha = Image.new("L", (SIZE * SCALE, SIZE * SCALE), 0)
        draw = ImageDraw.Draw(alpha)
        for cx, cy, height in zs:
            draw_z(draw, cx, cy, height)
        alpha = alpha.resize((SIZE, SIZE), Image.LANCZOS)
        icon = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
        icon.putalpha(alpha)
        for out in OUTS:
            path = os.path.normpath(os.path.join(out, "T_OffDuty_Fatigue_%d.png" % tier))
            icon.save(path)
            print(path)


if __name__ == "__main__":
    main()
