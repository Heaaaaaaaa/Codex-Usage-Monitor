#!/usr/bin/env python3
from math import cos, radians, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "build" / "AppIcon.iconset"
APP_ICON = ROOT / "Resources" / "AppIcon.icns"
MENU_BAR_ICON = ROOT / "Resources" / "MenuBarIcon.png"

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


def rounded_mask(size: int, bounds: tuple[int, int, int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(bounds, radius=radius, fill=255)
    return mask


def interpolate(start: int, end: int, amount: float) -> int:
    return round(start + (end - start) * amount)


def diagonal_gradient(size: int) -> Image.Image:
    start = (49, 133, 255)
    end = (15, 62, 174)
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            amount = min(max((x * 0.34 + y * 0.66) / size, 0), 1)
            pixels[x, y] = (
                interpolate(start[0], end[0], amount),
                interpolate(start[1], end[1], amount),
                interpolate(start[2], end[2], amount),
                255,
            )
    return image


def draw_round_arc(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    start: float,
    end: float,
    width: int,
    fill: tuple[int, int, int, int],
) -> None:
    draw = ImageDraw.Draw(image)
    draw.arc(bounds, start=start, end=end, fill=fill, width=width)
    center_x = (bounds[0] + bounds[2]) / 2
    center_y = (bounds[1] + bounds[3]) / 2
    radius = (bounds[2] - bounds[0]) / 2
    cap_radius = width / 2
    for angle in (start, end):
        x = center_x + radius * cos(radians(angle))
        y = center_y + radius * sin(radians(angle))
        draw.ellipse(
            (x - cap_radius, y - cap_radius, x + cap_radius, y + cap_radius),
            fill=fill,
        )


def draw_usage_mark(
    image: Image.Image,
    bounds: tuple[int, int, int, int],
    width: int,
    ring: tuple[int, int, int, int],
    token: tuple[int, int, int, int],
) -> None:
    draw_round_arc(image, bounds, start=42, end=318, width=width, fill=ring)
    center_y = (bounds[1] + bounds[3]) / 2
    token_x = bounds[2] + width * 0.20
    token_radius = width * 0.52
    ImageDraw.Draw(image).ellipse(
        (
            token_x - token_radius,
            center_y - token_radius,
            token_x + token_radius,
            center_y + token_radius,
        ),
        fill=token,
    )


def draw_app_icon() -> Image.Image:
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    squircle = (64, 52, 960, 948)
    mask = rounded_mask(size, squircle, 214)

    shadow_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle((72, 76, 952, 956), radius=210, fill=90)
    shadow = Image.new("RGBA", (size, size), (1, 8, 25, 0))
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(28)))
    canvas = Image.alpha_composite(canvas, shadow)

    background = diagonal_gradient(size)
    canvas.paste(background, (0, 0), mask)

    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.rounded_rectangle(
        (78, 66, 946, 934),
        radius=202,
        outline=(255, 255, 255, 32),
        width=6,
    )
    canvas = Image.alpha_composite(canvas, highlight)

    mark_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_usage_mark(
        mark_shadow,
        (242, 230, 770, 758),
        108,
        (1, 24, 83, 108),
        (1, 24, 83, 108),
    )
    mark_shadow = mark_shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas, mark_shadow)

    mark = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_usage_mark(
        mark,
        (242, 212, 770, 740),
        108,
        (248, 251, 255, 255),
        (105, 232, 184, 255),
    )
    return Image.alpha_composite(canvas, mark)


def draw_menu_bar_icon() -> Image.Image:
    source_size = 144
    image = Image.new("RGBA", (source_size, source_size), (0, 0, 0, 0))
    draw_usage_mark(
        image,
        (29, 25, 107, 103),
        18,
        (0, 0, 0, 255),
        (0, 0, 0, 255),
    )
    return image.resize((36, 36), Image.Resampling.LANCZOS)


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    APP_ICON.parent.mkdir(parents=True, exist_ok=True)

    master = draw_app_icon()
    for size, filename in ICON_SPECS:
        master.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / filename)
    master.save(APP_ICON, format="ICNS")
    draw_menu_bar_icon().save(MENU_BAR_ICON)
    print(APP_ICON)
    print(MENU_BAR_ICON)


if __name__ == "__main__":
    main()
