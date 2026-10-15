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

"Automático" en *Controles en pantalla* es **solo móvil y tablet** (decisión de
Bryan, 2026-10-04): sigue al perfil, y en un PC no se enciende ni porque la pantalla
se declare táctil ni porque llegue un toque real; un portátil táctil tocado una vez
no se llena de flechas. El portátil táctil elige **Siempre** a mano (o el perfil
Tablet), y Ajustes lo dice debajo del selector (`LBL_TOUCH_AUTO_HINT`). Un toque real
sí cambia los textos de ayuda a dedo (`input_style`) y la colocación táctil (§9):
eso no son los controles en pantalla.

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
| **Audio** | Volumen general, música sí/no (también en ☰ MENÚ → PARTIDA), música, efectos. De serie bajos: general 80 %, música 35 %, efectos 50 % (`GameConfig.AUDIO_DEFAULTS`), con curva perceptual |
| **Interfaz** | Perfil de dispositivo, escala, tamaño de texto · Vista 3D/2D, rejilla, pantalla completa · Elementos en pantalla (un interruptor por elemento) · Editar / Restablecer disposición |
| **Controles** | Controles en pantalla (Automático / Siempre / Nunca), su opacidad (20–100 %, de serie 55 %, `GameConfig.ui_touch_controls_opacity`) y el resumen de controles en ratón o en dedo |
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
ocultar: recursos y almacén (con obreros y moral, que van en esa fila), botón del registro,
indicador de la Tormenta, avisos emergentes, globos de ayuda (es el
mismo interruptor que AYUDA del menú ☰), texto de turno en batalla y las
herramientas Sandbox (solo existen en ese modo, docs/20) y el botón de velocidad
x1 / x2 (§13). El botón ☰ MENÚ (el
menú único, que sustituye al ☰ y a la pausa II) no está en el registro: no se
puede ocultar.

La pestaña SANDBOX es también movible: su slot `sandbox_tab` la apila al pie de
la columna izquierda (tras el globo de los recursos, que va tras el registro),
así que baja sola cuando la Tormenta pasa a esa columna. Su
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
marco sobre cada panel movible (recursos, Tormenta,
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

Todos salen de una paleta de diez colores con nombre: ver
[24-paleta.md](24-paleta.md). Las paletas para daltonismo y el alto contraste
solo cambian colores de esa paleta; el resto se deriva.

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

El tutorial guiado y las ayudas ([23-onboarding.md](23-onboarding.md)) van
igual: cada paso del tutorial ("Toca CONSTRUIR" / "Haz clic en CONSTRUIR"), cada
globo y el índice de AYUDA leen con `Tr.ti`. El prólogo dice "Desliza el dedo
para pasar folio" en tablet y "← → o Intro" en PC. El interruptor "Globos de
ayuda" de Interfaz (`HelperPanel.callouts`) es ahora el de las ayudas que salen
solas: apagado, el índice de AYUDA sigue reabriendo la que se pida.

### Menos texto (2026-10-04, rama `feat/menos-texto`)

Reglas para los paneles y overlays (todos menos el HUD de recursos y la tarjeta de
estado de población, que lleva su propia rama):

- **Icono + cifra antes que frase.** Los costes son una fila de iconos con su
  cifra y en rojo solo lo que falta: `TextKit.cost_row()` (o `cost_inline()` dentro
  de otra fila). Un material sin icono se escribe con su nombre. Nada de "Costo:",
  "Produce:", "Duración:" delante.
- **Tiempos cortos**: `TextKit.short_time()` → `45 s`, `1:30`, `2 h`.
- **Un verbo por botón** (CONSTRUIR, MEJORAR → Nv 2, MOVER, ENTRENAR).
- **El motivo de "no se puede" en ≤ 6 palabras** junto al botón
  (`PlacementRules.block_reasons_short`); el motivo entero, en su tooltip.
- **Las explicaciones al tooltip**: descripción del edificio (título), regla de la
  carretera, qué hace MOVER, por qué retirar trabajadores, tasa de cancelación, de
  dónde salen los topes del ejército, la intro y las ramas del árbol tecnológico, el
  lore de cada tecnología, la frase de cada grupo del menú. En táctil el tooltip se lee
  **manteniendo pulsado** (§9, `TouchTooltip`, desde 2026-10-05), y aun así lo que
  importa tiene que estar también a la vista o en la ayuda: el lore y la frase de rama
  del árbol tecnológico salen en la ficha de la tecnología elegida. Lo que el jugador
  necesita para decidir (coste, motivo de bloqueo, producción, tiempo) no se mueve.
- **Nada repetido**: ni el nombre del recurso junto a su icono, ni "Modo: Campaña"
  en cada pausa, ni una línea del parte que diga lo mismo que su título.
- **Medir**: `tools/texto_probe.gd` fotografía cada panel y overlay
  (`-- --profile=pc|tablet --prefix=antes|despues`, con `override.cfg` propio).
  Las suites `tests/ui/test_menos_texto_*.gd` fijan que los datos clave siguen a la
  vista y los topes de palabras; `test_tr_en_parity.gd`, que toda clave tiene ES y EN
  con los mismos huecos de formato.

## 7. Disposición por tamaño de lienzo

- **< 1080 px de ancho** (tablet 4:3 con escala, 150 %…): la columna central
  (la Tormenta) baja a la columna izquierda
  (`UILayoutConfig.COLUMN_NARROW_WIDTH`, `COLUMN_SLOTS`), los avisos pasan al
  centro encima de CONSTRUIR (`COLUMN_NARROW_SLOTS`) y solo queda el globo del
  menú ☰. El indicador de la Tormenta, que normalmente gana a las ventanas
  (capa 16), se pone por debajo mientras hay una abierta.
- **< 720 px** (móvil en vertical): la disposición estrecha de siempre
  (`NARROW_SLOTS`), con un solo aviso a la vez.
- Máximo 3 avisos a la vez (el resto ya está en el registro).
- Los globos de ayuda se callan también bajo la pausa y el menú principal
  (`HelperPanel` mira `get_tree().paused` con un vigía que corre en pausa).

## 8. Menú único, Ajustes que responden y volumen

- **Un solo menú** (`PauseMenu`, docs/08): el botón "☰ MENÚ" arriba a la
  derecha sustituye a la pausa II (arriba a la izquierda) y al ☰ desplegable.
  Abre una tarjeta con COLONIA y PARTIDA y pausa. Siempre abre: cierra antes las
  ventanas y suelta el edificio en la mano. ESC y el botón atrás de Android
  (`quit_on_go_back=false`) hacen lo mismo. Sin botón de pausa junto a los
  recursos, la columna izquierda ya no le reserva sitio (`PAUSE_RESERVE = 0`).
- **CONSTRUIR** es siempre visible, grande y abajo en el centro.
- **Ajustes prestados** (desde el menú principal o el menú de la partida) van
  en una capa por encima de todo (`LAYER + 1`) mientras están abiertos y
  procesan en pausa. Ajustes guarda al cerrarse.
- **Volumen**: `AudioManager.slider_to_db(v) = linear_to_db(v * v)` en los
  cuatro buses, y cada efecto con su ganancia fija (`SFX_GAIN_DB`, por nombre
  de fichero: `era_up` −11 dB, `ui_click` −10 dB, el resto −6 a −8 dB).
- **HUD sin texto fijo** (2026-10, sustituye al "HUD con palabras"): una fila
  de `[icono] número` (recursos, obreros libres y, con la Tormenta armada, la
  moral) y la barra del almacén con `500/600`. Las palabras están en el tooltip
  de cada ficha y, con el dedo, en el detalle que despliega un toque (nombres,
  leyenda de colores de la barra, obreros, moral). La tarjeta de estado
  (Trabajadores / En su puesto / Moral) ya no existe. El Zzz sigue con su
  motivo. Detalle en docs/08 (ResourceHUD).
- **Sonda**: `tools/menu_probe.gd` captura título, Ajustes sobre el título, el
  HUD en era 1 y 3, el menú y cada pestaña de Ajustes, y el tablero, en
  `docs/media/dev/menu/`.

### Herramientas y tests (§1-§8)

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
  ("Automático" sigue al perfil: en PC no enciende los controles aunque llegue un
  toque, tampoco en un portátil táctil; "Siempre" y "Nunca" fuerzan; Ajustes
  muestra la nota para el portátil táctil).
- Tacto: ver §9.

## 9. Tacto (dedo)

Lo que hace que una tablet se juegue con el dedo, y dónde vive. Parte de un
diagnóstico de jugabilidad en tableta (bugs 5, 7, 8, 10 y 13), que no está en el
repositorio.

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
- Medido a 1280x800 con el perfil tablet (sonda con ventana y mapas de bloqueo,
  fuera del repositorio), en % de la pantalla entera que llega al mapa:

  | | Reposo | Colocando |
  |---|---|---|
  | Antes (E1 / IB) | 73,6 % / 71,4 % | 56,2 % / 53,2 % |
  | 3D ahora | 89,3 % | 87,8 % |
  | 2D ahora | 90,3 % | 85,5 % (con la tarjeta de población ya abierta) |

  Lo que falta son botones de verdad (cruceta, zoom, R, CANCELAR, ☰ MENÚ, CONSTRUIR, GUÍA),
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

- La ficha de `ConstructionMenu` dice "▲ El aserradero debe tocar un bosque (al
  lado o en diagonal)" (o la veta, el hierro, el pozo):
  `PlacementAssist.rule_text(id)`. Es la misma clave `message` de
  `GameConfig.building_deposit_rules` que usa el aviso al fallar
  (`LBL_NEEDS_*_NEAR`, `LBL_REQUIRES_DEPOSIT`), con ratón o en táctil: una sola
  redacción en todas partes.
- Al colocar un extractor se pintan en verde pálido las casillas donde cabe
  (`PlacementAssist.valid_spots`, el mismo `PlacementRules.evaluate_placement`
  del clic). En tactil el fantasma sale ya en la más cercana al centro de la
  pantalla, y si no hay ninguna a la vista la cámara va a ella.
- Empezar a colocar cierra el ☰ MENÚ si estaba abierto.

### Mantener pulsado repite

Todos los botones de `OnScreenControls` disparan al tocar
(`ACTION_MODE_BUTTON_PRESS`). Mantenidos más de `hold_repeat_delay_sec` (0,3 s):
la cruceta panea cada frame, zoom y giro siguen de forma continua
(`HOLD_ZOOM_PER_SEC`, `hold_rotate_degrees_per_sec` = 90°/s tras el paso de 45°),
R un cuarto de vuelta cada 0,45 s. CANCELAR no repite.

### Mantener pulsado para leer (`TouchTooltip`)

Decisión de Bryan (2026-10-05): con el dedo, los tooltips se leen manteniendo
pulsado. `scripts/ui/TouchTooltip.gd` es una `CanvasLayer` (capa 50) hija de
`InputService`: sobrevive a las recargas de escena y corre en pausa
(`PROCESS_MODE_ALWAYS`, el ☰ MENÚ pausa el árbol). Mira la entrada en `_input`, antes
que la interfaz:

| Gesto | Qué pasa |
|---|---|
| Toque corto | Pulsa como siempre. El gesto ni se entera |
| Dedo quieto `GameConfig.touch_tooltip_hold_sec` (0,5 s) sobre un control con tooltip | Burbuja con el texto encima del dedo; el botón **no** se pulsa |
| Levantar el dedo | Cierra la burbuja. El soltar no llega al botón |
| Mover el dedo más que `InputService.touch_slop_px()` | Cancela: es un arrastre (mapa o lista) |
| Segundo dedo | Cancela o cierra: pellizco, giro o tocar fuera |
| Botones que actúan al tocar (`ACTION_MODE_BUTTON_PRESS`) | No se leen: la cruceta, el zoom y el giro repiten al mantener (abajo) |

- **Qué control.** `TouchTooltip.control_at()` busca el `Control` bajo el dedo como la
  interfaz: la capa más alta, el último hijo, visible, que no sea `IGNORE` y que no
  esté recortado por un `ScrollContainer`. Si no tiene tooltip, el primer padre que lo
  tenga (`tooltip_owner`), igual que el tooltip del ratón. Un fondo `STOP` (el de un
  modal) tapa lo de debajo: sin burbuja.
- **Sin pulsar.** Al salir la burbuja, el botón recibe un "soltar" lejos de todo
  control (el mismo truco que `DragScroll`): no se dispara y no se queda hundido. El
  soltar del ratón emulado al levantar el dedo se come.
- **Con DragScroll.** Arrastrar una lista manda ese soltar-lejos: el gesto lo ve y se
  cancela, aunque `DragScroll` se quede los movimientos.
- **La burbuja.** Estilo `UITheme.make_hud_card_style`, texto "body" (sigue el tamaño
  de texto de Ajustes), 360 px de ancho máximo con ajuste de línea, centrada sobre el
  dedo y 56 px por encima (debajo si no cabe), nunca fuera de la pantalla
  (`bubble_position`, pura).
- **Solo táctil.** Activo cuando `DeviceProfile.input_style()` es `touch` (tablet,
  móvil, controles táctiles forzados o un toque real en esta sesión). Con ratón no
  llega ningún toque, así que en PC siguen los tooltips de Godot.
- **El mapa.** Los edificios y yacimientos del mapa no son `Control` y no tienen
  tooltip (su información está en BuildingInfoPanel): mantener pulsado sobre el mapa
  no enseña nada. Sí funciona sobre todo el HUD (fichas de recursos, Tormenta,
  menú…).
- **Ayuda.** La guía rápida acaba con una línea, y AYUDA tiene la entrada "Leer qué es
  cada cosa" (`guide_read`), con `Tr.ti("QG_READ_HINT")`: "Mantén pulsado un botón o
  un icono para leer qué es" con el dedo, "Pasa el ratón por encima…" con ratón.

### Controles semitransparentes

`GameConfig.ui_touch_controls_opacity` (0,45 de serie, 15–100 %), en
`settings.cfg [ui] touch_controls_opacity` (la clave vieja `touch_opacity` del
menú único se lee si no hay otra y se borra al guardar: hay un solo ajuste). Se aplica a cada botón entero
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

`tests/input/test_twist_gesture.gd`, `tests/input/test_touch_tooltip.gd` (toque corto
pulsa, largo enseña y no pulsa, moverse o un segundo dedo cancelan, en PC no hace
nada), `tests/ui/test_touch_hold_opacity.gd`,
`tests/ui/test_touch_passthrough.gd`, `tests/ui/test_touch_placement.gd` (3D y
2D). La sonda con ventana del diagnóstico (fuera del repositorio) sirvió para el mapa
de bloqueo y el recorrido completo con toques sintéticos; en el repositorio, los
flujos de `qa/maestro/` recorren lo mismo en el emulador de tableta. Siempre con un
`override.cfg` que apunte a otra carpeta de datos.

## 10. Tope de fotogramas

Sin tope propio, Godot repinta la escena entera tan rápido como deja el vsync: 144
veces por segundo en un monitor de 144 Hz, 90 o 120 en un Android de pantalla
rápida, también con el juego en pausa o la ventana detrás de otra. En un juego de
gestión eso no se ve, pero se paga en batería, calor y ventilador. El ejecutable
exportado hace lo mismo, así que el tope vive en el juego.

Ajustes → Interfaz → Vista → **Fotogramas por segundo** (`FpsRow`, debajo de
pantalla completa): "Del perfil (N)", 30, 45, 60, 90, 120 o "Sin tope". Se aplica
al momento con `Engine.max_fps` (no reconstruye la interfaz) y se guarda en
`settings.cfg` como `[interfaz] fps_cap` (`GameConfig.ui_fps_cap`: `"auto"`, un
número como texto o `"unlimited"`; un valor desconocido carga como `"auto"`). El
vsync sigue como está.

| Perfil | "Del perfil" | Por qué |
|---|---|---|
| PC | 60 | Por encima no aporta nada en un juego de gestión |
| Tablet | 30 | Batería y calor: las tablets baratas bajan el reloj al calentarse y entonces tironean |
| Móvil | 30 | Igual, y en pantalla pequeña 30 estables se ven bien |

Además del elegido, el juego baja solo:

- **En pausa** (`get_tree().paused`: menú de pausa, menú de título, prólogo) a
  `GameConfig.fps_paused` = 30. La pausa no tiene señal; `DeviceProfile` corre con
  `PROCESS_MODE_ALWAYS` y mira el booleano en `_process`.
- **Sin foco** (otra ventana delante, minimizada, la app en segundo plano;
  `NOTIFICATION_APPLICATION_FOCUS_OUT/IN`) a `GameConfig.fps_background` = 10.
- Nunca por encima de lo elegido: con 30 elegido la pausa se queda en 30. "Sin
  tope" también baja en pausa y sin foco.

La cuenta es pura: `DeviceProfile.fps_for(mode, profile_fps, focused, paused)`
(0 = sin tope); `effective_fps_cap()` la hace con el estado de ahora y
`apply_fps()` la aplica (al arrancar, al cambiar de perfil, al restablecer
Interfaz, al pausar y al perder o recuperar el foco). Valores por perfil en
`DeviceProfile.DEFAULTS["fps"]`. Diseño y medidas: `docs/26-rendimiento.md` §7.4.

- **Headless no se toca**: `apply_fps()` no hace nada con
  `DisplayServer.get_name() == "headless"`, así que los tests y las sondas sin
  ventana corren sin tope.
- **Sondas con ventana que miden "sin tope"** (`life_probe_runner`, y las de
  rendimiento y arte de otras ramas) ponen `Engine.max_fps = 0` ellas mismas, pero
  `DeviceProfile` lo vuelve a aplicar en cuanto cambia la pausa o el foco. Una
  sonda que quiera medir sin tope de verdad pone antes
  `GameConfig.ui_fps_cap = "unlimited"` (sin guardar) y no pierde el foco, o
  ajusta `fps_paused` / `fps_background`.

Tests: `tests/ui/test_device_profile.gd` (la cuenta por perfil, números, sin
tope, pausa, foco, carga y guardado) y `tests/ui/test_settings_tabs.gd` (la fila
y Restablecer).

## 11. Huecos conocidos

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
- La barra de recursos (ResourceHUD) es un panel STOP: es de verdad, pero tapa
  el mapa en la esquina (ahora ~350x75 en PC con seis fichas, más bajo que la
  barra y la tarjeta de estado de antes juntas).
- Tooltips con el dedo: se leen manteniendo pulsado (§9). Los objetos del mapa
  (edificios, yacimientos) no tienen tooltip que leer: mantener pulsado sobre el
  mapa no enseña nada.
- En tablet 16:10 (lienzo ~1113 px) con los cuatro recursos y la moral a la
  vista, la fila de recursos pasa del borde que deja libre la columna central y
  la Tormenta baja a la columna izquierda (`is_column_narrow()`,
  el mismo mecanismo que ya existía con LIMPIAR o letra grande). Con oro,
  madera y obreros (eras 1-2) no pasa.
- Un `settings.cfg` que nombre un elemento retirado (la tarjeta de estado
  `NotificationPanel.status` o la franja de objetivo `NotificationPanel.objective`,
  ocultos o movidos) carga sin él: `GameConfig.load_user_settings()` lo quita
  (`HudRegistry.RETIRED`).
- `UILayoutConfig.CENTER_COLUMN_HALF_WIDTH` sigue en 220 (se midió con la franja de
  objetivo, de 440 px): la Tormenta (380) cabe con margen y así no se mueven los
  umbrales de las tablets.

## 12. Luz y ambiente del mapa 3D (aire de maqueta)

> Número fijo: el código lo cita como "docs/21 §12" desde la rama de arte. El §11
> queda libre.

Dirección de arte (2026-10-05): diorama de juguete. Colores cálidos y saturados,
luz suave y sombras marcadas que anclan cada pieza al suelo. Esta sección cubre
lo que no es edificio: cielo, sol, isla, agua, el día y la noche, y lo que les
hace la Tormenta.
Los edificios, las parcelas y su paleta están en docs/03 ("Modelos: maqueta de
juguete", `scripts/buildings/ToyPalette.gd`).

### Quién hace qué

| Pieza | Archivo | Qué decide |
|---|---|---|
| Cielo, sol, tonemapping | `scenes/main/Main.tscn` (`WorldEnvironment`, `DirectionalLight`) | Los colores **limpios**: cielo procedural cálido, luz ambiental del cielo (70 %), sol cálido a 1,35, ACES, contraste 1,06 y saturación 1,2 |
| Lo que cuesta GPU | `scripts/map/WorldLook.gd` (script del `WorldEnvironment`) | SSAO, glow, cortes de sombra, radiancia, isla sencilla, escala 3D. Nunca toca colores ni energías |
| La hora del día | `scripts/storm/DayCycle.gd` (modelo puro) + `scripts/services/DayClock.gd` (autoload) | El reloj: amanecer, día, atardecer, noche; la hora viaja en el save |
| La Tormenta y el día | `scripts/map/StormSky.gd` (autoload) | Guarda los valores limpios (los del mediodía), pinta los del momento del día y oscurece por fase encima: cielo, niebla, sol, luz ambiental, **la isla** y las ventanas |
| La isla | `scripts/map/IslandGenerator.gd` + cinco shaders | Cesped (`grass_ground`), canto (`island_cliff`), playa (`island_sand`), espuma (`island_foam`), agua (`water_border`). Sin texturas: todo en coordenadas de mundo |
| Lo común de los shaders | `scripts/map/storm_grade.gdshaderinc` | Los uniforms `storm_weight` (0-1), `night_weight` (0-1) y `simple` (bool), y la función `storm_grade()` |

La isla 2D (`scripts/view2d/Island2D.gd`) usa la misma geometría y la misma
paleta cálida, pero no pasa por nada de esto: se tiñe con `StormTint2D` (día,
noche y Tormenta en un solo `CanvasModulate`).

### La isla de maqueta

- **Cesped** en y = 0 (la rejilla, el ratón y los edificios cuentan con ello):
  tres verdes, zonas secas, calvas de tierra, grano de matas y flores sueltas.
  Las octavas del ruido van giradas y el dominio se dobla con dos ruidos lentos:
  sin eso las manchas salían cuadradas, alineadas con las calles.
- **Canto**: una pared de y = 0 a y = −0,6 por todo el borde, con un labio verde
  arriba y tierra con vetas (la `WOOD` de ToyPalette oscurecida).
- **Playa**: un anillo que baja de −0,28 a −0,9; arena entre `CREAM` y `BRASS`,
  mojada donde la corta el agua, y una franja oscura al pie del canto que hace de
  **sombra de contacto** (ancla la placa de cesped sin SSAO, que Mobile no tiene).
- **Agua** a y = −0,5: el `SKY` de ToyPalette, hondo lejos y turquesa junto a la
  costa (distancia a un rectángulo redondeado ajustado a la isla). Ondas de
  senos, sin ruido: el ruido de valor derivado dejaba un mosaico de rombos.
- **Espuma**: cinta `unshaded` que sigue la costa exacta, con una franja fija
  pegada a la arena (legible desde lejos) y líneas que salen hacia el mar.
- Todo se rehace en `grid_resized` (la rejilla cambia por partida).

### Calidades (`WorldLook.settings_for`)

El jugador elige en Ajustes → Interfaz: `auto`, `high`, `low`
(`GameConfig.ui_graphics_quality`, en `settings.cfg`). `auto` es alta solo con
Forward+; con Mobile o Compatibility es baja. `minimal` existe en WorldLook pero
aún **no tiene entrada en Ajustes** (2026-10-12): se activa poniendo
`GameConfig.ui_graphics_quality = "minimal"` y emitiendo
`graphics_quality_changed` (lo hace `tools/arte_probe_runner.gd`).

| | Alta | Baja | Mínima |
|---|---|---|---|
| SSAO | solo Forward+ | no | no |
| Glow | Forward+ y Mobile | no | no |
| Sombras del sol | 4 cortes (Forward+), 2 (Mobile) | 1 corte (ortogonal) | **apagadas** |
| Radiancia del cielo | 64 | 32 | 32 |
| Isla | completa | sencilla | sencilla |
| `scaling_3d_scale` | 1,0 | 1,0 | **0,7** (la UI no se escala) |

- **Isla sencilla** (uniform `simple`): agua lisa (solo el degradado, sin ondas
  ni crestas), espuma con la franja fija y sin líneas, cesped sin sombra, zonas
  secas, matas ni doblado de dominio, arena sin grano ni guijarros. El valor es
  el mismo para todo el material, así que la rama no cuesta. WorldLook lo pinta
  en los materiales al cambiar de calidad, e IslandGenerator lo lee
  (`WorldLook.island_simple()`) al crearlos.
- **Distancia de sombra**: sigue al zoom de la cámara
  (`shadow_distance_for`: distancia × 1,6 + 18, entre 30 y 200), para que de
  cerca la sombra use toda su resolución. Sin sombras no se calcula.
- El SSAO está apagado en `Main.tscn` y lo enciende WorldLook: así Mobile no
  avisa al cargar la escena.
- Shaders "para una papa": sin bucles (las tres octavas del cesped van escritas a
  mano), sin texturas ni muestreos, nada recalculado por frame en GDScript.

### Por renderizador

- **Forward+** (PC): todo lo de la tabla.
- **Mobile** (APK Android): sin SSAO (no existe); glow y dos cortes de sombra
  solo si el jugador fuerza alta. Con `auto` va en baja.
- **Compatibility** (APK de QA del emulador): sin SSAO ni glow; con `auto`, baja.

### Lo que oscurece la Tormenta (`StormSky`)

Un peso por fase: Aviso 0,35, Ceniza 0,7, Tormenta entre 0,6 y 1 según la
severidad (solo ahora se ve la severidad: el Aviso no adelanta la factura).
Funde en 3 s al cerrarse y en 5 s al abrirse; ganada la Auditoría Final aclara
de golpe y para siempre.

- **Cielo**: color de fondo, los cuatro colores del `ProceduralSkyMaterial`
  hacia ceniza, luz ambiental hacia ceniza clara y al 30 % de energía, sol al
  15 %, niebla de ceniza hasta 0,014.
- **Isla, agua y espuma**: el mismo peso, con el mismo fundido (un
  `tween_method` sobre el uniform `storm_weight` de los cinco materiales).
  `storm_grade()` desatura y enfría hacia la pizarra (`SLATE`) y baja el valor;
  el agua además pierde brillo (más rugosa). La espuma no tiene luz, así que
  aquí se apaga a mano y pierde opacidad: sin esto era lo único blanco bajo la
  ceniza.
- **Cargar o empezar partida** (`game_load_completed`, `game_new_started`):
  `sync_to_storm()` pinta al instante la fase en que está la Tormenta, sin
  fundido; en calma vuelve todo limpio. Los valores limpios se guardan una vez
  por `Environment` (el de `Main.tscn` es un sub-recurso que puede sobrevivir a la
  recarga con la ceniza puesta).
- **Isla rehecha** (`grid_resized`, recarga): el peso vive en el autoload
  (`StormSky.get_island_weight()`); IslandGenerator lo pone en los materiales al
  crearlos, así que no nace limpia a media tormenta. Sin cielo (vista 2D) el
  peso se guarda igual.
- **Coste**: solo se tocan uniforms y propiedades del entorno durante los
  fundidos (3-5 s por fase); nada de materiales ni mallas nuevas.

### Día y noche (2026-10-12)

Solo visual, preparado para reglas. El público tiene 10-15 años: la noche es
azulada y más baja de luz, **nunca oscura de verdad**.

- **Modelo puro** `scripts/storm/DayCycle.gd` (como `StormCycle`): sin nodos, sin
  señales, sin azar. `tick(delta)` devuelve eventos `day_phase_changed`. La hora va
  de 0 a 1 y empieza al rayar el alba; fases `DAWN`, `DAY`, `DUSK`, `NIGHT`.
  Consultas: `is_night()`, `light_weight()` (1 de día, 0 de noche, curva suave en
  alba y ocaso), `warm_weight()` (el naranja del sol bajo, un arco dentro del alba y
  del ocaso), `sun_arc()` (−1 este, 0 mediodía, 1 oeste; de noche la luna lo
  recorre al revés, así la dirección de la luz nunca salta).
- **Duración** (`GameConfig.day_cycle_*`): amanecer 90 s, día 600 s, atardecer
  90 s, noche 180 s = **16 min** por vuelta. En dev_mode se comprime como todo.
  `day_cycle_enabled = false` = siempre de día pleno (la luz de `Main.tscn`).
- **Servicio**: `DayClock`, autoload propio (antes de StormSky). No vive en
  StormSky porque la hora es estado de partida (save + `reset()` desde los tres
  sitios de GameManager) y el `reset()` de StormSky no se puede llamar al empezar
  partida (olvidaría los valores limpios del Environment). Se para con la pausa
  real. Emite `day_phase_changed(phase, hour)` al entrar en cada fase. Una regla
  futura pregunta `DayClock.is_night()` o `light_weight()`.
- **3D (StormSky)**: los valores limpios de `Main.tscn` son los del **mediodía**.
  Cada `day_cycle_refresh` segundos (2) y al cambiar de fase se calculan los del
  momento (`_day`): sol, color del sol, luz ambiental, fondo y los cuatro colores
  del cielo procedural. Alba y ocaso: sol y cielo hacia naranja (`SUN_WARM`,
  `SKY_WARM`), el sol más bajo y girado (`SUN_DIP`, `SUN_SWEEP`, nunca bajo
  `MIN_ELEVATION`: la maqueta se sigue leyendo). Noche: luna azulada al 50 % de
  energía, luz ambiental azul a energía plena, cielo azul pizarra (`SKY_NIGHT`). Los
  colores de la noche entran con n² (en mitad del ocaso manda el naranja).
- **La Tormenta manda sobre la noche**: se mezcla *encima* del momento del día
  hacia los mismos objetivos de ceniza que de día (calculados sobre los valores
  limpios). Con la Tormenta en pleno da igual la hora, y la noche con Tormenta
  nunca queda más oscura que la Tormenta de día. Los fundidos de 3-5 s son un solo
  `tween_method` que relee `_day` en cada paso: el refresco del día no se pelea
  con ellos.
- **Isla**: uniform `night_weight` en `storm_grade.gdshaderinc` (= noche × (1 −
  Tormenta)): quita un 30 % de saturación y enfría hacia el azul sin oscurecer (la
  luna ya baja la luz). La espuma, sin luz, se apaga un 40 %; el agua pierde
  además saturación y algo de brillo (agua azul bajo luna azul salía chillona).
  IslandGenerator lo lee (`StormSky.get_island_night_weight()`) al crear la isla.
- **Ventanas y faroles**: un parámetro del material compartido
  `ToyPalette.glow_material()` (el `albedo_color` si es `StandardMaterial3D`, el
  uniform `glow_gain` si un día es `ShaderMaterial`): ×0,8 de día, ×1,7 de noche,
  ×1,4 con la Tormenta encima. Más de 1 es HDR: con glow (calidad alta) brillan.
  Sin luces nuevas. Hoy solo lo usan las parcelas (`LotMesh`); los edificios
  horneados de la rama de arte lo heredan sin tocar nada.
- **2D (`StormTint2D`)**: el `CanvasModulate` parte del tinte del momento
  (`day_tint()`: blanco de día, `WARM_TINT` al alba y al ocaso, `NIGHT_TINT` azul
  de noche) y la ceniza se mezcla encima. Dos `lerp` por frame sobre un color.
- **Guardado**: clave `day` (`{"hour"}`), docs/09. Partida vieja = de día.
  **Offline el reloj no avanza**: al volver es la misma hora (como la Tormenta,
  solo la producción corre con el juego cerrado).
- **Coste**: nada nuevo por frame salvo durante los fundidos de la Tormenta (como
  antes). El refresco cada 2 s toca propiedades del Environment y de la luz, cinco
  uniforms y un color de material; el cielo (radiancia incremental) se recalcula
  entonces. En calidad mínima sigue sin sombras: la luz que gira no cuesta nada.
  Medida (2026-10-12, misma máquina cargada, 1600x900): alta día 50 fps / noche 49;
  mínima día 77 / noche 75 — de noche cuesta lo mismo que de día.
- Sonda: `tools/dianoche_probe.gd` (amanecer, día, atardecer, noche, costa y
  cerca de noche, mínima de noche, noche con Tormenta y después, y lo mismo en 2D;
  FPS de día y de noche). Capturas `docs/media/dev/dianoche_<tag>_*.png`.

### Sonda

`tools/arte_probe.gd` (con ventana y con `override.cfg` propio) fotografía la
colonia en calma, de cerca, la costa (`3d_costa`), las calidades baja y mínima
con su FPS, las tres fases de la Tormenta y la costa en Tormenta
(`3d_costa_tormenta`), y la vista 2D. Con `--rendering-method mobile` repite todo
en Mobile. Capturas en `docs/media/dev/arte_<tag>_*.png` (git-ignored).

Medida de referencia (2026-10-12, PC de desarrollo, 1600x900, colonia sembrada):
Forward+ alta ≈ 85 fps, baja ≈ 88, mínima ≈ 139; Mobile ≈ 135 / 138 / 151.

### Pendiente

- Día y noche: sin reglas todavía (producción nocturna, consumo de madera en luz,
  Tormenta de noche). Los caminantes tienen el gancho
  (`WorkerWalkers.set_presence()`, `GameConfig.life_night_presence`) sin cablear:
  colgaría de `day_phase_changed`. AudioManager no cambia de noche (un ambiente
  nocturno colgaría de la misma señal). Las parcelas no reciben `night_weight`
  (como con `storm_weight`). Sin entrada en Ajustes para apagar el ciclo.

- Las parcelas de los edificios (césped de los solares) no reciben
  `storm_weight`: bajo la Tormenta quedan algo más verdes que la isla. Son de
  los edificios, no de esta sección.
- `minimal` sin entrada en Ajustes ni en `GameConfig.GRAPHICS_QUALITY_MODES`.

## 13. Velocidad del juego (x1 / x2) e Informar de un fallo

> Número fijo: el código lo cita como "docs/21 §13" (rama `feat/soporte-y-velocidad`).

### Velocidad x1 / x2

- **Botón:** `scripts/ui/GameSpeedButton.gd`, una capa (10) que crea `PauseMenu`
  al arrancar como hermana suya (las dos vistas tienen `PauseMenu`; no está en
  las escenas). Dice `x1` o `x2` y nada más; en x2 se tiñe de acento. Slot
  `speed_button`: arriba en el centro, bajo el indicador de la Tormenta (en calma,
  en su sitio); con la columna central bajada (tablet 4:3) se queda arriba en el
  centro sin apilarse; en móvil vertical va bajo la insignia del rango. Registrado
  en `HudRegistry` (`GameSpeedButton`): se oculta en Ajustes → Interfaz y se mueve
  en Editar disposición.
- **Atajo:** tecla **F** (sin Ctrl/Alt), en `_unhandled_key_input`: un campo de
  texto con foco se la queda. Con el juego en pausa no responde
  (`PROCESS_MODE_PAUSABLE`).
- **Qué acelera:** la simulación. `GameConfig.game_speed` (1.0 o 2.0,
  `GAME_SPEEDS`) y `GameConfig.sim_delta(delta)`, que leen en su `_process`
  ProductionManager (construcción, producción, caducidad), ProcessManager,
  PopulationManager (consumo y crecimiento), ArmyManager (entrenamiento y
  sueldo), TechTreeManager, StormManager (ciclo y tormenta de prueba), DayClock,
  RandomEventManager y MarketManager. En el tablero, `get_combat_ai_step_delay()`
  pasa por `GameConfig.combat_pace()`: el turno enemigo va al doble.
- **Qué no:** la interfaz (tweens, avisos, cámara, arrastre), el autoguardado
  (segundos reales), los enfriamientos de avisos, el reloj del tutorial, el tiempo
  jugado (`ProgressionManager.get_played_seconds()`, que es de verdad) y la
  progresión offline.
- **Por qué no `Engine.time_scale`:** escala el `delta` de *todo* nodo y de todo
  tween y `Timer`: la cámara, los avisos, `DragScroll`, los globos, el
  autoguardado y las animaciones de menús irían al doble, y cada uno pediría su
  excepción (`ignore_time_scale`, o dividir el delta) en archivos de otras ramas.
  Con el multiplicador, la regla es una línea al principio de cada `_process` de
  servicio y lo demás no se entera. Coste: una multiplicación por servicio y
  fotograma. Con `dev_time_scale` se compone sin pisarse (uno acorta duraciones,
  el otro acelera el reloj).
- **La vista de combate** (otra rama) lee `GameConfig.game_speed`, acorta sus
  animaciones con `GameConfig.combat_pace(segundos)` y escucha
  `EventBus.game_speed_changed(speed)` para cambiar a mitad de tablero.
- **No se guarda:** ni en `save_game.json` ni en `settings.cfg`. Al abrir el
  juego siempre es x1 (escribirla en `settings.cfg` sería un valor que nadie lee).
  Lo que sí guarda `settings.cfg` es el botón: oculto o movido (HudRegistry). La
  pausa real sigue igual: con el árbol en pausa ningún `_process` corre.
- **Tests:** `tests/support/test_game_speed.gd`.

### Informar de un fallo

**☰ MENÚ → PARTIDA → Informar fallo** (en la fila de Historia, tras AYUDA; el
nombre largo va en su tooltip) copia al portapapeles
el informe de `scripts/services/BugReport.gd` y lo dice bajo los grupos, como
Guardar: "Copiado. Pégalo en un mensaje." Nada sale del equipo. Qué lleva, dónde
está el registro y cómo se limpian las rutas: docs/19 §7.

PARTIDA lleva dos filas de dos botones (Guardar | PARTIDAS, Historia | Informar
fallo, con letra de cuerpo): con diez botones en columna, en una tablet de 720 px
de alto "Guardar y salir" quedaba tras el scroll; con ocho filas cabe entero.
