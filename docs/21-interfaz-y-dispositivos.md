# 21 · Interfaz configurable y perfiles de dispositivo

La interfaz se adapta al dispositivo (PC, tablet, móvil) y el jugador puede
cambiarla: escala y tamaño de texto, qué elementos del HUD se ven, dónde están,
colores para daltonismo, alto contraste y opacidad de paneles. Todo es del
**dispositivo**: vive en `user://settings.cfg`, sección `[interfaz]`, nunca en la
partida. Dispositivos principales: tablet Android apaisada (táctil) y PC (ratón
y teclado). El móvil es secundario.

## 1. Perfiles de dispositivo (`DeviceProfile`)

Autoload `scripts/services/DeviceProfile.gd`, el último de `project.godot`.

### Detección (`DeviceProfile.detect_from`, pura)

| Regla | Perfil |
|---|---|
| Sin feature de móvil (`android`, `ios`, `mobile`, `web_android`, `web_ios`) | **PC**. Un portátil Windows táctil sigue siendo PC |
| Feature de móvil y lado corto ≥ **600 dp** (`px / (dpi / 160)`, la regla de Android) | **Tablet** |
| Feature de móvil y lado corto < 600 dp | **Móvil** |
| Sin dpi conocido (web) | se mide en píxeles (dpi 160) |

Ajustes → Interfaz → *Perfil de dispositivo*: **Automático (detectado)** / PC /
Tablet / Móvil (`GameConfig.ui_device_profile`: `auto`, `pc`, `tablet`, `phone`).

### Lo que trae cada perfil (`DeviceProfile.DEFAULTS`)

| | PC | Tablet | Móvil |
|---|---|---|---|
| Escala de interfaz | 100 % | 115 % | 130 % |
| Tamaño de texto | normal | normal | grande |
| Lado táctil mínimo (`UITheme.MIN_BTN_H`) | 44 | 48 | 52 |
| Controles en pantalla en "Automático" | **no** (norma de Bryan) | sí | sí |
| Variante de disposición | standard | standard | compact (sin globos de ayuda) |
| Textos de ayuda | ratón | dedo | dedo |
| Disposición movida | la suya | la suya | la suya |

"Automático" en *Controles en pantalla* ya no se enciende en un PC porque llegue
un toque: un portátil táctil tocado una vez no se llena de flechas. Quien los
quiera en PC elige **Siempre** o el perfil Tablet.

### Escala y proporción de pantalla

`project.godot`: `stretch/mode = canvas_items`, **`aspect = expand`** (antes
`keep_height`, que ponía bandas negras en 16:10 y 4:3). El lienzo base es
1280x720 y el lado que sobra se convierte en lienzo, no en negro. La escala de
interfaz es `Window.content_scale_factor` (`DeviceProfile.content_scale_for`,
pura): el texto se sigue rasterizando a la resolución real, nítido.

| Ventana | Perfil / escala | Lienzo lógico |
|---|---|---|
| 1280x720 (16:9) | PC 100 % | 1280x720 |
| 1280x720 | PC 75 % | 1707x960 |
| 1280x720 | PC 150 % → 133 % | 960x540 |
| 2560x1600 / 1280x800 (16:10) | Tablet 115 % | 1113x696 |
| 2048x1536 / 1024x768 (4:3) | Tablet 115 % | 1113x835 |
| 2560x1080 (21:9) | PC 100 % | 1707x720 |
| 400x720 (vertical) | Móvil | 400x720 (columna única) |

- En apaisado el lienzo nunca baja de **540** de alto (`MIN_LOGICAL_HEIGHT`): es
  lo que ocupa el menú ☰ desplegado. Por eso 150 % en 1280x720 se queda en 133 %.
- En vertical el ancho lógico se lleva a 480 (y nunca menos de 400) para que el
  móvil use la disposición estrecha.
- La escala se aplica al momento y al girar la tablet (`size_changed`). En
  headless no se toca: los tests miden contra 1280x720.
- La vista 2D descuenta la escala en su cámara (`Camera2DController.ui_scale`):
  la escala es de la interfaz, no un zoom del mapa. La 3D no la necesita.

### Arranque

La pantalla de arranque de Godot se sustituye por el logo de la marca
(`assets/branding/logo.png`, a su tamaño, sobre `Color(0.05, 0.06, 0.04)`).

## 2. Ajustes en pestañas

`SettingsPanel` tiene cinco pestañas, cada una con su scroll (cabe a 1024x768,
en tablet y con letra grande) y su **Restablecer esta pestaña** (menos Juego):

| Pestaña | Qué hay |
|---|---|
| **Audio** | Volumen general, música sí/no (sigue en el menú ☰), música, efectos |
| **Interfaz** | Perfil de dispositivo, escala, tamaño de texto · Vista 3D/2D, rejilla, pantalla completa · Elementos en pantalla (un interruptor por elemento) · Editar / Restablecer disposición |
| **Controles** | Controles en pantalla (Automático / Siempre / Nunca) y el resumen de controles en ratón o en dedo |
| **Accesibilidad** | Paleta de colores, alto contraste, opacidad de paneles, vista previa |
| **Juego** | Idioma, Nueva partida |

Qué se aplica al momento: audio, vista, rejilla, pantalla completa, controles,
escala, mostrar/ocultar HUD y la disposición. Lo que cambia tokens de `UITheme`
(texto, paleta, contraste, opacidad, perfil) se ve en la **vista previa** y se
aplica con **APLICAR CAMBIOS** o al cerrar Ajustes: los paneles se construyen una
vez, así que `DeviceProfile.rebuild_ui()` recarga la escena conservando la partida
(la misma recarga que el cambio de idioma) y vuelve a abrir Ajustes en la
pestaña donde estaba. Con un tablero de combate abierto no se recarga: se guarda
y se verá al terminar.

## 3. Mostrar / ocultar HUD (`HudRegistry`)

`scripts/ui/HudRegistry.gd` es el registro central. Elementos que se pueden
ocultar: recursos y almacén, población/obreros/moral, botón del registro,
objetivo, indicador de la Tormenta, avisos emergentes, globos de ayuda (es el
mismo interruptor que AYUDA del menú ☰), texto de turno en batalla y las
herramientas Sandbox (solo existen en ese modo, docs/20). El menú ☰ y la pausa no
están en el registro: no se pueden ocultar.

La pestaña SANDBOX es también movible: su slot `sandbox_tab` la apila al pie de
la columna izquierda (tras el globo de los recursos, que va tras el registro),
así que baja sola cuando la Tormenta y el objetivo pasan a esa columna. Su
tarjeta de herramientas cuelga de ella y la sigue (a su derecha, a su izquierda
o debajo, siempre dentro de la pantalla). `tests/ui/test_modes_meet_interface.gd`
lo comprueba, junto con que el selector de "Nueva partida" (NewGameDialog) usa
los tokens vivos de paleta, contraste, texto y lado táctil, y que "Nueva
partida" de la pestaña Juego lo abre.

Ocultar no toca el `visible` del panel (que es suyo: la población se esconde
sola hasta la fase de asentamiento, la Tormenta en calma…). En modo `holder` el
control se mete en un `Control` contenedor y se oculta el contenedor; en modo
`visible` (piezas sueltas dentro de una columna) se usa `visible`. El apilado
ve el oculto como ausente y la columna se compacta.

### Registrar un elemento nuevo

1. Añádelo a `HudRegistry.ELEMENTS` y a `ORDER`: `{"label": "HUD_MI_COSA",
   "hideable": true, "movable": true, "mode": "holder"}`. Si es movible, su id
   es su `panel_id` de `UILayoutConfig.PANEL_SLOTS`.
2. En el panel, **después** de `add_child`:
   `HudRegistry.register("MiPanel", control)`.
3. `HUD_MI_COSA` en `Tr.gd`, ES y EN.

`tests/ui/test_hud_layout.gd` comprueba que todo id tiene nombre en los dos
idiomas y, si es movible, slot.

## 4. Paneles movibles (A9)

**Ajustes → Interfaz → EDITAR DISPOSICIÓN** cierra Ajustes (y la pausa o el menú
principal que lo prestaba, que vuelven al terminar) y abre `LayoutEditor`: un
marco sobre cada panel movible (recursos, población, objetivo, Tormenta,
avisos, registro, CONSTRUIR, panel de edificio) que se arrastra con el ratón o
con el dedo. Es un modo aparte a propósito: fuera de él un toque en el HUD es
un toque en el HUD y nada se mueve por accidente. Un velo se come los toques al
mapa. **LISTO** (o Esc) termina; **RESTABLECER DISPOSICIÓN** vuelve a la de serie.

- Cada arrastre se ajusta a una rejilla de 8 px y se pega al borde si queda a
  menos de 16 px (`UILayoutManager.snap_offset`), y nunca sale de la pantalla
  (`clamp_rect_to`). El recorte se aplica también al pintar, sin tocar lo
  guardado: en otra ventana el mismo desplazamiento puede volver a caber.
- Se guarda como desplazamiento sobre la posición del slot (el slot sigue
  siendo la posición de serie), en `GameConfig.ui_layout` con clave
  `"<perfil>|<proporción>"` (`DeviceProfile.layout_key`, proporciones
  `16:9`, `16:10`, `4:3`, `21:9`, `portrait`): mover el HUD en la tablet no lo
  mueve en el PC, ni lo de 16:9 se aplica a 4:3.
- Un panel movido deja su hueco en la columna: el que iba debajo sube. Los
  globos de ayuda (`follow_moved` en su slot) siguen al panel que explican.
- No se edita con un tablero de combate abierto.

## 5. Colores y contraste

Los colores de `UITheme` son **tokens** (`static var`), no constantes:
`UITheme.configure(paleta, alto_contraste, opacidad, tamaño_texto, lado_táctil)`
los reescribe y todo lo que pinta con `UITheme.POSITIVE / DANGER / WARNING /
INFO / RES_* / CAT_* / BRANCH_* / BOARD_* / FONT_*` sigue la preferencia sin
saberlo: bando aliado/enemigo del tablero, barras de vida (bueno → aviso →
malo), fases de la Tormenta, colores de recurso (también el texto flotante del
mundo, vía `GameConfig.resource_colors`), casillas de mover y objetivo.

| Paleta | Para | Aliado / bueno | Enemigo / malo | Aviso |
|---|---|---|---|---|
| Normal | — | verde militar | óxido | ámbar |
| Rojo-verde | deuteranopía y protanopía | azul (Okabe-Ito) | bermellón | amarillo |
| Azul-amarillo | tritanopía | turquesa | carmesí | rosa |

`tests/ui/test_ui_palettes.gd` simula cada deficiencia (matrices de Machado,
Oliveira y Fernandes 2009) y exige que aliado, enemigo y aviso queden separados
para quien la tiene, y más que con la paleta normal. Los iconos de recurso y de
fase ya tenían formas distintas: el color nunca es la única pista.

**Alto contraste**: fondos opacos y más oscuros, cajas lisas en vez de la placa
metálica ruidosa, bordes claros y más gruesos, velo más oscuro, texto
secundario tan claro como el principal y contraste mínimo 7:1 (AAA) en todo el
texto que pasa por `UITheme.readable`.

**Opacidad de paneles** (40–100 %): transparenta tarjetas del HUD y placas de
paneles, nunca los botones.

**Tamaño de texto**: pequeño 88 %, normal, grande 118 %, muy grande 136 % sobre
26/20/17/15 px (título/sección/cuerpo/pequeño), nunca por debajo de 11 px.

## 6. Textos de ayuda de dedo o de ratón

`Tr.ti(clave)` devuelve `CLAVE_TOUCH` si existe y el estilo de entrada es táctil
(`DeviceProfile.input_style`: perfil tablet/móvil, controles táctiles
encendidos o un toque real en esta sesión); si no, `Tr.t(clave)`. Lo usan los
globos de ayuda (cámara, zoom), la página de controles del tutorial, el consejo
de ruinas, los tooltips de colocar/rotar/pausa y el resumen de Controles.
Para una ayuda nueva que hable de ratón: escribe también `MI_CLAVE_TOUCH` (ES y
EN) y llama a `Tr.ti`. `test_device_profile.gd` falla si un texto `_TOUCH` dice
WASD, rueda, ratón o clic.

## 7. Disposición por tamaño de lienzo

- **< 1080 px de ancho** (tablet 4:3 con escala, 150 %…): la columna central
  (Tormenta y objetivo) baja a la columna izquierda
  (`UILayoutConfig.COLUMN_NARROW_WIDTH`, `COLUMN_SLOTS`), los avisos pasan al
  centro encima de CONSTRUIR (`COLUMN_NARROW_SLOTS`) y solo queda el globo del
  menú ☰. El indicador de la Tormenta, que normalmente gana a las ventanas
  (capa 16), se pone por debajo mientras hay una abierta.
- **< 720 px** (móvil en vertical): la disposición estrecha de siempre
  (`NARROW_SLOTS`), con un solo aviso a la vez.
- Máximo 3 avisos a la vez (el resto ya está en el registro).
- Los globos de ayuda se callan también bajo la pausa y el menú principal
  (`HelperPanel` mira `get_tree().paused` con un vigía que corre en pausa).

## 8. Herramientas y tests

- `tools/interfaz_probe.gd`: siembra una partida y hace capturas (HUD, menú ☰
  con un edificio, Ajustes pestañas Interfaz y Accesibilidad, editor, tablero)
  en `docs/media/dev/interfaz/` (ignorada por git). Argumentos:
  `--shot-size=WxH --view=2d --profile=tablet --scale=150 --text=large
  --palette=red_green --hc --opacity=0.6 --edited --only-hud --tag=x`.
  Siempre con un `override.cfg` temporal que apunte a otra carpeta de datos;
  aun así aparca guardado y ajustes.
- `tests/save/settings_parking.gd`: aparta `settings.cfg` (byte a byte) y el
  estado de interfaz de GameConfig mientras una suite toca preferencias.
- Suites: `tests/ui/test_device_profile.gd`, `test_ui_palettes.gd`,
  `test_hud_layout.gd`, `test_settings_tabs.gd`, y `test_touch_controls.gd`
  (actualizado: PC nunca enciende los controles en "Automático").
- Tacto: ver §9.

## 9. Tacto (dedo)

Lo que hace que una tablet se juegue con el dedo, y dónde vive. Diagnóstico de
partida: `tormenta-imperial-contexto/07_DIAGNOSTICO_JUGABILIDAD.md` (bugs 5, 7,
8, 10 y 13).

### El mapa se arrastra casi en cualquier sitio

- El GUI entrega un `InputEventScreenTouch` a **cualquier** `Control` que no sea
  `MOUSE_FILTER_IGNORE` bajo el dedo, y lo da por manejado; un `Container` vale
  `PASS` por defecto y un `Control` pelado `STOP`. Además `InputService`
  descarta el toque si hay un control "hovered". Regla: **solo los botones,
  deslizadores y paneles de verdad paran el dedo**; todo contenedor o hueco que
  quede encima del mapa va en `IGNORE`.
- `OnScreenControls`: la fila inferior, la columna derecha, la cruceta, su
  centro vacío y las filas de giro y zoom en `IGNORE`. El aviso de colocación
  rechazada (`BuildingPlacer._show_feedback`) también.
- Medido a 1280x800 con el perfil tablet (sonda con ventana, mapas en
  `tormenta-imperial-contexto/diagnostico/fx*_blockmap*_overlay.png`), en % de
  la pantalla entera que llega al mapa:

  | | Reposo | Colocando |
  |---|---|---|
  | Antes (E1 / IB) | 73,6 % / 71,4 % | 56,2 % / 53,2 % |
  | 3D ahora | 89,3 % | 87,8 % |
  | 2D ahora | 90,3 % | 85,5 % (con la tarjeta de población ya abierta) |

  Lo que falta son botones de verdad (cruceta, zoom, R, CANCELAR, II, ☰, GUÍA),
  la barra de recursos y la tarjeta de población. `tests/ui/test_touch_passthrough.gd` repite
  el barrido en headless y exige el 90 % de los puntos que no caen sobre un
  control de verdad (da el 100 %).

### Toque o arrastre: el umbral en dp

`GameConfig.touch_drag_threshold_dp` (14 dp, unos 2,2 mm) pasado a píxeles del
lienzo con el dpi real y la escala (`InputService.touch_slop_px()`), sin bajar de
`touch_drag_threshold_px` (8). Los 12 px físicos de antes eran 1,1 mm en una
tablet de 280 dpi y un toque normal se volvía arrastre. El paneo no pierde nada
por esperar: arranca desde donde se apoyó el dedo.

### Construir con el dedo (`PlacementAssist`)

Común a `BuildingPlacer` (3D) y `BuildingPlacer2D`; cada colocador responde a
los métodos `assist_*`. Con ratón nada cambia: el fantasma sigue al cursor y el
clic planta. Con el dedo:

| Gesto | Qué hace |
|---|---|
| Tocar el mapa | Lleva el fantasma bajo el dedo (centrado), verde o rojo. Si es rojo, dice por qué en el acto (bosque, ocupado, fuera del mapa). En la franja verde de un extractor, se ajusta al hueco válido que cubre el dedo |
| Tocar el fantasma | Lo planta (mismo veredicto y cobro que el clic) |
| **✓ CONSTRUIR AQUÍ** | El botón que flota sobre el fantasma; lo planta. Solo sale si el sitio vale |
| Apoyar en el fantasma y arrastrar | Lo mueve con el dedo; no panea |
| Arrastrar en otro sitio | Mueve el mapa, como siempre |
| Dos dedos | Pellizco o giro; el fantasma se queda donde está |

**Por qué apuntar y confirmar** y no "planta al levantar el dedo": en tactil no
hay hover, así que sin este paso el jugador paga antes de ver si el sitio vale.
Con el fantasma verde y ✓ delante, el primer aserradero sale al segundo toque.
Para construir en serie (calzadas) basta tocar la casilla siguiente y el
fantasma. El clic emulado que Godot fabrica al levantar el dedo se ignora
mientras se coloca, y el dedo que pulsa ✓ no mueve después el fantasma.

El fantasma lo apunta el dedo (`touch_aim`) desde que empieza la colocación si
el perfil es táctil o ya llegó un toque; un movimiento de ratón de verdad
devuelve el mando al cursor.

**La regla del yacimiento se ve antes de colocar:**

- La ficha de `ConstructionMenu` dice "▲ Necesita bosque adyacente" (o la veta,
  el hierro, el pozo): `PlacementAssist.rule_text(id)`, claves `LBL_RULE_*`.
- Al colocar un extractor se pintan en verde pálido las casillas donde cabe
  (`PlacementAssist.valid_spots`, el mismo `PlacementRules.evaluate_placement`
  del clic). En tactil el fantasma sale ya en la más cercana al centro de la
  pantalla, y si no hay ninguna a la vista la cámara va a ella.
- Empezar a colocar cierra la columna ☰.

### Mantener pulsado repite

Todos los botones de `OnScreenControls` disparan al tocar
(`ACTION_MODE_BUTTON_PRESS`). Mantenidos más de `hold_repeat_delay_sec` (0,3 s):
la cruceta panea cada frame, zoom y giro siguen de forma continua
(`HOLD_ZOOM_PER_SEC`, `hold_rotate_degrees_per_sec` = 90°/s tras el paso de 45°),
R un cuarto de vuelta cada 0,45 s. CANCELAR no repite.

### Controles semitransparentes

`GameConfig.ui_touch_controls_opacity` (0,45 de serie, 15–100 %), en
`settings.cfg [ui] touch_controls_opacity`. Se aplica a cada botón entero
(fondo, borde y símbolo); el que se pulsa se ve al 100 % y vuelve en 0,2 s al
soltar. Ajustes → Controles → "Opacidad de los controles", al momento. En PC los
controles siguen sin salir por defecto.

### Girar con dos dedos (3D)

`InputService` sigue los dos dedos, mide la separación y el ángulo de la línea
que los une, y bloquea el gesto en lo primero que pase su umbral
(`twist_lock_degrees` = 8° de giro antes que `pinch_lock_scale` = 8 % de
separación → giro; al revés → zoom; `decide_two_finger_lock`, pura). El giro va
1:1 por `camera_rotate_step_requested`: el terreno gira con los dedos. Levantar
un dedo reinicia el bloqueo. En 2D no hay giro (docs/18) y un giro tampoco da
zoom.

### Tests y sonda

`tests/input/test_twist_gesture.gd`, `tests/ui/test_touch_hold_opacity.gd`,
`tests/ui/test_touch_passthrough.gd`, `tests/ui/test_touch_placement.gd` (3D y
2D). La sonda con ventana del diagnóstico
(`tormenta-imperial-contexto/diagnostico/_sonda/Probe.gd`) sirve para el mapa de
bloqueo y el recorrido completo con toques sintéticos; siempre con un
`override.cfg` que apunte a otra carpeta de datos.

## 10. Huecos conocidos

- Cambiar texto, paleta, contraste u opacidad recarga la escena: no hay
  repintado en caliente de los paneles ya construidos.
- `TUT_PLAY_1_BODY_TOUCH` es una copia de `TUT_PLAY_1_BODY` con la última frase
  cambiada: si alguien reescribe la página del tutorial, tiene que tocar las dos.
- Con la escala por encima de lo que cabe, el selector sigue diciendo el valor
  pedido (150 %) aunque se aplique el máximo (133 % a 1280x720).
- Los avisos (capa 19) se dibujan encima de Ajustes y de los globos: es a
  propósito (tienen que verse sobre el tablero), pero tapan unos segundos.
- Los controles en pantalla (D-pad, zoom) no son movibles: son una sola capa a
  pantalla completa (sus contenedores no paran el dedo, §9).
- Si el fantasma sale de la pantalla, el botón ✓ se queda abajo al centro en
  vez de flotar sobre él.
- La barra de recursos (ResourceHUD) es un panel STOP de ~280x100: es de verdad,
  pero tapa el mapa en la esquina.
