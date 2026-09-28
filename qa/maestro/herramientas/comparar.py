"""Compara dos capturas del emulador y dice si la camara se ha movido.

Godot pinta en un SurfaceView y Maestro no puede leer la posicion de la camara,
asi que se mide en la imagen: se recorta una zona del mapa (por defecto el
centro, lejos del HUD), se calcula la diferencia media y el desplazamiento por
correlacion de fase. Un desplazamiento de mas de ~3 px o una diferencia de mas
de ~4 (sobre 255) es que la vista ha cambiado.

Uso:
    python comparar.py antes.png despues.png [x0 y0 x1 y1]
    (recorte en fracciones de la imagen; por defecto 0.30 0.30 0.70 0.70)

Salida, una linea:  dif=<media> dx=<px> dy=<px> movido=<si|no>
"""
import sys

import numpy as np
from PIL import Image


def cargar(path, caja):
    img = Image.open(path).convert("L")
    w, h = img.size
    x0, y0, x1, y1 = caja
    return np.asarray(img.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h))), dtype=np.float64)


def desplazamiento(a, b):
    fa = np.fft.fft2(a - a.mean())
    fb = np.fft.fft2(b - b.mean())
    r = fa * np.conj(fb)
    r /= np.abs(r) + 1e-9
    c = np.abs(np.fft.ifft2(r))
    dy, dx = np.unravel_index(np.argmax(c), c.shape)
    if dy > a.shape[0] // 2:
        dy -= a.shape[0]
    if dx > a.shape[1] // 2:
        dx -= a.shape[1]
    return int(dx), int(dy)


def comparar(p1, p2, caja=(0.30, 0.30, 0.70, 0.70)):
    a, b = cargar(p1, caja), cargar(p2, caja)
    dif = float(np.abs(a - b).mean())
    dx, dy = desplazamiento(a, b)
    movido = dif > 4.0 or abs(dx) > 3 or abs(dy) > 3
    return dif, dx, dy, movido


if __name__ == "__main__":
    if len(sys.argv) not in (3, 7):
        print(__doc__)
        sys.exit(2)
    caja = tuple(float(v) for v in sys.argv[3:7]) if len(sys.argv) == 7 else (0.30, 0.30, 0.70, 0.70)
    dif, dx, dy, movido = comparar(sys.argv[1], sys.argv[2], caja)
    print("dif=%.1f dx=%d dy=%d movido=%s" % (dif, dx, dy, "si" if movido else "no"))
