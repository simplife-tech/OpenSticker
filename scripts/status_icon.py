from pathlib import Path

from PIL import Image, ImageDraw

ASSETS = Path(__file__).resolve().parents[1] / "Sticker/Assets.xcassets/StatusIcon.imageset"


def draw_icon(size: int) -> Image.Image:
    # Use a 144-unit canvas so the fold and cutouts stay crisp at 18 points.
    image = Image.new("RGBA", (144, 144))
    draw = ImageDraw.Draw(image)
    ink = (0, 0, 0, 255)
    clear = (0, 0, 0, 0)

    draw.rounded_rectangle((18, 18, 125, 125), radius=16, fill=ink)
    draw.polygon(((86, 126), (126, 86), (126, 126)), fill=clear)
    draw.line(((86, 125), (86, 96), (96, 86), (125, 86)), fill=clear, width=8)
    draw.rounded_rectangle((39, 46, 102, 55), radius=4, fill=clear)
    draw.rounded_rectangle((39, 67, 81, 76), radius=4, fill=clear)

    return image.resize((size, size), resample=Image.Resampling.LANCZOS)


if __name__ == "__main__":
    for size in (18, 36, 54):
        draw_icon(size).save(ASSETS / f"status_{size}.png")
