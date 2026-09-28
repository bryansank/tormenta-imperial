"""Hoja de contactos: junta en una imagen las capturas de un flujo, con su nombre.

Uso:
    python hoja.py <carpeta> <prefijo> <salida.png> [columnas]
    p. ej.  python hoja.py qa-out 02_ hoja_02.png 3
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

ANCHO, ALTO, RÓTULO = 640, 400, 22


def hoja(carpeta, prefijo, salida, columnas=2):
    rutas = sorted(glob.glob(os.path.join(carpeta, prefijo + "*.png")))
    if not rutas:
        print("sin capturas para", prefijo)
        return
    filas = (len(rutas) + columnas - 1) // columnas
    out = Image.new("RGB", (columnas * ANCHO, filas * (ALTO + RÓTULO)), "white")
    d = ImageDraw.Draw(out)
    for i, ruta in enumerate(rutas):
        x, y = (i % columnas) * ANCHO, (i // columnas) * (ALTO + RÓTULO)
        out.paste(Image.open(ruta).convert("RGB").resize((ANCHO, ALTO)), (x, y + RÓTULO))
        d.text((x + 4, y + 4), os.path.basename(ruta), fill="black")
    out.save(salida)
    print(salida, len(rutas), "capturas")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(2)
    hoja(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 2)
