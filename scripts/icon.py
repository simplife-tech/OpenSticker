from PIL import Image, ImageDraw

SIZE = 1024
CORNER_RADIUS = 220

# 创建画布（RGBA）
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# =====================
# 1. 渐变背景
# =====================

top_color = (220, 248, 255)   # 浅蓝白
bottom_color = (142, 227, 255)

for y in range(SIZE):
    ratio = y / SIZE
    r = int(top_color[0] * (1 - ratio) + bottom_color[0] * ratio)
    g = int(top_color[1] * (1 - ratio) + bottom_color[1] * ratio)
    b = int(top_color[2] * (1 - ratio) + bottom_color[2] * ratio)
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

# =====================
# 2. 圆角裁剪
# =====================

mask = Image.new("L", (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
mask_draw.rounded_rectangle(
    (0, 0, SIZE, SIZE),
    radius=CORNER_RADIUS,
    fill=255
)

img.putalpha(mask)

# =====================
# 3. 异形 S 路径（用粗线模拟）
# =====================

s_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
s_draw = ImageDraw.Draw(s_layer)

inset = 280
w = SIZE - inset * 2
h = SIZE - inset * 2
x = inset
y = inset

# S 的路径点（手工设计）
path = [
    (x + w * 0.75, y + h * 0.95),
    (x + w * 0.25, y + h * 0.65),
    (x + w * 0.75, y + h * 0.35),
    (x + w * 0.25, y + h * 0.05),
]

s_draw.line(
    path,
    fill=(255, 255, 255, 245),
    width=110,
    joint="curve"
)

# 合成
img = Image.alpha_composite(img, s_layer)

# =====================
# 4. 保存
# =====================

img.save("icon.png", "PNG")
print("✅ icon.png 已生成")
