"""Generate repeatable fine-pixel ant-hill surface textures.

All patterns are authored at 128 px and use a controlled palette taken from
the warm masonry, blue-green paint and dark roofs of the ant-hill reference.
Rerun this file to regenerate every PNG without changing scene geometry.
"""

import logging
from pathlib import Path
from random import Random

from PIL import Image, ImageDraw, ImageFont


OUT = Path(__file__).resolve().parent / "textures" / "anthill"
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 128


def rgb(code: str) -> tuple[int, int, int]:
    code = code.removeprefix("#")
    return tuple(int(code[i:i + 2], 16) for i in (0, 2, 4))


def shade(color: tuple[int, int, int], amount: int) -> tuple[int, int, int]:
    return tuple(max(0, min(255, c + amount)) for c in color)


def image(color: str) -> Image.Image:
    return Image.new("RGB", (SIZE, SIZE), rgb(color))


def grain(
    draw: ImageDraw.ImageDraw,
    seed: int,
    base: tuple[int, int, int],
    count: int = 330,
    step: int = 3,
    spread: int = 13,
) -> None:
    rng = Random(seed)
    for _ in range(count):
        x = rng.randrange(0, SIZE, step)
        y = rng.randrange(0, SIZE, step)
        c = shade(base, rng.randrange(-spread, spread + 1))
        w = rng.choice((1, 2, 3))
        draw.rectangle((x, y, min(127, x + w), min(127, y + w)), fill=c)


def save(name: str, im: Image.Image) -> None:
    im.save(OUT / f"{name}.png", optimize=True)


def paving(seed: int, name: str) -> None:
    rng = Random(seed)
    im = image("#504b4a")
    d = ImageDraw.Draw(im)
    base = rgb("#91847a")
    for row in range(4):
        for col in range(4):
            x0, y0 = col * 32, row * 32
            tile = shade(base, rng.randint(-12, 11))
            d.rectangle((x0 + 2, y0 + 2, x0 + 31, y0 + 31), fill=tile)
            d.line((x0 + 3, y0 + 3, x0 + 29, y0 + 3),
                   fill=shade(tile, 14), width=1)
            d.line((x0 + 31, y0 + 3, x0 + 31, y0 + 30),
                   fill=shade(tile, -16), width=2)
            for _ in range(9):
                x = x0 + rng.randrange(5, 28)
                y = y0 + rng.randrange(5, 28)
                c = shade(tile, rng.choice((-23, -16, -10, 8, 13)))
                d.rectangle((x, y, x + rng.choice((1, 2, 3)), y + 1), fill=c)
            if rng.random() < 0.38:
                x, y = x0 + rng.randrange(7, 24), y0 + rng.randrange(7, 23)
                d.line((x, y, x + 5, y + 2, x + 8, y + 2),
                       fill=shade(tile, -31), width=1)
    save(name, im)


for variant in range(4):
    paving(800 + variant * 101, f"paving_{variant}")


rng = Random(41)
im = image("#514744")
d = ImageDraw.Draw(im)
brick_colors = [rgb(c) for c in ("#88695e", "#9b7563", "#a07d6a", "#745b53")]
for row in range(8):
    offset = -16 if row % 2 else 0
    for x in range(offset, 128, 32):
        y = row * 16
        c = shade(rng.choice(brick_colors), rng.randint(-7, 7))
        d.rectangle((x + 2, y + 2, x + 31, y + 15), fill=c)
        d.line((x + 3, y + 3, x + 29, y + 3), fill=shade(c, 13))
        for _ in range(3):
            px = x + rng.randrange(5, 29)
            py = y + rng.randrange(5, 14)
            d.rectangle((px, py, px + 2, py + 1), fill=shade(c, -22))
save("brick", im)


im = image("#a89a88")
d = ImageDraw.Draw(im)
grain(d, 71, rgb("#a89a88"), 650, 3, 12)
rng = Random(72)
for _ in range(24):
    x, y = rng.randrange(9, 118), rng.randrange(9, 118)
    w, h = rng.randrange(3, 11), rng.randrange(2, 7)
    d.rectangle((x, y, x + w, y + h), fill=rng.choice((
        rgb("#958477"), rgb("#b6a894"), rgb("#8c796d"))))
    if rng.random() < 0.3:
        d.line((x, y, x + w + 2, y - 2), fill=rgb("#6f655e"))
save("plaster", im)


im = image("#aa9b8a")
d = ImageDraw.Draw(im)
grain(d, 81, rgb("#aa9b8a"), 490, 3, 13)
for y in (31, 63, 95, 127):
    d.line((0, y, 127, y), fill=rgb("#746d65"), width=2)
for row in range(4):
    for x in ((0, 64) if row % 2 else (32, 96)):
        d.line((x, row * 32, x, row * 32 + 30),
               fill=rgb("#82796d"), width=1)
save("stone", im)


im = image("#393b45")
d = ImageDraw.Draw(im)
rng = Random(91)
slates = [rgb(c) for c in ("#40434d", "#4c4c55", "#343945", "#55535a")]
for row in range(8):
    y = row * 16
    offset = -12 if row % 2 else 0
    for x in range(offset, 128, 24):
        c = shade(rng.choice(slates), rng.randint(-5, 5))
        d.rectangle((x + 1, y + 1, x + 23, y + 14), fill=c)
        d.line((x + 2, y + 2, x + 20, y + 2), fill=shade(c, 20))
        d.line((x + 3, y + 13, x + 22, y + 13), fill=shade(c, -22))
        if rng.random() < 0.3:
            d.rectangle((x + 6, y + 7, x + 11, y + 8), fill=shade(c, 10))
save("slate", im)


im = image("#77756e")
d = ImageDraw.Draw(im)
grain(d, 101, rgb("#77756e"), 700, 3, 11)
for edge in (31, 63, 95, 127):
    d.line((edge, 0, edge, 127), fill=rgb("#5a5c58"))
    d.line((0, edge, 127, edge), fill=rgb("#5a5c58"))
rng = Random(102)
for _ in range(25):
    x, y = rng.randrange(8, 120), rng.randrange(8, 120)
    d.line((x, y, x + rng.randrange(2, 9), y - 1),
           fill=rgb("#5e605b"), width=1)
save("roof_concrete", im)


im = image("#765844")
d = ImageDraw.Draw(im)
rng = Random(111)
for row in range(8):
    y = row * 16
    c = shade(rgb("#765844"), rng.randrange(-12, 13))
    d.rectangle((0, y + 1, 127, y + 15), fill=c)
    d.line((0, y, 127, y), fill=rgb("#3f342f"))
    d.line((0, y + 2, 127, y + 2), fill=shade(c, 15))
    for _ in range(11):
        x = rng.randrange(0, 125)
        gy = y + rng.randrange(5, 13)
        d.line((x, gy, x + rng.randrange(2, 15), gy),
               fill=shade(c, rng.choice((-18, -10, 12))), width=1)
save("wood", im)


im = image("#53616a")
d = ImageDraw.Draw(im)
grain(d, 121, rgb("#53616a"), 520, 3, 11)
rng = Random(122)
for _ in range(55):
    x, y = rng.randrange(0, 126), rng.randrange(0, 126)
    d.rectangle((x, y, x + rng.randrange(1, 4), y + 1),
                fill=rng.choice((rgb("#876452"), rgb("#64717a"),
                                 rgb("#35434c"))))
for x in (8, 120):
    for y in (8, 120):
        d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgb("#303b42"))
        d.point((x - 1, y - 1), fill=rgb("#a3a7a4"))
save("metal", im)


im = image("#617889")
d = ImageDraw.Draw(im)
for y in range(0, 128, 4):
    for x in range(0, 128, 4):
        c = rgb("#6b8292") if (x // 4 + y // 4) % 2 else rgb("#5d7485")
        d.rectangle((x, y, x + 3, y + 3), fill=c)
grain(d, 131, rgb("#617889"), 180, 4, 9)
save("fabric", im)


im = image("#3f686d")
d = ImageDraw.Draw(im)
grain(d, 141, rgb("#3f686d"), 260, 4, 7)
for offset in (-45, 5, 55):
    d.line((offset, 127, offset + 92, 0),
           fill=rgb("#71969a"), width=6)
    d.line((offset + 12, 127, offset + 104, 0),
           fill=rgb("#527d80"), width=2)
save("glass", im)


im = image("#4c4138")
d = ImageDraw.Draw(im)
grain(d, 151, rgb("#4c4138"), 850, 2, 20)
save("soil", im)


im = image("#566943")
d = ImageDraw.Draw(im)
rng = Random(161)
leaves = [rgb(c) for c in ("#647947", "#7f8b4a", "#9a9b4e", "#425b3d")]
for _ in range(310):
    x, y = rng.randrange(0, 126), rng.randrange(0, 126)
    w = rng.choice((2, 3, 4, 5))
    d.rectangle((x, y, x + w, y + rng.choice((2, 3, 4))),
                fill=rng.choice(leaves))
save("foliage", im)


im = image("#514b47")
d = ImageDraw.Draw(im)
grain(d, 171, rgb("#514b47"), 550, 3, 10)
save("grout", im)


im = image("#4f706c")
d = ImageDraw.Draw(im)
grain(d, 181, rgb("#4f706c"), 480, 3, 11)
rng = Random(182)
for _ in range(22):
    x, y = rng.randrange(4, 118), rng.randrange(4, 118)
    w, h = rng.randrange(3, 12), rng.randrange(2, 6)
    d.rectangle((x, y, x + w, y + h),
                fill=rng.choice((rgb("#6f8179"), rgb("#42615d"),
                                 rgb("#a29580"))))
save("paint_band", im)


im = image("#8e7867")
d = ImageDraw.Draw(im)
grain(d, 191, rgb("#8e7867"), 560, 3, 11)
for y in range(0, 128, 16):
    d.line((0, y, 127, y), fill=rgb("#6b5e55"), width=1)
save("stairs", im)


im = image("#a49b72")
d = ImageDraw.Draw(im)
rng = Random(201)
goods = [rgb(c) for c in ("#829263", "#bd8e5f", "#84665d", "#718a8d",
                          "#c1a667", "#745e7a")]
for y in range(0, 128, 24):
    for x in range(0, 128, 20):
        color = rng.choice(goods)
        d.rectangle((x + 2, y + 2, x + 18, y + 21), fill=color)
        d.rectangle((x + 5, y + 7, x + 15, y + 10), fill=shade(color, 29))
        d.line((x + 4, y + 16, x + 16, y + 16),
               fill=shade(color, -28), width=2)
save("goods", im)


im = image("#f0bb63")
d = ImageDraw.Draw(im)
for radius, c in [(58, "#f4c876"), (42, "#ffd88d"), (25, "#ffe4a5")]:
    d.ellipse((64 - radius, 64 - radius, 64 + radius, 64 + radius),
              fill=rgb(c))
grain(d, 211, rgb("#ffd88d"), 130, 4, 9)
save("lamp", im)


names = [
    "paving_0", "paving_1", "paving_2", "paving_3", "brick",
    "plaster", "stone", "slate", "roof_concrete", "wood", "metal",
    "fabric", "glass", "soil", "foliage", "grout", "paint_band",
    "stairs", "goods", "lamp",
]
columns = 5
cell = 154
sheet = Image.new("RGB", (columns * cell, 4 * cell), rgb("#1b232a"))
sd = ImageDraw.Draw(sheet)
font = ImageFont.load_default()
for index, name in enumerate(names):
    x = (index % columns) * cell + 13
    y = (index // columns) * cell + 8
    sheet.paste(Image.open(OUT / f"{name}.png"), (x, y))
    sd.text((x, y + 130), name, fill=rgb("#e9e4d8"), font=font)
sheet.save(OUT / "texture_contact_sheet.png", optimize=True)
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logging.info("Generated %s textures at %s", len(names), OUT)
