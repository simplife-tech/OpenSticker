from PIL import Image, ImageDraw

def draw_s_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    inset = size * 0.18
    w = size - inset * 2
    h = size - inset * 2
    x = inset
    y = inset

    path = [
        (x + w * 0.75, y + h * 0.95),
        (x + w * 0.30, y + h * 0.65),
        (x + w * 0.70, y + h * 0.35),
        (x + w * 0.25, y + h * 0.05),
    ]

    stroke_width = int(size * 0.12)

    draw.line(
        path,
        fill=(0, 0, 0, 255),
        width=stroke_width,
        joint="curve"
    )

    return img


def generate_status_icon(target_size: int, filename: str):
    # 1️⃣ 先用大尺寸画
    supersample_size = target_size * 8   # 8 倍超采样
    base = draw_s_icon(supersample_size)

    # 2️⃣ 高质量缩小
    icon = base.resize(
        (target_size, target_size),
        resample=Image.LANCZOS
    )

    icon.save(filename, "PNG")
    print(f"✅ generated {filename}")


generate_status_icon(18, "status_18.png")
generate_status_icon(36, "status_36.png")
generate_status_icon(44, "status_44.png")
