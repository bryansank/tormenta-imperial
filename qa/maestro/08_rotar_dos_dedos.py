"""08 · Giro y pellizco con dos dedos en el emulador (Maestro no tiene multitouch).

Bug de Bryan: "no me agarra el gesto de rotar la camara en tablet".

Inyecta toques de uno y dos dedos en la pantalla tactil virtual del emulador
("virtio_input_multi_touch_1", /dev/input/event2, protocolo B de Linux) a traves
de la consola del emulador: `adb emu event send EV_ABS:ABS_MT_...`. No hace falta
root. `sendevent` directo no sirve: en una imagen "user" SELinux se lo deniega al
usuario shell. Cada gesto se hace con la partida ya en pantalla (por ejemplo, al
terminar 07_ayudas_cerrar.yaml), con captura antes y despues, y se compara con
herramientas/comparar.py.

    python 08_rotar_dos_dedos.py [carpeta_capturas]

Gestos:
  un_dedo          - arrastre de un dedo: CONTROL de que la inyeccion llega (debe panear)
  pellizco_abrir   - dos dedos que se separan: deberia hacer zoom
  pellizco_cerrar  - dos dedos que se juntan: deberia hacer zoom
  giro / giro_inv  - dos dedos que giran 90 grados a distancia constante.
                     Esperado tras el arreglo: la vista gira.
Despues repite pellizco y giro con "Ubicacion del puntero" encendida y guarda
08_*_traza.png, donde se ve si Android recibe los dos dedos.

Variables: ADB (ruta a adb), DISPOSITIVO (por defecto emulator-5554).
"""
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "herramientas"))
from comparar import comparar  # noqa: E402

ADB = os.environ.get("ADB", os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"))
DISPOSITIVO = os.environ.get("DISPOSITIVO", "emulator-5554")
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
    return "%d:%d:%d" % (t, c, v)


def _consola(eventos):
    # Consola del emulador: `adb emu event send tipo:codigo:valor ...`. Llega a la
    # pantalla tactil virtual sin root. (sendevent sobre /dev/input/event2 no vale:
    # SELinux lo deniega al usuario shell en una imagen "user", aunque este en el
    # grupo input.)
    adb("emu", "event", "send", *eventos, capture_output=True)


def gesto(trayectorias, pausa_s=0.016):
    """trayectorias: lista de pasos; cada paso = [(x0, y0), (x1, y1)] en px."""
    import time
    for paso_i, paso in enumerate(trayectorias):
        evs = []
        for slot, (x, y) in enumerate(paso):
            evs.append(_ev(EV_ABS, ABS_MT_SLOT, slot))
            if paso_i == 0:
                evs.append(_ev(EV_ABS, ABS_MT_TRACKING_ID, 700 + slot))
                evs.append(_ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 6))
                evs.append(_ev(EV_ABS, ABS_MT_PRESSURE, 60))
            evs.append(_ev(EV_ABS, ABS_MT_X, _abs(x, "x")))
            evs.append(_ev(EV_ABS, ABS_MT_Y, _abs(y, "y")))
        evs.append(_ev(EV_SYN, 0, 0))
        _consola(evs)
        time.sleep(pausa_s)
    evs = []
    for slot in range(len(trayectorias[0])):
        evs.append(_ev(EV_ABS, ABS_MT_SLOT, slot))
        evs.append(_ev(EV_ABS, ABS_MT_TRACKING_ID, -1))
    evs.append(_ev(EV_SYN, 0, 0))
    _consola(evs)


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
    pruebas = [
        ("un_dedo", [[(1000 + 30 * i, 700)] for i in range(15)]),   # control de la inyeccion
        ("pellizco_abrir", pellizco()),
        ("pellizco_cerrar", pellizco(500, 150)),
        ("giro", giro(90)),
        ("giro_inv", giro(-90)),
    ]
    print("| Gesto | dif media | dx | dy | Cambio la vista |")
    print("|---|---|---|---|---|")
    for nombre, tr in pruebas:
        antes = captura(carpeta, "08_%s_0" % nombre)
        gesto(tr)
        time.sleep(1.5)
        despues = captura(carpeta, "08_%s_1" % nombre)
        dif, dx, dy, movido = comparar(antes, despues, (0.20, 0.20, 0.80, 0.70))
        print("| %s | %.1f | %d | %d | %s |" % (nombre, dif, dx, dy, "SI" if movido else "no"))
    # Segunda pasada con "Ubicacion del puntero" (opciones de desarrollador): Android
    # pinta los dedos que VE. Las capturas _traza demuestran si los dos dedos llegan
    # al sistema aunque el juego no reaccione. No se mide la camara en esta pasada,
    # porque la capa de trazas ensucia la comparacion.
    adb("shell", "settings put system pointer_location 1")
    time.sleep(1.0)
    try:
        for nombre, tr in (("pellizco_abrir", pellizco()), ("giro", giro(90))):
            gesto(tr)
            time.sleep(0.4)
            captura(carpeta, "08_%s_traza" % nombre)
    finally:
        adb("shell", "settings put system pointer_location 0")


if __name__ == "__main__":
    main()
