#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "build" / "AppIcon.iconset"
OUTPUT = ROOT / "Resources" / "AppIcon.icns"

ICON_SPECS = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def draw_icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = rounded_mask(size, int(218 * scale))

    bg = Image.new("RGBA", (size, size))
    pixels = bg.load()
    for y in range(size):
        for x in range(size):
            t = (x * 0.58 + y * 0.42) / size
            r = int(28 + 22 * t)
            g = int(36 + 40 * t)
            b = int(52 + 72 * t)
            pixels[x, y] = (r, g, b, 255)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (int(-110 * scale), int(-90 * scale), int(760 * scale), int(720 * scale)),
        fill=(106, 122, 238, 72),
    )
    glow_draw.ellipse(
        (int(500 * scale), int(470 * scale), int(1160 * scale), int(1160 * scale)),
        fill=(58, 190, 133, 54),
    )
    bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(int(34 * scale))))

    image.paste(bg, (0, 0), mask)
    draw = ImageDraw.Draw(image)

    inset = int(116 * scale)
    card = (inset, inset, size - inset, size - inset)
    draw.rounded_rectangle(card, radius=int(130 * scale), fill=(20, 25, 35, 218), outline=(255, 255, 255, 28), width=max(1, int(5 * scale)))

    bar_left = int(292 * scale)
    bar_bottom = int(790 * scale)
    bar_width = max(1, int(110 * scale))
    gap = int(55 * scale)
    heights = [int(210 * scale), int(360 * scale), int(500 * scale)]
    colors = [(77, 145, 232, 255), (224, 156, 63, 255), (59, 190, 132, 255)]
    for i, height in enumerate(heights):
        x0 = bar_left + i * (bar_width + gap)
        y0 = bar_bottom - height
        draw.rounded_rectangle(
            (x0, y0, x0 + bar_width, bar_bottom),
            radius=int(34 * scale),
            fill=colors[i],
        )

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle(
        (int(4 * scale), int(4 * scale), size - int(4 * scale), size - int(4 * scale)),
        radius=int(214 * scale),
        outline=(255, 255, 255, 46),
        width=max(1, int(6 * scale)),
    )
    return Image.alpha_composite(image, border)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    largest_icon = None
    for size, filename in ICON_SPECS:
        icon = draw_icon(size)
        icon.save(ICONSET / filename)
        if size == 1024:
            largest_icon = icon
    if largest_icon is None:
        largest_icon = draw_icon(1024)
    largest_icon.save(OUTPUT, format="ICNS")
    print(OUTPUT)


if __name__ == "__main__":
    main()
