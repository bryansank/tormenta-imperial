# QA en tableta con Maestro

Flujos de regresión para los bugs de jugabilidad que Bryan encontró en su tableta.
Corren en el emulador Android `TI_Pixel_Tablet` (2560x1600, apaisado, Android 16
x86_64) con un APK solo para QA. Cada paso deja una captura. Se leen a ojo o con los
scripts de `herramientas/`.

Los resultados de la primera pasada (2026-09-28, código de `build/exportar-android`)
están en `tormenta-imperial-contexto\08_QA_TABLET_MAESTRO.md`.

## Por qué coordenadas y no textos

Godot pinta todo en un único `SurfaceView`. `maestro hierarchy` e `inspect_screen` no
ven ni un botón del juego. Por eso los flujos:

- tocan por **coordenadas en porcentaje** (`tapOn: {point: "18%,38%"}`), que aguantan
  otras resoluciones con la misma relación de aspecto. Los porcentajes solo admiten
  enteros;
- esperan con `comun/esperar.yaml` (espera fija: un `extendedWaitUntil` opcional a un
  texto que nunca aparece);
- capturan en cada paso (`takeScreenshot`), y la comprobación la hace quien mira la
  captura o `herramientas/comparar.py`.

Si un arreglo mueve un botón, hay que tocar su coordenada. Cada flujo lleva en la
cabecera qué se espera ver cuando el bug esté arreglado.

## 1. Arrancar el emulador

```bash
SDK="$LOCALAPPDATA/Android/Sdk"
"$SDK/emulator/emulator.exe" -avd TI_Pixel_Tablet -gpu host -no-snapshot-save &
"$SDK/platform-tools/adb.exe" wait-for-device
until [ "$("$SDK/platform-tools/adb.exe" shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 3; done
```

El id del dispositivo suele ser `emulator-5554` (`adb devices`).

## 2. Construir e instalar el APK de QA

El APK real (preset `Android`: arm64, renderer Mobile/Vulkan) sale **en negro** en el
emulador de Windows: `ERROR: Couldn't present to Vulkan queue (VkResult error 5)`.
Se ha comprobado también con `-gpu host`. Para el emulador existe un segundo preset,
`Android QA (emulador)`:

| | Android (real) | Android QA (emulador) |
|---|---|---|
| ABI | arm64-v8a | x86_64 |
| Renderer | Mobile (Vulkan) | Compatibility (OpenGL ES 3), por `command_line/extra_args` |
| Paquete | `com.bryankey.tormentaimperial` | `com.bryankey.tormentaimperial.qa` |
| Salida | `build/android/TormentaImperial-debug.apk` | `build/android/TormentaImperial-qa.apk` |

Los dos excluyen lo mismo y ninguno guarda secretos (`tests/build/test_export_guards.gd`).
Pueden estar instalados a la vez.

**Antes de lanzar Godot** (importar, exportar o tests) tiene que haber un `override.cfg`
en la raíz del proyecto con una carpeta de usuario propia. Si no, Godot escribe logs
en la del jugador (`%APPDATA%\Godot\app_userdata\Tormenta Imperial`). El fichero está
en `.gitignore` y el preset lo excluye del paquete:

```ini
[application]
config/use_custom_user_dir=true
config/custom_user_dir_name="TI_qa_tablet"
```

```bash
GODOT=".../Godot_v4.7-stable_mono_win64_console.exe"
"$SDK/platform-tools/adb.exe" start-server       # evita que el export se quede colgado
"$GODOT" --headless --path . --export-debug "Android QA (emulador)" build/android/TormentaImperial-qa.apk
"$SDK/platform-tools/adb.exe" install -r build/android/TormentaImperial-qa.apk
```

El export tarda en torno a 1 minuto y el APK pesa unos 40 MB. `build/` no se versiona.

## 3. Correr los flujos

Hace falta Maestro CLI (`~/.maestro/bin/maestro`). Desde `qa/maestro/`:

```bash
RUN=/tmp/ti-maestro          # salida cruda de la CLI (logs, jerarquías, capturas)
OUT=/ruta/a/capturas         # carpeta plana, p. ej. tormenta-imperial-contexto/qa-tablet
maestro --device emulator-5554 test --test-output-dir "$RUN" 01_lore_atras.yaml
maestro --device emulator-5554 test --test-output-dir "$RUN" .       # todos los .yaml
python herramientas/recoger.py "$RUN" "$OUT"
```

- Las capturas se llaman `<flujo>_<paso>_<qué>.png`. La CLI las deja en
  `$RUN/<fecha>/<nombre del flujo>/takeScreenshot/` y `recoger.py` las junta en `$OUT`.
  La CLI rechaza rutas fuera de su carpeta de salida, así que con la CLI **no** se
  pasa `OUT` como variable.
- Con varios ficheros, la CLI no imprime nada hasta acabar ("Waiting for flows to
  complete..."). El progreso está en `$RUN/<fecha>/<flujo>/logs/maestro.log`.
- Con el MCP de Maestro (que no tiene `--test-output-dir`), la ruta se pasa como
  variable: `env: {OUT: "C:/…/qa-tablet"}`. Lo resuelve `comun/salida.yaml`.
- Todos los flujos arrancan con `clearState`: sin partida guardada, con los ajustes
  de fábrica y la introducción sin ver. El primer arranque tras `clearState` tarda
  20-30 s (splash de Godot + carga), y `comun/arrancar.yaml` espera 35 s.
- Un flujo completo dura entre 1 y 4 minutos. El 06 (16 arrastres) y el 07 (espera 90 s
  a propósito) son los largos.
- `qa-out/` (la carpeta por defecto si se lanza sin `--test-output-dir`) está en
  `.gitignore`. Nunca se versionan capturas ni APKs.

## 4. Los flujos

| Flujo | Bug | Qué mirar |
|---|---|---|
| `01_lore_atras.yaml` | El lore solo tiene "Siguiente" | Prólogo de 6 folios: `01_02` en el folio 2, `01_03` (◀ Atrás) y `01_05` (deslizar a la derecha) de vuelta al 1. El atrás de Android cierra el prólogo, no la app (`01_06`) |
| `02_ajustes_responden.yaml` | Ajustes "pegado" | Desde ☰ MENÚ (dos veces) y desde el título: los % y los interruptores cambian entre `_a` y `_e` |
| `02b_ajustes_titulo_limpio.yaml` | Ajustes "pegado" (el caso que fallaba) | Instalación limpia → AJUSTES del título: nada encima, responde (`02b_a`…`02b_g`); el prólogo solo sale tras Nueva partida y se salta (`02b_i`, `02b_j`) |
| `03_menu_principal.yaml` | No deja salir al menú principal | ☰ MENÚ → Menú principal → Continuar (`03_02`, `03_03`); con el panel del Núcleo abierto el MENÚ se abre igual (`03_05`); el atrás de Android abre y cierra el MENÚ (`03_07`, `03_08`) |
| `04_construir_aserradero.yaml` | No deja construir el aserradero | Lista llena y X a la vista (`04_01`), CONSTRUIR del detalle visible (`04_02`), casillas verdes + ✓ + tutorial sin taparlo (`04_03`), aserradero en obras y oro 300→220 (`04_04`) |
| `05_mantener_dpad.yaml` | Mantener pulsado debería repetir | Pares `05_*` con `comparar.py` |
| `06_arrastre_vista.yaml` | El arrastre solo funciona en algunos sitios | `herramientas/analizar_arrastre.py` → tabla 4x4 y mapa |
| `07_ayudas_cerrar.yaml` | Las ayudas no se cierran | Tras saltar el tutorial: una ayuda cada vez, con ✕ y barra (`07_00`, `07_04`), se van solas (`07_01`..`07_03`); ☰ MENÚ → AYUDA abre el índice (`07_05`) y reabre una (`07_06`) |
| `08_rotar_dos_dedos.py` | El giro con dos dedos no rota | Script de adb (Maestro no tiene multitouch). Tabla pellizco/giro. **Ojo:** los toques de `adb emu event send` llegan a Android (se ven con "Ubicación del puntero") pero **no a la app**: con logs en `InputService` no entra ni un evento, mientras que `adb shell input swipe` (el control de un dedo) sí. En el emulador el resultado de dos dedos no es concluyente; lo fija `tests/input/test_twist_gesture.gd` y hay que probarlo en una tableta real |

`comun/` contiene los trozos compartidos: `arrancar`, `nueva_partida`, `saltar_lore`
("Saltar historia" del prólogo), `saltar_tutorial`, `en_partida` (los cuatro seguidos),
`probar_ajustes`, `esperar` y `salida`. Las coordenadas son las de la interfaz tras #31
(☰ MENÚ arriba a la derecha, CONSTRUIR abajo al centro), #32 (prólogo y tutorial) y
#34 (✓ CONSTRUIR AQUÍ).

## 5. Leer los resultados

```bash
cd qa/maestro/herramientas
python hoja.py "$OUT" 02_ hoja_02.png 3            # hoja de contactos de un flujo
python comparar.py "$OUT/05_a0_antes_toque.png" "$OUT/05_a1_tras_toque.png"
python analizar_arrastre.py "$OUT" "$OUT/06_mapa.png" # tabla de cobertura del arrastre
```

`comparar.py` recorta el centro del mapa y mide la diferencia media (0-255) y el
desplazamiento en px por correlación de fase. `movido=si` cuando la diferencia supera
4 o el desplazamiento pasa de 3 px. Un zoom o un giro no son un desplazamiento puro, así
que ahí manda la diferencia.

### Dos dedos (08)

Con la partida en pantalla (por ejemplo, al terminar `05_mantener_dpad.yaml`):

```bash
python 08_rotar_dos_dedos.py "$OUT"
```

Inyecta los dedos por la consola del emulador (`adb emu event send EV_ABS:ABS_MT_…`),
que llegan a `/dev/input/event2` (`virtio_input_multi_touch_1`, protocolo B). No
necesita root. `sendevent` directo no sirve, porque SELinux se lo deniega al usuario
`shell` en una imagen "user". Primero hace un arrastre de un dedo, que es el control
(si panea, la inyección llega). Después dos pellizcos y un giro de 90° en cada
sentido, a distancia constante. Al final repite con "Ubicación del puntero" encendida
y guarda `08_*_traza.png`, donde Android pinta los dedos que recibe.

## Trampas conocidas

- El botón **atrás** de Android (`- back`) cierra el juego entero (`quit_on_go_back`
  por defecto). Por eso los flujos que lo prueban lo dejan para el final.
- Si Maestro dice `Device server died … UNAVAILABLE` tras reiniciar el emulador, el
  servidor de Maestro se ha quedado con la sesión vieja. La CLI vuelve a instalar su
  driver en cada ejecución; el MCP puede necesitar reiniciarse.
- Las coordenadas son las de la base `feat/hito-3-expedicion` 2a3ec3e (pantalla
  completa con `aspect=expand`, selector de modo en "Nueva partida"). En el build
  que jugó Bryan (`e591ea7`) había franjas negras arriba y abajo y todo estaba en
  otro sitio; sus capturas están en `qa-tablet\e1_build_jugado\`.
- Menú de título sin partida: Nueva partida 21 %,36 % · AJUSTES 21 %,45 %. Con partida
  guardada se añade "Continuar" arriba: Continuar 21 %,29 % · Nueva partida 21 %,43 % ·
  AJUSTES 21 %,52 %.
- En el selector de modo, el primer toque en EMPEZAR a veces no responde en el
  emulador. `comun/nueva_partida.yaml` toca dos veces.
- Maestro `hideKeyboard` es un "atrás" y cierra el juego. No se usa.
