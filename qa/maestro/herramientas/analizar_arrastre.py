"""Tabla de cobertura del arrastre a partir de las capturas del flujo 06.

Busca pares 06_r<fila>c<col>_x<X>y<Y>_0.png / _1.png en la carpeta, compara cada
par con comparar.py (zona central del mapa) y escribe una tabla Markdown 4x4 con
"SI" (la vista se movio) o "no". Tambien pinta un mapa sobre la primera captura:
circulo verde = mueve, rojo = no mueve.

Uso:
    python analizar_arrastre.py <carpeta> [mapa_salida.png]
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comparar import comparar  # noqa: E402

PATRON = re.compile(r"06_r(\d)c(\d)_x(\d+)y(\d+)_0\.png$")


def analizar(carpeta, mapa=None):
    celdas = {}
    for p0 in sorted(glob.glob(os.path.join(carpeta, "06_r*_0.png"))):
        m = PATRON.search(os.path.basename(p0))
        if not m:
            continue
        p1 = p0[:-6] + "_1.png"
        if not os.path.exists(p1):
            continue
        fila, col, x, y = (int(v) for v in m.groups())
        # Zona de medida: franja central del mapa, sin el HUD de arriba ni la
        # cruceta. Un arrastre de camara la desplaza entera.
        dif, dx, dy, movido = comparar(p0, p1, (0.25, 0.30, 0.75, 0.60))
        celdas[(fila, col)] = (x, y, movido, dif, dx, dy)
    if not celdas:
        print("no hay capturas 06_* en", carpeta)
        return
    xs = sorted({v[0] for v in celdas.values()})
    ys = sorted({v[1] for v in celdas.values()})
    print("| y \\ x | " + " | ".join("%d %%" % x for x in xs) + " |")
    print("|---" * (len(xs) + 1) + "|")
    for f, y in enumerate(ys):
        fila = []
        for c, x in enumerate(xs):
            v = celdas.get((f, c))
            fila.append("?" if v is None else ("SI (dif %.0f)" % v[3] if v[2] else "no (dif %.0f)" % v[3]))
        print("| %d %% | " % y + " | ".join(fila) + " |")
    total = len(celdas)
    si = sum(1 for v in celdas.values() if v[2])
    print("\nMueven %d de %d puntos." % (si, total))
    if mapa:
        base = sorted(glob.glob(os.path.join(carpeta, "06_r0c0_*_0.png")))[0]
        img = Image.open(base).convert("RGB")
        w, h = img.size
        d = ImageDraw.Draw(img)
        r = int(w * 0.02)
        for (x, y, movido, *_rest) in celdas.values():
            cx, cy = int(w * x / 100), int(h * y / 100)
            color = (40, 220, 40) if movido else (230, 30, 30)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color, width=8)
            d.line((cx, cy, cx + (w // 10 if x < 50 else -w // 10), cy), fill=color, width=6)
        img.save(mapa)
        print("mapa:", mapa)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    analizar(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
