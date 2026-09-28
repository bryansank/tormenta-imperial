"""08 · Giro y pellizco con dos dedos en el emulador (Maestro no tiene multitouch).

Bug de Bryan: "no me agarra el gesto de rotar la camara en tablet".

Inyecta toques reales de dos dedos en la pantalla tactil virtual del emulador
(/dev/input/event2, "virtio_input_multi_touch_1", protocolo B de Linux) con
`sendevent`. El usuario `shell` de adb esta en el grupo `input`, asi que no hace
falta root. Cada gesto se hace con la partida ya en pantalla (por ejemplo, tras
`maestro test 05_mantener_dpad.yaml` o con comun/en_partida.yaml), con captura
antes y despues, y se compara con herramientas/comparar.py.

    python 08_rotar_dos_dedos.py [carpeta_capturas]

Gestos:
  pellizco  - dos dedos que se separan (control: debe hacer zoom; demuestra que
              la inyeccion de dos dedos llega al juego)
  giro      - dos dedos que giran 90 grados alrededor del centro a distancia
              constante. Hoy la vista NO gira. Esperado: gira.
  giro_inv  - el mismo giro al reves.

Variables: ADB (ruta a adb), DISPOSITIVO (por defecto emulator-5554),
TOUCH_DEV (por defecto /dev/input/event2).
"""
import math
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "herramientas"))
from comparar import comparar  # noqa: E402

ADB = os.environ.get("ADB", os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"))
DISPOSITIVO = os.environ.get("DISPOSITIVO", "emulator-5554")
TOUCH_DEV = os.environ.get("TOUCH_DEV", "/dev/input/event2")
ANCHO, ALTO = 2560, 1600          # pantalla del TI_Pixel_Tablet en apaisado
ABS_MAX = 32767                    # rango de ABS_MT_POSITION_X/Y del emulador

EV_SYN, EV_ABS = 0, 3
ABS_MT_SLOT, ABS_MT_TOUCH_MAJOR, ABS_MT_X, ABS_MT_Y = 0x2F, 0x30, 0x35, 0x36
ABS_MT_TRACKING_ID, ABS_MT_PRESSURE = 0x39, 0x3A


def adb(*args, **kw):
    return subprocess.run([ADB, "-s", DISPOSITIVO, *args], check=True, **kw)


def _abs(px, eje):
    return int(round(px * ABS_MAX / (ANCHO if eje == "x" else ALTO)))


def _ev(t, c, v):
    return "sendevent %s %d %d %d" % (TOUCH_DEV, t, c, v)


def gesto(trayectorias, pausa_s=0.016):
    """trayectorias: lista de pasos; cada paso = [(x0, y0), (x1, y1)] en px."""
    lineas = []
    for paso_i, paso in enumerate(trayectorias):
        for slot, (x, y) in enumerate(paso):
            lineas.append(_ev(EV_ABS, ABS_MT_SLOT, slot))
            if paso_i == 0:
                lineas.append(_ev(EV_ABS, ABS_MT_TRACKING_ID, 700 + slot))
                lineas.append(_ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 6))
                lineas.append(_ev(EV_ABS, ABS_MT_PRESSURE, 60))
            lineas.append(_ev(EV_ABS, ABS_MT_X, _abs(x, "x")))
            lineas.append(_ev(EV_ABS, ABS_MT_Y, _abs(y, "y")))
        lineas.append(_ev(EV_SYN, 0, 0))
        lineas.append("sleep %.3f" % pausa_s)
    for slot in range(len(trayectorias[0])):
        lineas.append(_ev(EV_ABS, ABS_MT_SLOT, slot))
        lineas.append(_ev(EV_ABS, ABS_MT_TRACKING_ID, -1))
    lineas.append(_ev(EV_SYN, 0, 0))
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, newline="\n") as f:
        f.write("\n".join(lineas) + "\n")
        local = f.name
    adb("push", local, "/data/local/tmp/ti_gesto.sh", capture_output=True)
    adb("shell", "sh /data/local/tmp/ti_gesto.sh")
    os.unlink(local)


def giro(grados, radio=320, pasos=24, cx=ANCHO / 2, cy=ALTO * 0.45):
    tr = []
    for i in range(pasos + 1):
        a = math.radians(grados * i / pasos)
        tr.append([(cx + radio * math.cos(a), cy + radio * math.sin(a)),
                   (cx - radio * math.cos(a), cy - radio * math.sin(a))])
    return tr


def pellizco(r0=150, r1=500, pasos=20, cx=ANCHO / 2, cy=ALTO * 0.45):
    tr = []
    for i in range(pasos + 1):
        r = r0 + (r1 - r0) * i / pasos
        tr.append([(cx - r, cy), (cx + r, cy)])
    return tr


def captura(carpeta, nombre):
    ruta = os.path.join(carpeta, nombre + ".png")
    with open(ruta, "wb") as f:
        f.write(adb("exec-out", "screencap", "-p", capture_output=True).stdout)
    return ruta


def main():
    carpeta = sys.argv[1] if len(sys.argv) > 1 else "qa-out"
    os.makedirs(carpeta, exist_ok=True)
    import time
    pruebas = [("pellizco", pellizco()), ("giro", giro(90)), ("giro_inv", giro(-90))]
    print("| Gesto | dif media | dx | dy | Cambio la vista |")
    print("|---|---|---|---|---|")
    for nombre, tr in pruebas:
        antes = captura(carpeta, "08_%s_0" % nombre)
        gesto(tr)
        time.sleep(1.5)
        despues = captura(carpeta, "08_%s_1" % nombre)
        dif, dx, dy, movido = comparar(antes, despues, (0.20, 0.20, 0.80, 0.70))
        print("| %s | %.1f | %d | %d | %s |" % (nombre, dif, dx, dy, "SI" if movido else "no"))


if __name__ == "__main__":
    main()
