"""Gera os ícones da versão web (PWA). Uso: python3 tool/make_web_icons.py

Marca provisória: "H" branco sobre o verde do tema Floresta.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFont

GREEN = (61, 107, 90)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
out = pathlib.Path(__file__).resolve().parent.parent / "web"


def icon(size: int, *, maskable: bool = False, rounded: bool = True) -> Image.Image:
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if maskable or not rounded:
        d.rectangle([0, 0, s, s], fill=GREEN)
    else:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=GREEN)
    # Área segura do ícone "maskable": 80% central.
    glyph = int(s * (0.46 if maskable else 0.6))
    font = ImageFont.truetype(FONT, glyph)
    box = d.textbbox((0, 0), "H", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((s - w) / 2 - box[0], (s - h) / 2 - box[1]), "H", font=font, fill="white")
    # Pontinho: "humano", um toque de calor.
    r = int(s * (0.045 if maskable else 0.06))
    cx, cy = s / 2 + w / 2 + r * 1.2, (s + h) / 2 - r
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 196, 120))
    return img.resize((size, size), Image.LANCZOS)


icon(192).save(out / "icons/Icon-192.png")
icon(512).save(out / "icons/Icon-512.png")
icon(192, maskable=True).save(out / "icons/Icon-maskable-192.png")
icon(512, maskable=True).save(out / "icons/Icon-maskable-512.png")
# iOS aplica o próprio arredondamento: quadrado cheio.
icon(180, rounded=False).save(out / "icons/apple-touch-icon.png")
icon(32).save(out / "favicon.png")
