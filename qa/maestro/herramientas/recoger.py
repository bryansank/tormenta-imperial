"""Junta en una carpeta plana las capturas de una o varias ejecuciones de la CLI.

`maestro test --test-output-dir D` deja las capturas de cada flujo en
D/<fecha_hora>/<nombre del flujo>/takeScreenshot/*.png. Este script las copia
todas a una carpeta plana (la mas reciente gana si un nombre se repite), que es lo
que leen hoja.py, comparar.py y analizar_arrastre.py.

Uso:
    python recoger.py <test-output-dir> <carpeta_plana>
"""
import glob
import os
import shutil
import sys


def recoger(origen, destino):
    os.makedirs(destino, exist_ok=True)
    rutas = sorted(glob.glob(os.path.join(origen, "*", "*", "takeScreenshot", "*.png")), key=os.path.getmtime)
    for ruta in rutas:
        shutil.copy2(ruta, os.path.join(destino, os.path.basename(ruta)))
    print(len(rutas), "capturas copiadas a", destino)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    recoger(sys.argv[1], sys.argv[2])
