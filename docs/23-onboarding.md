# 23 · Prólogo, tutorial y ayudas

Cómo aprende a jugar alguien que abre el juego por primera vez. Sustituye a la intro
paginada de `TutorialPanel` (10 páginas, lore y "Cómo se juega" en el mismo marco) y a
los seis globos de `HelperPanel` que salían a la vez. Arregla los bugs 1 (en parte), 2,
6 y 12 del diagnóstico de jugabilidad (fuera del repositorio).

Tres piezas, tres estilos, y ninguna se parece a otra:

| | Qué es | Estilo | Dónde |
|---|---|---|---|
| **Prólogo** | El lore, que se lee | Papel, máquina de escribir, lacre rojo, notas a mano | `PrologueScreen` (capa 32) |
| **Tutorial** | Qué tocar, sobre la interfaz de verdad | Latón sobre metal, flecha y velo | `TutorialPanel` (capa 19) |
| **Ayudas** | Globos y consejos, de uno en uno | Azul acero, con ✕ y barra de tiempo | `HelperPanel` (14 y 19) + `HelpIndexPanel` |

> **Rediseño 2026-10-18 (fase 2, `docs/28`)**: las tres piezas pasan al estilo nuevo
> (ventanas crema, letra redonda, una frase y el detalle al pedirlo, sin animaciones).
> Lo que cambia se resume en §10; la tabla de arriba es la de antes.

Junto al tutorial, la tarjeta de consejo y los partes de guerra habla un **instructor**
(§9): la Capitana Ada Remache en la colonia y el Sargento Mayor Casimiro Bombarda en el
combate, un busto dibujado por código que se pega a la tarjeta.

El estado va **en la partida** (`TutorialManager.get_save_data`): una partida nueva es
un jugador que no sabe nada otra vez. `reset()` se llama en los tres sitios de
`GameManager` que empiezan partida (`_new_game`, `clear_save`,
`clear_save_and_reload_from`), y al cargar el paso del tutorial se **deduce** de lo que
hay construido, no se cree a ciegas.

---

## 1. Prólogo (`scripts/ui/PrologueScreen.gd`)

El lore en **cuatro folios y en lenguaje claro** (2026-09-28; el cuarto, 2026-10-04): frases cortas y palabras
normales, en ES y EN. Ya no hay membrete ni subtítulo de expediente: cada hoja empieza
por su título. El texto va a máquina; debajo, a mano y en tinta azul
(`UITheme.hand_font()`), una nota de los Olvidados (`PRO_<n>_NOTE`). El primer folio
lleva el tampón **FIRMADO** y el tercero **VIVOS** (la hoja final no lleva tampón); cada folio, el sello de lacre con
"NADA SE PIERDE" (`RegenciaSeal.gd`, dibujado, sin imagen). El papel y la mesa son ruido
generado (`UITheme.parchment_texture`). Cada folio lleva su lámina de grabado (`PrologueEngraving.gd`, ver abajo).

| Folio | Título | Qué cuenta |
|---|---|---|
| 1 | La firma del Emperador | El Imperio manda en casi todo el mundo; el Emperador lleva un siglo muerto y la Regencia firma por él |
| 2 | La Tormenta | La ceniza que manda el Imperio, los Cobradores y el Impuesto |
| 3 | Quiénes somos | Los Olvidados, la isla dada por perdida, y lo que vamos a hacer: construir, aguantar y no pagar |
| 4 | Desde cero | **La hoja final, la última antes de jugar** (idea de Bryan, 2026-10-04): construirlo todo desde cero para pelear contra el Imperio y que no nos opriman; para eso, hacer crecer la economía y entrenar soldados. Sin instrucciones de botones |

Los textos son `PRO_1_*` … `PRO_4_*` en `Tr.gd`. La hoja final, tal cual:

> **Desde cero.** Empezamos con casi nada: un Núcleo, unos árboles y nuestras manos. Lo
> vamos a construir todo desde cero. / Primero haremos crecer nuestra economía. Con ella
> entrenaremos soldados. Y con soldados pelearemos contra el Imperio, para que nunca más
> nos opriman. *Nota:* «Ladrillo a ladrillo, hasta que dejen de darnos órdenes.»
>
> **From nothing.** We start with almost nothing: a Core, a few trees and our own hands.
> We will build everything from scratch. / First we grow our economy. With it we train
> soldiers. And with soldiers we fight the Empire, so no one ever oppresses us again.
> *Note:* “Brick by brick, until they stop giving us orders.”
 El agente
`.claude/agents/escritor-lore.md` es el que escribe lore y tutoriales con esta guía de
estilo.

### Una lámina por folio (2026-10-18, rama `feat/vista2d-y-prologo`)

La ronda de la 1.0 vio el folio con **dos tercios del papel vacíos** (mejora 8). Cada
folio lleva ahora un **grabado a tinta** (`scripts/ui/PrologueEngraving.gd`), dibujado
en código como el sello de lacre: contornos de tinta, rellenos de trazos paralelos
recortados contra cada forma (`Geometry2D.intersect_polyline_with_polygon`), sombras
de trazo cruzado, una plancha con doble filete y **un solo acento rojo de lacre** por
lámina. Sin imágenes: escala sin pixelarse en PC, tableta y teléfono, y no cuesta nada
mientras no cambia (sin `_process`; se pinta al cambiar de folio o de tamaño).

| Folio | Lámina |
|---|---|
| 1 La firma del Emperador | medallón con el busto coronado y la cinta de luto; el decreto firmado, el lacre y la pluma en el tintero |
| 2 La Tormenta | nubes de ceniza, ceniza que cae sobre las casas (una con el tejado roto) y el dirigible de los Cobradores con su bandera |
| 3 Quiénes somos | la isla con la nave y las chimeneas humeando, los nuestros en la orilla y, en el horizonte, el barco de los que se fueron |
| 4 Desde cero | el Núcleo a medio levantar con su andamio y la bandera, los árboles, el sol detrás, el montón de ladrillos y el martillo |
| B En trámite (Constructor) | el vigía con su catalejo sobre la roca, el libro de cuentas y el humo lejano de la isla |

**Maquetación** (`PrologueScreen.layout_for(sheet)`, pura):

- Folio ancho (≥ 600 px, PC, tableta y teléfono en horizontal): **la lámina a la
  derecha del texto**, del 36 % del ancho (170-320 px), con hueco abajo para el sello
  de lacre.
- Folio estrecho y alto (≥ 330 px): la lámina **encima** del texto, en una franja de
  90-150 px.
- Estrecho y bajo: solo texto (con su scroll, como antes).
- El texto pasa de 21 a 22 px. La lámina aparece con la máquina de escribir (fundido
  de 0,6 s) y Siguiente la completa como al texto.
- **El tampón** (FIRMADO, VIVOS, EN TRÁMITE) cae ahora **sobre la parte de abajo de la
  lámina**, como un golpe sobre el grabado (`stamp_position`); si la lámina no está o
  es pequeña, en su sitio de siempre.

- **El prólogo sí se salta** (`Saltar historia`, Esc): es lore, no tutorial.
- **Pie:** `Saltar historia` · puntos de página · `◀ Atrás` · `Siguiente ▶` (`Empezar`
  en el último). Atrás está apagado en el primer folio.
- **Deslizar** el dedo a la izquierda pasa folio, a la derecha vuelve. Un deslizamiento
  nunca cierra: cerrar es Empezar o Saltar. En teclado: ← →, Intro, Espacio, Esc.
- **Máquina de escribir:** el texto se escribe solo (80 car/s, tope 3 s). Siguiente o un
  toque en el papel mientras se escribe lo completa; el segundo toque pasa de folio.
- **Pausa** el juego mientras se lee (si no lo estaba ya) y corre en pausa.
- **Variantes por modo** (`TutorialManager.prologue_variant`):

| Modo | Prólogo |
|---|---|
| Campaña, Supervivencia | Completo, 4 folios (la firma del Emperador, la Tormenta, quiénes somos, desde cero) |
| Constructor | Corto: portada y un cierre propio, **EN TRÁMITE** ("Aquí no llega la Tormenta") |
| Sandbox | Ninguno (cuenta como visto). "Historia" a mano cuenta el completo |

**Cuándo sale.** Una vez por partida, en `game_new_started` o al cargar una partida que
no lo tiene visto. **Nunca detrás de otro menú:** queda pendiente
(`TutorialManager.is_prologue_pending`) y sale cuando no hay menú principal abierto, ni
árbol en pausa, y existe quien lo pinte (grupo `prologue_screen`). Era el bug 1: la intro
vieja se abría detrás del menú principal, en la capa 17, congelada por la pausa, y se
comía los toques de Ajustes.

**Reabrirlo:** `TutorialManager.show_prologue()` (alias `show_intro()`). Lo usan
"Historia" del menú de pausa, el índice de AYUDA y el menú ☰ único.

`PrologueScreen` es hija de `TutorialPanel` (se instancia en su `_ready`), así que no hay
que tocar `Main.tscn` ni `Main2D.tscn` y existe en las dos vistas.

Hoy la Nueva partida solo ofrece la Campaña (docs/20), así que en la práctica sale
siempre el completo; las variantes de los modos apartados siguen en el código.

### Guía rápida (`scripts/ui/QuickGuide.gd`)

**Ya no sale sola (14-10-2026, partidas de Bryan):** la ventana "Cómo funciona Tormenta
Imperial" sobraba al empezar, así que `TutorialPanel._on_prologue_closed()` ya no la
abre; tras el prólogo va directo la primera marca del tutorial. Sus cuatro bloques
siguen en el índice de AYUDA (`guide_qg_*`). Un `quick_guide` en `helps_seen` de una
partida vieja se carga y no cambia nada. Lo que sigue describe la pantalla.

**Reactivada desde AYUDA (17-10-2026, rama `feat/topes-mejoras-ayuda`):** no era código
muerto del todo (nadie la abría, pero sus textos son la mejor chuleta de una pantalla), así
que en vez de quitarla la abre el botón **CÓMO FUNCIONA** del índice de AYUDA
(`HelpIndexPanel`, nodo `QuickGuideOpen`, busca el grupo `tutorial_panel` y llama a
`open_quick_guide()`). Ya no se construye al arrancar: `TutorialPanel.quick_guide()` la crea
la primera vez que se pide (menos nodos en cada partida). Al cerrarla se marca vista
`quick_guide`, como antes.

Antes salía al cerrar el prólogo, **una vez por partida** (ayuda vista `quick_guide`) y
antes de la primera marca del tutorial: una pantalla con cuatro bloques: **recursos** (qué hay,
cuándo llega cada uno, el almacén y el taller), **extraer** (a mano se agota; con su
edificio, no), **edificios** (trabajadores, viviendas y carretera hasta el Núcleo) y
**progreso** (eras, árbol tecnológico y la Tormenta). Capa 33, hija de `TutorialPanel`,
grupo `quick_guide`; Esc, Intro o el botón la cierran. Mientras está abierta el tutorial
no se ve. Los mismos textos son las guías básicas `guide_qg_*` del índice de AYUDA.
No es el lore (eso es el prólogo) ni el tutorial (eso son las marcas).

---

## 2. Tutorial guiado (`scripts/ui/TutorialPanel.gd`)

> **TUTORIAL CORTO (decisión de Bryan, 2026-10-24, rama `fix/tutorial-flujo`).** Lo que
> sigue de §2 a §2.11 describe el tutorial largo (13 pasos) y queda como historia; lo
> vigente es esto:
>
> 1. **"De qué va"** (`scripts/ui/AboutScreen.gd`, capa 33): la primera pantalla de una
>    partida nueva. Qué es el juego y la meta en tres frases (`ABOUT_BODY`) y tres iconos
>    (`build` Construye y junta recursos · `army` Entrena tu ejército · `storm` Aguanta la
>    Tormenta y gana), botón **¡VAMOS!**. La abre `TutorialPanel` cuando el prólogo sale
>    solo en una partida nueva (`TutorialManager.take_about_first()`); "Historia" desde el
>    menú va directa al lore. Con la piel dieselpunk (integración v1.3): en PC y tablet
>    va centrada, 760 de ancho y el alto de su contenido (`CT.place_center`; antes
>    760×520 con media ventana vacía); en teléfono sigue con `place_window`.
> 2. **Lore corto**: el prólogo `full` pasa de 4 folios a 2 (`PRO_2` la Tormenta y `PRO_3`
>    quiénes somos), cada uno de una o dos frases. `PRO_1`/`PRO_4` siguen en Tr.
> 3. **Tutorial práctico, 8 pasos** (`GUIDE_GOALS` / `GUIDE_STEPS`, `GUIDE_TOTAL = 8`):
>
> | # | Paso | Señala | Avanza cuando |
> |---|---|---|---|
> | 1 | `resources` (tarjeta de leer) | la fila de recursos del HUD | **Entendido**. Para qué sirve cada recurso (`GUIDE_RESOURCES`) y sus iconos (`resource_facts()`: oro, madera, comida, acero, petróleo, materiales) |
> | 2 | `open_build` / `pick_sawmill` / `place_sawmill` / `wait_sawmill` | CONSTRUIR, la tarjeta, el bosque, la obra | acaba la obra del Aserradero |
> | 3 | `collect` | el Aserradero | se recoge madera |
> | 4 | `open_gold_mine` / `pick_gold_mine` / `place_gold_mine` / `wait_gold_mine` | CONSTRUIR, la tarjeta, la veta, la obra | acaba la obra de la Mina |
> | 5 | `collect_gold` | la Mina de oro | se recoge oro (`collected_gold`) |
> | 6 | `open_barracks` … `wait_barracks` | CONSTRUIR, la tarjeta, la obra | acaba el Cuartel |
> | 7 | `train` / `need_train` | ENTRENAR en la ficha del Cuartel | se pulsa ENTRENAR; sin oro o madera, espera plegada |
> | 8 | `wait_unit` / `battle` / `battle_launch` | el Cuartel; **Misiones** de la barra; **¡AL ATAQUE!** | acaba la primera pelea en el tablero (`encounter_ended`, o la salida termina: `battle_done`). En el tablero manda el combate guiado (§2.4) |
> | — | `done` | ☰ MENÚ (¿QUÉ HACER?) | "¡Ya sabes lo básico! Junta recursos y mejóralo todo." |
>
> - **Fuera del tutorial**: Casa, Granja, Mercado, Almacén, Laboratorio, girar, mover,
>   derribar. Salen como **consejos** cuando hacen falta, uno a la vez y nunca durante el
>   tutorial (`TIPS`: `house` sin manos ni sitio, `food_low` con comida para tres tics y
>   sin Granja, `placing` al coger un edificio — girar y cancelar —, `building_actions` al
>   tocar un edificio — mover y derribar —) y siguen en AYUDA (`HelpCatalog`, básicas).
>   ¿QUÉ HACER? sigue la línea después.
> - **Gente**: 10 colonos y sitio para 10 en el Núcleo: Aserradero 2 + Mina 3 + Cuartel 1
>   = 6, más 2 de minar a mano, sin Casa (`tests/tutorial/test_guide_workers.gd`).
> - **Gratis**: el primero de cada edificio del tutorial (Aserradero, Mina, Cuartel) y la
>   carretera, solo en una partida arrancada (`GameManager.has_begun()`); el soldado
>   cuesta lo de siempre (40 oro + 20 madera, se paga con lo de salida).
> - **Nada interrumpe** hasta acabar la primera batalla: la Tormenta, la de prueba, los
>   eventos y **también el hambre** (`PopulationManager` no consume ni crece mientras
>   `TutorialManager.blocks_interruptions()`).
> - **MISIONES** ya trae elegido al soldado de la primera escaramuza
>   (`SkirmishPanel._open`, `Objectives.first_sortie_party()`), y su botón está en el grupo
>   `hud_mission_launch`; el de la barra, `hud_bar_missions` (`HelpTargets` `bar_missions`,
>   `mission_launch`).
> - Arreglo de paso: una lección de combate que acaba sin atacar ya no deja su rótulo
>   ("COMBATE · PASO 1 DE 7") pegado en la tarjeta de la colonia
>   (`_on_lesson_encounter_ended` avisa al panel).
> - Sonda: `tools/recorrido_probe.gd -- --pobre` juega el tutorial con la bolsa a cero y
>   sin rellenar nada; `tools/line_probe.gd` ya no levanta el Laboratorio de la era 1 por
>   defecto (`--tutorial=1` para la apertura vieja).

Coach marks sobre la interfaz real. Cada paso:

- **oscurece** la pantalla menos el control del que habla, con un marco de latón que
  late (el velo es `MOUSE_FILTER_IGNORE`: se puede tocar todo, también fuera de orden);
- **señala** con una flecha;
- pone **una línea** de lo que hay que hacer, con "TUTORIAL · PASO n DE 13"; debajo,
  **las cifras del edificio con iconos** (`TutorialManager.building_facts()`: "[madera]
  +6 cada 12 s · [trabajadores] 2 trabajan", sacadas de `BuildingData` y `GameConfig`);
  y debajo **lo que falta** si algo lo impide (`step_hint`) y **cómo conseguirlo**
  (`step_how`). La tarjeta va junto a lo señalado (debajo si cabe, si no encima), nunca
  encima.

**No se salta ni se cierra** (decisión de Bryan, 2026-10-04; reforzada el 2026-10-16,
rama `feat/tutorial-claro`). La tarjeta no tiene `Saltar tutorial` ni ✕: el tutorial de
una partida nueva se hace entero. `TutorialManager.skip_guide()` queda como API interna
para sondas y pruebas, y fuera de `GameConfig.dev_mode` no hace nada. Los guardados con
el tutorial ya saltado (`"skipped"`) o hecho cargan igual. El **repaso** que se pide en
AYUDA > Repetir tutorial (`replay_guide()`) sí tiene `Terminar repaso` (`stop_replay()`):
lo pidió el jugador. Con el tutorial de verdad aún en marcha, Repetir tutorial no hace
nada (si no, sería la forma de saltarlo). Todos los caminos revisados, en §2.5.

**Tutorial claro (2026-10-16).** Empieza y acaba con **la meta de la partida**, y explica
**cada edificio del principio** en el momento en que se construye, con una frase de
para qué sirve (palabras de 12 años) y sus cifras con iconos, y enseña a **girar, mover y
derribar** un edificio. Trece pasos (doce hasta el 17-10-2026, cuando entró el Cuartel, §2.8):

| # | Paso (`GUIDE_STEPS`) | Señala | Avanza cuando | Qué explica |
|---|---|---|---|---|
| 1 | `goal` (tarjeta de leer) | nada: tarjeta abajo al centro | botón **¡A por ello!** (`confirm_step`, hecho `goal_seen`) | **La meta**: 3 eras, Cuartel General a nivel 3, aguantar el Ataque Final de la Regencia, y la Tormenta se detiene para siempre |
| 2 | `core` (tarjeta de leer) | un aro sobre el Núcleo | botón **Entendido** (hecho `core_seen`) | **Núcleo**: el corazón de la isla; todo va unido a él por carretera. Cifras: +8 viven aquí |
| 3 | `open_build` / `pick_sawmill` / `place_sawmill` / `wait_sawmill` | CONSTRUIR, la tarjeta, el bosque más cercano, la obra | se abre la lista, se elige, se coloca, acaba la obra | **Aserradero**: corta madera; casi todo se construye con ella. En la espera, **la carretera**: llega sola desde el Núcleo y sin ella un edificio no trabaja |
| 4 | `collect` | el aserradero | se recoge algo (`note_guide_fact("collected")`) | recoger lo producido |
| 5 | `rotate` / `rotate_pick` / `rotate_now`, y luego `place_house` | CONSTRUIR, la tarjeta de la Casa, y con la Casa en la mano el botón **R ↻** de la pantalla (tablet y móvil; en PC no hay botón: es la tecla R) | **gira** el edificio en la mano (`building_rotate_requested`, hecho `rotated`) y después se coloca la casa | **Girar**: R en PC, R ↻ con el dedo; un cuarto de vuelta cada vez. **Casa**: aquí vive tu gente, +6 trabajadores (va antes del Cuartel desde 2026-10-24, §2.12) |
| 6 | `open_barracks` / `pick_barracks` / `place_barracks` / `wait_barracks`, `train` / `need_train` | CONSTRUIR, la tarjeta del Cuartel, la obra; después ENTRENAR en su ficha | se coloca un cuartel, acaba la obra y se pulsa ENTRENAR | **Cuartel** (2026-10-17): entrena soldados; con soldados en casa, los Cobradores del Impuesto no se llevan nada. En la espera: se entrena tocando el Cuartel y pulsando ENTRENAR. Sin oro o madera para el soldado, `need_train` es un paso de espera (§2.12). Cifras: 1 trabaja, +8 soldados |
| 7 | `open_farm` / `pick_farm` / `place_farm` | CONSTRUIR, la tarjeta de la Granja | se coloca una granja | **Granja**: comida; tu gente come cada poco |
| 8 | `move` / `move_place` | MOVER en la ficha si está abierta (`info_move`); si no, la Casa en el mapa (`built:house`) | se mueve cualquier edificio (`building_moved`, hecho `moved`) | **Mover**: gratis, conserva el nivel |
| 9 | `road_open` / `road_pick` / `road_place`, y `demolish` | CONSTRUIR, la tarjeta de la Carretera; después Confirmar, DEMOLER o el tramo puesto (`info_demolish_confirm\|info_demolish\|practice_road`) | se pone a mano un tramo de carretera (1 oro, hecho `road_placed`) y se derriba algo (`building_demolished`, hecho `demolished`) | **Derribar**: devuelve la mitad de lo que costó; el Núcleo y la carretera que une edificios no se quitan. Se practica con 1 oro: no se pierde nada importante |
| 10 | `open_gold_mine` / `pick_gold_mine` / `place_gold_mine` | CONSTRUIR, la tarjeta, la veta de oro más cercana (`deposit:gold_vein`) | se coloca una mina | **Mina de oro**: oro de una veta; paga edificios y soldados |
| 11 | `open_market` / `pick_market` / `place_market` | CONSTRUIR, la tarjeta del Mercado | se coloca un mercado | **Mercado**: vende lo que sobra, compra lo que falta |
| 12 | `open_warehouse` / `pick_warehouse` / `place_warehouse` | CONSTRUIR, la tarjeta del Almacén | se coloca un almacén | **Almacén**: más sitio; lo que no cabe se pierde. Cifras: +500 de almacén |
| 13 | `open_laboratory` / `pick_laboratory` / `place_laboratory` | CONSTRUIR, la tarjeta del Laboratorio | se coloca un laboratorio | **Laboratorio**: mejoras para siempre (más producción, más sitio, obras más rápidas) |
| — | `done` | ¿QUÉ HACER? | "Entendido" o 25 s | **La meta otra vez**, en una línea, y que ¿QUÉ HACER? dice el paso siguiente |

El orden de los edificios sigue casi la línea de ¿QUÉ HACER? (`Objectives.LINE`: aserradero,
cuartel, granja, mina, casa, mercado, almacén); desde el 2026-10-24 la casa va justo después
de recoger, antes del Cuartel y la Granja (§2.12: con ella llegan 6 trabajadores más de golpe). El Laboratorio va el último: no está en la
línea, pero la Refinería lo pide (`building_prerequisites`).

Las claves: `GUIDE_GOAL`, `GUIDE_CORE`, `GUIDE_OPEN_<EDIFICIO>` (la frase de para qué
sirve, con `_TOUCH`), `GUIDE_PICK_<EDIFICIO>`, `GUIDE_PLACE_GOLD_MINE`,
`GUIDE_PLACE_ANYWHERE`, `GUIDE_HOW_*` (cómo conseguir lo que falta) y `GUIDE_FACT_*` (las
cifras). Lo mismo, para leerlo con calma, en AYUDA > Primeros pasos: **Tu meta**
(`guide_goal`) y **Los edificios del principio** (`guide_start_buildings`), y ¿QUÉ HACER?
dice la meta con las mismas palabras (`OBJ_MISSION_TEXT`).

**Partida vieja:** una isla con aserradero y casa (las metas de antes, `LEGACY_GOALS`) da
el tutorial por hecho igual que antes; no se le piden la meta ni los edificios nuevos.

**Girar, mover y derribar (2026-10-16).** Tres metas "fact" con pasos propios según lo que
hace el jugador (`menu_step` con la lista abierta, `placing_step` con algo en la mano). La
tecla R de los dos colocadores ya no gira directamente: emite
`EventBus.building_rotate_requested`, la misma señal que el botón R ↻ de
`OnScreenControls`, y así el tutorial ve el giro con teclado y con el dedo. El tramo de
carretera se reconoce porque se pone con la carretera en la mano y en su paso (los tramos
de la carretera automática no cuentan); `practice_road_cell` es transitorio. Derribar
cualquier otra cosa también cumple el paso; si se derriba un edificio de las metas, el
paso sale de lo que queda y lo vuelve a pedir. Mientras se mueve, se derriba o se repara,
la marca no se esconde con la ficha del edificio abierta (`INFO_PANEL_STEPS`), y señala
sus botones (grupos `hud_info_move`, `hud_info_demolish`, `hud_info_demolish_confirm`,
`hud_info_repair`; el ↻, `hud_rotate_building`; `HelpTargets`). Un objetivo puede tener
alternativas con `|`: el primero que se encuentre.

**Recoger y la Granja (2026-10-04, rama `feat/comida-granja-recoger`).** Lo que
producen los edificios se queda en ellos hasta recogerlo, y la gente come comida: los
dos pasos van en el orden en que pasan al arrancar (el aserradero produce su primera
madera; la comida de salida dura pocos minutos). Entran en `GUIDE_GOALS` (§2.3) entre
el aserradero y la casa: una meta "fact" (`collected`: se recogió algo desde que empezó
el tutorial, en `guide_flags`; repetir el tutorial lo vuelve a pedir) y una meta "build"
(`farm`, sin espera de obra). Un guardado de la rama de comida anterior a `GUIDE_GOALS`
traía `guide_collected`, y se lee como `guide_flags.collected`. Una isla vieja con
aserradero y casa sigue dando el tutorial por hecho: `start_guide()` cuenta recoger y la
Granja como hechos solo para esa comprobación.

**El paso se deduce, no se cuenta.** `TutorialManager.derive_step(hechos)` es pura:
aserraderos (en obra y hechos), recogido, granjas, casas, lista de construir abierta,
qué se tiene en la mano. Por eso:

- **Fuera de orden** no se rompe: si coloca una casa primero, sigue pidiendo el
  aserradero y luego ya no pide la casa. Si cancela, vuelve un paso.
- **Al cargar** vuelve donde estaba: el estado `active` está en la partida y el paso sale
  de lo construido.
- **Partida vieja:** con aserradero y casa ya hechos se da por hecho sin enseñar nada;
  quien vio la intro vieja (que traía "Cómo se juega") no lo repite.
- **Repetir tutorial** (índice de AYUDA) cuenta desde lo que hay (`guide_baseline`): pide
  un aserradero más.

**El tutorial pide CONSTRUIR** (2026-09-28): en los pasos de elegir (`pick_sawmill`,
`pick_house`), si el edificio pedido ya está elegido en la lista, la marca pasa al botón
CONSTRUIR del detalle y el texto cambia a "Bien. Ahora pulsa CONSTRUIR"
(`GUIDE_PRESS_BUILD`). La tarjeta pedida (la Casa es la última de la lista) se
desplaza sola a la vista. Con otra ventana abierta encima (Tecnología, Mercado...) la
marca no se pinta; con CONSTRUIR sí, porque los pasos ocurren ahí dentro.

### 2.1 Que ningún paso se atasque

Sin botón de saltar, ningún paso puede quedarse pidiendo algo imposible. Cada segundo
(`GUIDE_CHECK_SECONDS`), con el tutorial activo, `TutorialManager` repasa las metas:

| Caso | Qué hace | Prueba (`tests/tutorial/test_guide_never_stuck.gd`) |
|---|---|---|
| Sin bosque al que llegar (agotado, tapado, sin carretera posible) | La meta del aserradero se pasa de largo (`has_reachable_deposit`, en los dos giros) y pide la casa. Si vuelve a haber sitio, la vuelve a pedir | `no_reachable_forest`, `no_forest_at_all`, `a_forest_lost_mid_guide` |
| Mapa aún sin sortear | No se salta nada a ciegas | `a_map_not_drawn_yet` |
| Tope de edificios (un repaso con los 5 aserraderos; el Mercado y el Laboratorio, únicos; los 3 Cuarteles de la era 1) | Se pasa de largo (`goal_impossible_reason` = `limit`; también `prereq` y `rank`) | `the_building_limit_reached`, `a_replay_with_the_barracks_at_its_limit_skips_it` |
| Sin Aserradero (bosque imposible) | El Cuartel lo pide (`prereq`): se pasa de largo también | `no_reachable_forest` |
| Una meta se pasa de largo (2026-10-17) | Un aviso de una línea, una vez, dice por qué y que el tutorial sigue (`GUIDE_SKIP_DEPOSIT/LIMIT/PREREQ/RANK`, `TutorialManager._notice_skipped`); en un repaso no | `a_skipped_goal_says_why_once` |
| Sin veta de oro al alcance | La Mina se pasa de largo, y el Mercado (que la pide) también: sigue el Almacén | `a_step_already_done` |
| Paso ya cumplido antes de llegar | El paso sale de lo construido: no lo pide | `a_step_already_done`, `a_sawmill_built_before` |
| Faltan recursos | Debajo del paso, "Te falta: 70 oro \| 50 madera" (`step_hint` con `OBJ_MISSING`, ≤ 8 palabras: el aserradero y la casa solo cuestan oro y madera) | `short_of_resources`, `the_panel_shows_the_missing_line` |
| Faltan trabajadores | "Faltan trabajadores: construye antes una Casa." (`GUIDE_NEED_WORKERS`); la casa no pide trabajadores. Si ya hay sitio libre en las casas, debajo: "Llegan solos a tus casas, uno cada poco. Espera un momento." (`GUIDE_HOW_WORKERS_WAIT`) | `short_of_workers`, `short_of_workers_with_room_in_the_houses_says_to_wait` |
| Cómo conseguir lo que falta (2026-10-16) | Debajo de "Te falta", una línea por recurso: madera → el icono del Aserradero; oro → el icono de la Mina, o sacarlo a mano de una veta si aún no hay Mina (`step_how`, `GUIDE_HOW_*`) | `short_of_resources_also_says_how_to_get_them` |
| No llega para el edificio que toca (2026-10-17) | El paso deja de ser "Toca CONSTRUIR" y pasa a **consigue lo que falta** (`need_<edificio>`, §2.7): dice todo lo que falta y cómo conseguirlo, señala dónde, y vuelve solo al paso de construir | `test_short_of_resources_the_guide_waits_and_comes_back_by_itself` y siguientes |
| El aserradero no produce (sin trabajadores, retirado, sin carretera) | En "recoger": "Tu Aserradero está parado: tócalo y mira por qué." (`GUIDE_HOW_STOPPED`) | — |
| Táctil | Todos los pasos tienen texto con el dedo; lo que falta se dice igual | `touch_steps_all_resolve` |
| Vista 2D | El bosque se busca en el generador registrado (`GameManager.map_generator()`, también `MapGenerator2D`) y su punto sin Camera3D | `the_2d_view_finds_the_forest_too` |

Las metas imposibles (`blocked_goals()`) no se guardan: se recalculan al cargar, cada
segundo y en cuanto se cumple una meta (`_recheck_guide`). Solo se miran **hasta la meta
que toca** (buscar sitio junto a una veta cuesta, y con diez metas no se paga cada
segundo por las que aún no tocan). La obra (`wait_sawmill`) no puede atascarse: termina
por tiempo. Las tarjetas de leer (`goal`, `core`) tampoco: su botón siempre está.

### 2.2 Cómo están hechos los pasos

`GUIDE_GOALS` es la lista **ordenada** de metas; `GUIDE_STEPS`, el texto, el número y el
objetivo de cada paso. `derive_step(hechos, metas)` recorre las metas y devuelve el
primer paso sin cumplir. Dos clases de meta:

- `"build"`: un edificio, con pasos `open`, `pick`, `place` y, si se espera la obra,
  `wait`. Los hechos son `<id>s` y `<id>s_built` (lo que hay menos el punto de partida).
- `"fact"`: algo que no es un edificio. Se cumple con
  `TutorialManager.note_guide_fact("<fact>")`, que se guarda en la partida
  (`guide_flags`) y vale aunque el tutorial no haya llegado a ese paso.

### 2.3 La granja y "recoger producción"

La rama `feat/comida-granja-recoger` metió sus dos pasos en el hueco **sin reescribir
nada** de `derive_step`:

1. En `GUIDE_GOALS`, detrás del aserradero y delante de la casa:
   `{"goal": "collect", "kind": "fact", "fact": "collected", "step": "collect", "needs": "sawmill"}`
   y `{"goal": "farm", "kind": "build", "building": "farm", "steps": {"open": "open_farm", "pick": "pick_farm", "place": "place_farm"}}`.
   `needs` es nuevo: una meta "fact" cuya meta necesaria se pasa de largo (sin bosque al
   alcance no hay aserradero) también se pasa de largo, porque no hay nada que recoger.
2. En `GUIDE_STEPS`, `collect` (5, señala `building:sawmill`) y los tres de la Granja (6,
   `card:farm`); la casa pasa a 7 y `GUIDE_TOTAL` a 7 (una prueba exige que sea el mayor `n`).
3. Las claves `GUIDE_COLLECT` y `GUIDE_*_FARM` en `Tr.gd`, ES y EN, con `_TOUCH`.
4. `TutorialManager` escucha `EventBus.production_collected` y llama
   `note_guide_fact("collected")`.

El resto (contar, saltar lo imposible, decir lo que falta, guardar, cargar) ya
funcionaba para cualquier meta: `test_the_collect_and_farm_goals_sit_between_sawmill_and_house`
lo comprueba con la lista real.

**Texto de dedo o de ratón:** cada paso usa `Tr.ti`, con variantes `_TOUCH` ("Toca
CONSTRUIR" / "Haz clic en CONSTRUIR"; "arrastra el mapa" / "WASD o arrastrar").

**Modos:** el tutorial es el mismo en los cuatro y no tiene pasos de Tormenta ni de
Auditoría. Se esconde durante el prólogo, la pausa, el menú principal y el tablero. Lo del
tablero lo enseña el combate guiado (§2.4).

### 2.4 El combate guiado (2026-10-14, rama `feat/ensenar-combate`)

Hasta aquí el tutorial acababa en el mapa de la colonia y nadie explicaba el tablero.
Ahora hay **dos lecciones** con marcas sobre el tablero de verdad, en las dos vistas
(frente y tablero) y en el tablero 2D. Diseño: `21_REDISENO_CICLO_Y_CONTENIDO.md` §4.1.

| Paso | Clave | Señala | Se cierra cuando |
|---|---|---|---|
| 1 | `CGUIDE_SELECT` | tu unidad (la del aro dorado) | la tocas (abre su ficha) o ya te mueves/atacas |
| 2 | `CGUIDE_MOVE` | la casilla azul que más te acerca al enemigo | te mueves |
| 3 | `CGUIDE_ATTACK` / `CGUIDE_ATTACK_FAR` | el objetivo (el de ventaja, si no el más tocado) / Terminar turno si no llegas | atacas |
| 4 | `CGUIDE_ENEMY_TURN` | el botón Ver alcance enemigo; el alcance se pinta solo | vuelve tu turno |
| 5 | `CGUIDE_DEFEND` | Defender — **solo si te han quitado vida** | haces cualquier cosa |
| 6 | `CGUIDE_ART_RANGE` | tu artillería; se pinta su zona de tiro y las ✕ de al lado | actúa o pasa su turno |
| 7 | `CGUIDE_TYPE_CIRCLE` | nada: la tarjeta dibuja el círculo (`TypeCircle.gd`) | Entendido (ya no se cierra sola a los 15 s, 2026-10-16) |

- **Lección `basics`** (pasos 1-5): la primera pelea con tablero de la partida (en la
  práctica, la primera misión: un soldado contra uno débil). Cuenta como dada al
  terminar el paso 5, o al acabar esa pelea **si el jugador llegó a atacar**: abandonar o
  perder antes de atacar no la gasta, vuelve en la próxima pelea (2026-10-16).
- **Lección `artillery`** (pasos 6-7): la primera pelea con artillería propia (también una
  dotación de torre en una defensa), ya dada la de lo básico. Si la pieza no llega a
  actuar, espera a la próxima pelea con artillería.
- **Cómo se decide el paso:** igual que en la colonia, sale de lo que ha pasado
  (`TutorialManager.derive_combat_step(lesson, facts)`, pura, probada sin tablero), no de
  un "Siguiente". Los hechos se apuntan con las señales del combate (`turn_started`,
  `unit_moved`, `unit_attacked`, `unit_defended`) y con
  `note_combat_fact("selected")`, que llama `BattleScreen` al tocar una pieza propia.
- **Sin Saltar** (2026-10-16): ningún paso lo tiene. Los pasos 1-3 nunca lo tuvieron; el
  botón `Saltar` de los pasos 4-7 se quitó de `TutorialPanel`, y
  `TutorialManager.skip_combat_lessons()` queda como API interna, solo en modo dev, como
  `skip_guide()`. Ninguno puede atascarse: sin objetivo a tiro, el 3 señala Terminar turno;
  los 4-6 se cierran con cualquier acción o al pasar el turno; el 7 tiene Entendido.
- **Quién pinta:** `TutorialManager` emite `EventBus.combat_lesson_step_changed`;
  `TutorialPanel` (capa 19, encima de `BattleScreen`, 18) usa la misma tarjeta, flecha y
  aro, sin velo; pregunta cada fotograma a `BattleScreen.coach_anchor(target)` dónde
  está lo señalado y espera mientras la maqueta 3D anima (`{"busy": true}`).
- **La tarjeta "Combate" de siempre** (`encounter`) no sale encima de una lección: se da
  por vista y queda en el índice.
- **Guardado:** `combat_lessons_done` en la clave `tutorial` (`["basics", "artillery"]`),
  limpiado por `reset()` (llamado en los tres sitios de `GameManager`), carga idempotente.
  Un guardado de antes sin la clave: quien ya ganó su primera misión no repite lo
  básico; la de artillería sí le sale una vez. Lo de dentro de una lección no se guarda
  (una pelea nunca se guarda).
- **Repetir:** en AYUDA, **Repetir combate guiado** (`replay_combat_lessons()`) vuelve a
  dar las dos en la próxima pelea.

### 2.5 Caminos para saltar o cerrar el tutorial, revisados (2026-10-16)

| Camino | Antes | Ahora |
|---|---|---|
| Botón `Saltar tutorial` de la tarjeta | Quitado el 04-10 | Sigue sin existir (`test_there_is_no_skip_tutorial_button`) |
| ✕ o cerrar la tarjeta | No había | Sigue sin haber; las tarjetas de leer solo avanzan con su botón, el de su propio paso (`confirm_step`) |
| `Esc` / botón atrás de Android | Abren la pausa (☰ MENÚ); el tutorial se esconde y vuelve al quitarla | Igual: esconder no es saltar. `TutorialPanel` no escucha teclas |
| Ajustes > Interfaz "Mostrar ayudas en pantalla" (`ui_helper_visible`) y el mismo interruptor del índice de AYUDA | Solo apagan globos y consejos (`HelperPanel`) | Igual: el tutorial guiado y el combate guiado no lo miran |
| Ajustes > Interfaz, ocultar elementos del HUD (`HudRegistry`) | ☰ MENÚ y CONSTRUIR no se pueden ocultar | Igual: lo que señala el tutorial siempre queda |
| AYUDA > Repetir tutorial con el tutorial de verdad en marcha | No hace nada | Igual (si no, daría `Terminar repaso`) |
| ☰ MENÚ > Historia (prólogo) | Esconde el tutorial mientras se lee | Igual. El prólogo **sí** se salta (`Saltar historia`), como decidió Bryan |
| `TutorialManager.skip_guide()` | Solo en modo dev, sin botón | Igual |
| Combate guiado: botón `Saltar` de los pasos 4-7 | Daba por vistas las dos lecciones | **Quitado**; `skip_combat_lessons()` solo en modo dev |
| Combate guiado: el círculo de ventajas | Se cerraba solo a los 15 s | **Solo con Entendido** |
| Combate guiado: abandonar o perder la primera pelea antes de atacar | Daba lo básico por visto | **Ya no**: vuelve en la próxima pelea |
| Estado guardado `tutorial` | Un `"skipped"` solo lo escribe `skip_guide()` (dev); `"done"` lo escribe el final | Igual. Una partida vieja con aserradero y casa sigue dándolo por hecho (`LEGACY_GOALS`) |
| Nueva partida | Empieza el tutorial de cero | Igual |
| Girar, mover y derribar (pasos 6-8) | — | Como el resto: sin Saltar, y no se atascan (girar y mover siempre se pueden; derribar vale con cualquier edificio que no sea el Núcleo) |
| La lección de reparar | — | Sin Saltar ni ✕: se cierra con Entendido o al reparar (§2.6) |

### 2.6 La lección de reparar (2026-10-16)

Una tarjeta de leer **aparte del tutorial guiado** (`TutorialManager.REPAIR_STEP`), que sale
**la primera vez que un edificio se daña** (`EventBus.building_damaged`): en la primera
Tormenta de verdad o en un asedio (la tormenta de prueba de la era 1 no rompe nada). Si el
tutorial guiado está en marcha, espera a que acabe. Señala el edificio dañado (o la ficha
con REPARAR si está abierta) y dice: que la Tormenta y los ataques dañan; que cuanto más
dañado, más cerca de la ruina, y en ruinas no produce; que se repara con REPARAR en su
ficha y cuesta según el daño (la fila de cifras enseña lo que cuesta ahora,
`BuildingHealth.repair_cost`); que cada torre en pie reduce el daño; que el Núcleo y las
carreteras no se dañan (`BuildingHealth.is_immune`). Las etapas visibles del daño las hace
otra rama (`feat/danos-y-tormenta-corta`): aquí solo se explica.

- **Sin saltar y sin atascarse:** se cierra con **Entendido** o al reparar el edificio (o
  cuando ya no queda nada dañado). No hace falta poder pagar la reparación.
- **Una vez por partida:** `repair_lesson_done`, en la clave `tutorial`; `reset()` la
  olvida; un guardado sin la clave no la ha dado. Al cargar una partida con un edificio
  dañado y la lección sin dar, sale (se re-deriva, no se guarda el paso).
- Mientras está en pantalla, los globos y consejos de `HelperPanel` esperan
  (`TutorialManager.is_coach_active()`).
- En AYUDA: **Daños y reparar** (`guide_repair`, categoría Tormenta, oculta en
  Constructor). Y en Primeros pasos: **Girar**, **Mover** y **Derribar**
  (`guide_rotate`, `guide_move`, `guide_demolish`), con su variante de dedo.

### 2.7 Consigue lo que falta (2026-10-17, rama `fix/tutorial-materiales`)

Bug de la 1.0 (partida de Bryan): tras la Casa, el tutorial pedía un edificio detrás
de otro (Mina, Mercado, Almacén, Laboratorio) sin esperar a que llegara para
pagarlos. La marca seguía en CONSTRUIR, el botón del detalle salía apagado y lo que
faltaba era una línea pequeña debajo; con pocos trabajadores ni eso: `step_hint`
decía solo "construye antes una Casa" (ya hecha) y se callaba los recursos.

**Causa:** `derive_step` no miraba si se podía pagar el edificio de la meta; el paso
de abrir/elegir salía igual. **Arreglo:**

- `guide_facts()` añade `short`: los edificios de las metas que ahora no se pueden
  pagar (`TutorialManager.short_goals()` / `can_pay_now()`: trabajadores libres y todo
  el coste, materiales del taller incluidos; tope, requisitos y rango no, eso lo pasa
  de largo `goal_impossible_reason`).
- `derive_step`: si el edificio de la meta está en `short` y no se lleva en la mano, el
  paso es `need_<edificio>` (`GUIDE_NEED`: "Mina de oro: aún no puedes construirlo.
  Primero consigue lo que falta:"). También en girar (la Casa) y en el tramo de
  carretera. Cada segundo se vuelve a mirar: al tenerlo todo, vuelve solo a "Toca
  CONSTRUIR".
- Debajo, **todo** lo que falta (`step_hint`: trabajadores en una línea, recursos y
  materiales en otra) y **cómo conseguir cada cosa** (`step_how`, que usa
  `Objectives.how_to_get`): madera (del Aserradero, o a mano en un bosque), oro (de la
  Mina, o a mano en una veta), comida/acero/petróleo (de su edificio, o construirlo),
  materiales ("Tablones: toca tu Aserradero y pulsa «Serrar tablones»", o
  "constrúyelo antes"), trabajadores (esperar si hay sitio, si no otra Casa).
- La marca señala dónde (`need_target`): el productor de lo primero que falta (o su
  obra), el bosque o la veta si aún no hay productor, CONSTRUIR si hace falta otra Casa.

Fuera del tutorial: **¿QUÉ HACER?** dice todo lo que impide la obra
(`Objectives.blocker` usa `PlacementRules.block_reasons`, no solo lo primero) y debajo
cómo conseguirlo (`describe`). Al colocar, el **fantasma** sale rojo si no llega para
pagarlo (3D y 2D), y con el dedo, al apuntar a un sitio válido sin poder pagarlo, el
aviso dice qué falta (`PlacementAssist.move_to`). CONSTRUIR ya lo decía (coste en
rojo, `block_reasons_short` junto al botón). Balance sin tocar.

---

**Tarjeta compacta y la otra Casa (2026-10-18, rama `feat/hud-y-tutorial`):**

- `GUIDE_NEED` es más corta ("Mina de oro: antes consigue lo que falta:").
- La tarjeta se compone con `TutorialPanel.compose_card_text()`: la frase, lo que
  falta, cómo conseguirlo y, si lo señalado no se ve, "arrastra el mapa hacia la
  flecha" **al final** (antes salía en medio). Como mucho `CARD_MAX_LINES` (5) líneas
  sin contar el rótulo; las de "cómo conseguirlo" que no caben se quedan fuera
  (siempre queda una). En los pasos `need_*` no salen las cifras del edificio.
- **Solo falta otra Casa** (`TutorialManager.needs_house_only()`: recursos pagados,
  faltan trabajadores y las casas están llenas). Con el Cuartel temprano pasa casi
  siempre en el Laboratorio (5 + 6 de sitio = 11; aserradero 2 + cuartel 1 + granja 2
  + mina 3 + mercado 1 + almacén 1 = 10; el Laboratorio pide 2). En vez de "antes
  consigue lo que falta" + lista, el paso dice una frase natural, `GUIDE_NEED_HOUSE`:
  "Laboratorio: le faltan trabajadores y tus casas ya están llenas. Primero haz otra
  Casa: trae 6 más." Sin `step_hint`/`step_how` debajo (lo repetirían). La marca sigue
  en CONSTRUIR y, al acabar la Casa, el paso vuelve solo al Laboratorio: no se atasca.
- **Combate guiado:** la tarjeta se aparta de los avisos de abajo a la izquierda
  (`NotificationPanel.toasts`, capa 19 sobre el tablero) y de la ficha de la unidad
  tocada (`BattleScreen.unit_card()`): `TutorialPanel.clear_of()` la pone a su
  derecha, encima o debajo, sin tapar lo señalado; si nada cabe, se queda.

---

### 2.8 El Cuartel temprano (2026-10-17, rama `feat/cuartel-temprano`)

Decisión de Bryan: el Cuartel pasa a la era 1 (120 oro + 80 madera + 10 tablones, sin
acero, solo pide el Aserradero; docs/03) y el tutorial **solo añade el Cuartel**: un
paso (el 5) justo después de recoger la madera, con abrir, elegir, colocar y esperar la
obra, y su `need_barracks` (los tablones se sierran en el Aserradero: el paso de
"consigue lo que falta" ya lo sabía decir). `GUIDE_TOTAL` pasa a 13. Los demás pasos
siguen igual. Si no hay Aserradero posible (sin bosque), el Cuartel se pasa de largo por
su requisito.

**Que nadie se quede perdido con un salto.** Hasta ahora una meta imposible (`limit`,
`rank`, `prereq`, `deposit`) se pasaba de largo en silencio. Ahora sale una vez un aviso
de una línea: "Aserradero: no queda sitio junto a su bosque o su veta. El tutorial
sigue." (en un repaso no, ahí el tope es cosa del repaso).

**La tormenta de prueba trae un Impuesto de juguete** (docs/22 §12): al escampar bajan
unos Cobradores de prueba. Con soldados en casa se pelea en el tablero contra uno o dos
débiles; como suele ser la primera pelea con tablero de la partida (o la primera tras
la primera misión), la lección `basics` del combate guiado sale sola si aún no se dio.
Sin soldados se llevan un 10 % de la bolsa (tope 40) y el parte (`WarReportScreen`,
"IMPUESTO DE PRUEBA") explica que con un Cuartel y soldados no se lo habrían llevado.
Antes, el aviso de la prueba (`STORM_TRIAL_INCOMING`) ya dice "si tienes soldados en
casa, pelean", y el consejo del Cuartel (`HELP_TIP_BARRACKS_BODY`) explica por qué se
quiere pronto y dónde se entrena de verdad (toca tu Cuartel y pulsa ENTRENAR; hasta el
2026-10-24 decía ☰ MENÚ > COLONIA > EJÉRCITO, que no es donde se entrena). Guardado:
`trial_tithe_pending` en la clave `storm`; si se guarda con los Cobradores de prueba en
la puerta, al cargar vuelven a pedirse. `StormManager.reset()` lo limpia (ya se llama en
los tres sitios de `GameManager`).

Pruebas: `tests/tutorial/test_guide_steps.gd` (`after_collecting_comes_the_barracks_then_the_farm`,
`the_barracks_step_numbers_and_texts`, el recorrido entero), `tests/tutorial/test_guide_never_stuck.gd`
(tablones que faltan, avisos de salto), `tests/storm/test_storm_trial.gd` (Impuesto de
juguete), `tests/ui/test_war_reports.gd` (su parte) y `tests/economy/test_cuartel_temprano.gd`.
Sin correr aún (se corren en la ronda final).

### 2.9 El objetivo, paso a paso (2026-10-19, rama `feat/objetivo-paso-a-paso`)

Queja de Bryan: "siempre me dices EDIFICIO: OBJETIVO («Casa: …», «Cuartel: …», «Mina
de Oro: aún no puedes construirlo…»); coloca el OBJETIVO y ya, y explica PASO A PASO qué
se necesita". Y un bug suyo: "cuando me pide oro, si no está contado al oro, todo queda
bugueado": lo que espera en la Mina sin recoger no contaba, el paso pedía "te faltan 120
de oro" y se quedaba esperando.

**El objetivo en verbo, sin nombre delante.** `Objectives.goal_title()`: "Construye un
Cuartel", "Entrena tu primer soldado", "Sube el Cuartel General a nivel 2", "Gana la
misión «X» (Campaña de Tierra)". Los artículos salen de `Objectives.building_a()` /
`building_the()` / `your_building()` (`FEMININE_ES`: Casa, Granja, Mina, Fundición...).
Revisadas todas las claves con la forma "%s: …" que hablaban de un edificio o recurso
(`OBJ_DO_BUILD`, `OBJ_DO_REPAIR`, `OBJ_DO_RESEARCH`, `OBJ_DO_CONTRACT`, `OBJ_DO_CAMPAIGN`,
`OBJ_DO_MAKE`, `OBJ_DO_SANDBOX_MODE`, `GUIDE_NEED`, `GUIDE_NEED_HOUSE`, `GUIDE_SKIP_*`,
`GUIDE_HOW_*`, `TOPE_HOW_MATERIAL`, `LBL_DOMAIN_NEEDS`, `CAMP_LOCK_BUILDING`), en ES y EN;
`test_menos_texto_objetivos.gd` vigila que ninguna empiece por "%s:".

**Los pasos.** `Objectives.plan()` (= `plan_for(goal_step(), next_step())`) devuelve el
objetivo y 2-4 pasos con estado (`PLAN_MARKS`: ✓ hecho, ● el de ahora, ○ por hacer),
sacados de lo que falta de verdad:

| Paso (`kind`) | Cuándo | Ejemplo |
|---|---|---|
| `have` / `build` | requisito o taller del material | ✓ Aserradero / ○ Construye una Fundición |
| `make` | material del coste | ● Fabrica 10 tablones (6/10) |
| `collect` | lo que falta espera en un edificio | ● Recoge oro de la Mina de Oro (+45) — "En la bolsa 20 + por recoger 45 / necesitas 80" |
| `gather` | falta de la bolsa y no hay nada por recoger | ● Junta 80 de oro (20/80) |
| `room` | el coste no cabe, o la bolsa está llena y falta algo | ● Haz sitio en el almacén |
| `workers` | faltan manos | Espera a 1 trabajador más / Construye otra Casa (+6 trabajadores) |
| `place` | el último | ○ Coloca el Cuartel / Entrena Infantería (0/1): lleva al Cuartel, ENTRENAR en su ficha |
| `action` | `next_step()` es un apoyo que no está en la lista (Granja por comida, vender...) | va el primero, como el de ahora |

El de ahora: lo que se recoge (gratis, y desatasca), si no el que coincide con
`next_step()`, si no el primero que falte. `goal_step()` es `next_step()` sin los apoyos
(`_next(support)`): **`next_step()` no cambia** y la sonda de línea lo sigue leyendo igual.
Cada paso trae `how` (una frase) y `go`: {"build": id} abre CONSTRUIR con ese edificio
(`ConstructionMenu.open_on`), {"node"}/{"building"} lleva la cámara y abre la ficha,
{"deposit"} lleva la cámara al bosque o la veta más cercana, {"panel"} abre EJÉRCITO o
MISIONES. Un paso que espera por algo que no se ve no existe: si el productor está parado
lo dice (`OBJ_STEP_STOPPED`), con la bolsa llena pide sitio en vez de recoger.

**Dónde sale.**
- **Línea plegable del HUD** (`ObjectivePanel.refresh_line`): el objetivo y el paso de
  ahora, cortos (`Objectives.plan_line`): "Construye un Cuartel · Fabrica tablones 6/10",
  "Construye un Cuartel · Recoge oro +45". Al mantener, el objetivo y todos los pasos.
- **Panel ¿QUÉ HACER?**: el título es el objetivo; debajo, los pasos como botones planos
  (tocar uno lleva a él) y el "cómo" del de ahora. El aviso suelto de "te falta" solo
  queda para un objetivo sin pasos.
- **Tarjeta del tutorial** `need_<edificio>`: la frase es el objetivo ("Construye un
  Cuartel"), `step_hint` son los pasos con su marca (como mucho `NEED_PLAN_ITEMS` = 3) y
  `step_how` el cómo del de ahora; `need_target` señala lo del paso de ahora (el edificio
  con algo por recoger, el productor, la veta, CONSTRUIR). "Solo falta otra Casa" ya no es
  una frase aparte: es el paso ● Construye otra Casa (+6 trabajadores).

Pruebas: `tests/ui/test_objectives.gd` (títulos sin nombre delante en ES/EN, artículos, la
lista del Cuartel, colocar, **oro sin recoger** y que al recogerlo avanza, la bolsa llena,
la otra Casa, el apoyo delante, toda la línea con una lista corta y un solo paso de ahora,
`next_step()` intacto, el panel y la línea), `test_menos_texto_objetivos.gd`,
`tests/tutorial/test_guide_never_stuck.gd` y `tests/ui/test_hud_y_tutorial.gd`. Sonda:
`godot --path . -s tools/recorrido_probe.gd -- --objetivo --profile=phone --shot-size=800x360`
(y `--profile=pc --shot-size=1920x1080`): tarjeta del tutorial, línea y panel con oro sin
recoger y con tablones 6/10.

### 2.10 Nada interrumpe el tutorial (2026-10-19, rama `feat/objetivo-paso-a-paso`)

Queja de Bryan: "la primera tormenta está llegando aunque esté haciendo el tutorial".
`TutorialManager.blocks_interruptions()`: con el tutorial guiado en marcha (no un repaso
pedido desde AYUDA), o pendiente de empezar en una partida ya arrancada (el prólogo
delante), esperan:

- la **tormenta de prueba** (`StormManager.check_trial`): llega en `trial_due_at()`, a su
  hora (`storm_trial_at`, 300 s jugados) y nunca antes de `storm_trial_after_guide` (90 s)
  después de acabar el tutorial, con su Aviso delante como siempre;
- la **Tormenta de verdad**: con el reloj en calma no avanza (una ya empezada, de un
  guardado viejo, sigue su curso; la invocada a mano en Sandbox, también);
- los **eventos aleatorios** (`RandomEventManager`): el reloj no corre; el que ya estaba en
  curso acaba.

Guardado: `TutorialManager.guide_finished_at` (segundos jugados al acabar el tutorial de
verdad; `finish_guide` y `skip_guide`, no un repaso) viaja en la clave `tutorial`; sin ella
(partida de antes) vale -1 y la prueba sale a su hora de siempre. `trial_done` no cambia.
Partidas sin tutorial (repaso, guardados con el tutorial hecho, Sandbox/Constructor, que ya
no tienen prueba) siguen como antes. La sonda de línea juega como quien ya acabó el
tutorial (`tools/line_probe_player.gd` pone `guide_state = done`), así que sus cifras no
cambian. Pruebas: `tests/storm/test_storm_trial.gd` (no llega en medio, llega 90 s después,
tutorial corto = hora de siempre, el repaso no frena, guardado, el reloj de verdad en calma)
y `tests/tutorial/test_tutorial_holds_interruptions.gd`.

### 2.11 Los pasos de espera se pliegan (2026-10-19, ramas `integracion/ui-v2` y `feat/ui3-tutorial`)

Queja de Bryan: "cuando no tienes los recursos, el tutorial se vuelve molesto porque te
sigue marcando cosas todo el tiempo en pantalla; no es mi culpa no tenerlos". Primera
versión en `integracion/ui-v2` (e98310c); revisada y completada en `feat/ui3-tutorial`.

- **Pasos de espera** (`TutorialPanel.is_waiting_step` / `is_waiting_now`): `need_*`,
  `wait_*` y `collect` **mientras el Aserradero no ha cortado nada** (no hay icono que
  tocar). La tarjeta sale una vez (`fold_seconds`: 4 s, hasta 8 s si el texto es largo,
  como la carretera de la obra del Aserradero) o hasta «Más tarde», y se **pliega** a un
  recordatorio de una línea con la cara de la Capitana (`GuideReminder`), sin flecha, aro
  ni velo, que no bloquea nada. Va donde vive la línea de ¿QUÉ HACER? (slot `next_step`,
  que el tutorial esconde): encima de la barra de abajo, sin taparla. Con CONSTRUIR u
  otra ventana abierta no se pinta encima de su lista.
- **Qué dice** (`_reminder_line`): el paso de ahora de la lista (`need_plan` →
  `current.short`: "Junta oro 45/80", "Fabrica tablones 6/10", "Faltan 2 trabajadores");
  la obra ("Obra: Aserradero 44 %"); "Aserradero cortando madera…". Nunca la lista
  entera ni un "✓" de lo ya hecho (la primera versión copiaba la primera línea de
  `step_hint`, que podía ser "✓ Aserradero").
- **Tocarlo** abre la tarjeta; abierta a mano dura `REOPEN_SECONDS` (8 s) antes de
  replegarse. Un paso de espera ya visto que vuelve (los recursos bajan y suben alrededor
  del coste) sale **ya plegado** (`_seen_wait`).
- **¡Ya puedes!** Al pasar de una espera a un paso de acción (`need_x` → `open_x`, o
  `collect` cuando aparece la madera), la tarjeta se abre **una vez por paso**
  (`_ready_done`) con su flecha y el rótulo "¡YA PUEDES! · TUTORIAL · PASO N DE M"; se
  puede plegar con «Más tarde» y el recordatorio dice "¡Ya puedes! Pulsa CONSTRUIR" /
  "¡Ya puedes! Recoge la madera". La segunda vez que se llega a ese paso es un paso de
  acción como siempre.
- **90 s sin avance** (`IDLE_REMIND_SECONDS`; avance = cambia el texto del recordatorio):
  solo se resalta el borde, sin animación ni sonido. La tarjeta grande nunca vuelve sola.
- Los pasos de acción (toca aquí, coloca, gira, recoge con madera) siguen como antes.
- `collect` señala ahora el Aserradero terminado (`built:sawmill|building:sawmill`): antes
  apuntaba solo a su obra y, acabada, la tarjeta salía sin flecha.
- Lo señalado debajo de la tarjeta de recursos o del rango (una veta tras el HUD) cuenta
  como fuera de pantalla (`_under_hud`): el aro y la flecha ya no caen sobre los números.
- **No se guarda.** Plegado, visto y "¡Ya puedes!" son estado de la vista (como el paso en
  pantalla); al cargar o cambiar de vista 3D/2D la tarjeta del paso de espera vuelve a
  salir una vez y se pliega. El paso sí sale del guardado (`derive_step`).

Pruebas: `tests/tutorial/test_tutorial_reminder.gd`. Sonda:
`godot --path . -s tools/recorrido_probe.gd -- --recordatorio --profile=phone --shot-size=800x360`
(y `--profile=pc --shot-size=1920x1080`): tarjeta, recordatorio, resaltado, reabierta,
"¡Ya puedes!" abierto y plegado, la vuelta plegada, la obra, recoger y el Cuartel sin
tablones (con CONSTRUIR abierto encima).

### 2.12 Lo que Bryan encontró jugando la 1.1 (2026-10-24, rama `fix/tutorial-flujo`)

Seis quejas, seis arreglos:

1. **"Me indica ENTRENAR sin recursos y me lo sigue marcando."** La meta `train` lleva
   `unit: infantry`; sin oro o madera para el soldado (`unit_missing_cost`, en `short`
   como `"unit:infantry"`), `derive_step` da `need_train`: un paso de **espera** como los
   `need_*` (lista ✓/●/○ "Junta 40 de oro (10/40)", se pliega al recordatorio, sin flecha
   sobre ENTRENAR). Al tenerlo vuelve solo a `train` ("¡Ya puedes!"). `need_goal`,
   `need_plan_for_step` y `need_target_for_step` sirven para edificio o unidad.
2. **"Los soldados no son en MENÚ > EJÉRCITO."** Fuera de todos los textos que mandaban
   a entrenar allí (`GUIDE_WAIT_BARRACKS`, `TUT_TIP_BARRACKS_BODY`, `HELP_TIP_BARRACKS_BODY`,
   `OBJ_STEP_TRAIN(_HOW)`, `OBJ_DO_TRAIN`, docs/14): "toca tu Cuartel y pulsa ENTRENAR"
   (`HELP_B_ARMY` añade Astillero y Aeródromo). El paso de entrenar de ¿QUÉ HACER? lleva al
   edificio de la unidad (`{"building": ...}`), no al panel EJÉRCITO.
3. **"Salgo, pulso CONSTRUIR y me vuelve a ofrecer el Cuartel."** La lista de CONSTRUIR
   recordaba el último edificio elegido: al volver a abrirla salía el Cuartel ya puesto en
   el detalle, con su botón CONSTRUIR, como si fuera otra vez el objetivo. Ahora
   `ConstructionMenu._on_build_pressed` deja la lista sin elegir nada (salvo carretera y
   decoraciones, que se ponen en serie). El paso del tutorial ya salía de lo construido.
4. **"Me pides la Casa y ya me pides oro."** Mientras dura el tutorial guiado de verdad
   (no un repaso), **el primero de cada edificio que pide sale gratis**, y la carretera
   también (`TutorialManager.is_free_build`, que mira `BuildingData.get_cost`: CONSTRUIR,
   fantasma, cobro, ¿QUÉ HACER? y tutorial lo leen igual). La fila de CONSTRUIR lleva
   "Gratis en el tutorial" (`LBL_TUTORIAL_FREE`), también el detalle, las cifras de la
   tarjeta y el aviso al coger el edificio. Sin abuso: uno de cada (`free_builds_used`, en
   la clave `tutorial`; `reset()` lo vacía), solo si no hay ninguno en la isla, y derribar
   uno regalado no devuelve nada (meta `tutorial_free`, guardada en su entrada de
   `buildings`). Al acabar el tutorial, precios de siempre. `GameConfig.tutorial_free_builds`
   lo apaga (las pruebas de "consigue lo que falta"). El soldado no es gratis: por eso
   existe `need_train`.
5. **"Los trabajadores se agotan."** Con 5 colonos el Aserradero, el Cuartel y la Granja
   los gastaban todos antes de la Casa: ni minar a mano (2) cabía, y sin minar no había
   oro para la Casa. Ahora **10 colonos y sitio para 10 en el Núcleo** (`population_start`,
   `nucleo.tres`) y el tutorial corto no pide Casa: 6 trabajan + 2 de minar a mano caben,
   y detrás aún la Granja. `tests/tutorial/test_guide_workers.gd` lo recorre meta a meta.
6. **Cancelar, mover y derribar.** La primera colocación (`GUIDE_PLACE_SAWMILL`) dice
   "¿Te equivocaste? Esc o clic derecho deja de colocar" (con el dedo, "✕ CANCELAR"); el
   de mover (`GUIDE_MOVE_PLACE`), cómo dejarlo donde estaba. Mover y derribar nombran los
   botones de la ficha de hoy (MOVER; Derribar, el rojo, y DERRIBAR para confirmar), y
   AYUDA > Primeros pasos tiene **Dejar de colocar** (`guide_cancel`).

Pruebas: `tests/tutorial/test_guide_never_stuck.gd` (entrenar sin recursos, con la bolsa
a cero ningún paso se atasca, gratis una vez y sin reembolso, precios al acabar, la
tarjeta), `test_guide_steps.gd` (orden y números), `test_guide_workers.gd`,
`tests/economy/test_cuartel_temprano.gd` (textos de entrenar) y
`tests/ui/test_construction_menu_flow.gd` (el objetivo cumplido no vuelve).

## 3. Ayudas (`HelperPanel`, `HelpCallout`, `HelpCatalog`)

`HelpCatalog` es la lista de todas: los globos del HUD (`callout_*`), los consejos de
`TutorialManager.TIPS` y las guías básicas (`guide_*`, lo que eran las páginas "Cómo se
juega"). Cada una tiene id, categoría, título, texto (`Tr.ti`) y el control al que
apunta.

**Reglas:**

1. **Una a la vez.** Cola por prioridad (`HelpCatalog.priority`): los consejos de algo
   que acaba de pasar (100) van delante; luego MISIONES, construir, objetivo,
   recursos, cámara, zoom y menú. Entre dos que salen solas hay 1,2 s de respiro.
2. **Cada una con ✕ y cierre solo:** de 6 a 12 s según el largo del texto
   (`auto_close_seconds`), con una barra fina que se vacía. El reloj se para mientras el
   dedo está apoyado encima o el ratón pasa por encima.
3. **Cerrada o agotada, vista** (`TutorialManager.helps_seen`, en la partida). No vuelve
   a salir sola.
4. **Contextual:** nada sale durante el tutorial guiado. Al terminarlo salen los básicos
   de uno en uno (y si se saltó, solo posible con la API interna, primero el de construir). El de MISIONES sale cuando
   aparece su botón. Los consejos, cuando pasa lo que explican.
5. **Se callan y vuelven** sin contar como vistas: con una ventana abierta, en pausa, con
   el índice de AYUDA abierto, colocando con el dedo y, los globos, con la Tormenta
   encima. Los consejos no se callan por la Tormenta: la explican.
6. **Sin sitio junto a su control** (tablet con la columna central bajada, pantalla
   estrecha) el globo sale en la tarjeta de abajo, y un marco azul señala el control.
7. **Interruptor global** (no toca el tutorial guiado ni el combate guiado, §2.5) (`GameConfig.ui_helper_visible`, el de Ajustes > Interfaz de
   #29 y el del índice): apaga las que salen solas; las que se piden en el índice salen
   igual.
8. **Cortos** (2026-10-04): un globo está junto a su control, así que no lo describe
   ("CONSTRUIR (el botón grande de abajo)" sobraba). Cada globo, en 14 palabras como
   mucho, con su `_TOUCH` (`test_menos_texto_avisos.gd`). El de ☰ MENÚ ya no nombra
   Mercado ni Tecnología, que se abren desde sus edificios. Las explicaciones que los
   paneles mandan al tooltip (descripción del edificio, regla de la carretera, intro
   del árbol tecnológico) siguen en la guía rápida, la guía de edificios y los
   consejos del índice: en táctil es donde se leen (docs/21 §6, "Menos texto").

**La primera misión** (docs/15-combat.md §4). Al salir del cuartel la primera
unidad, el consejo `first_sortie` señala ☰ MENÚ (donde vive MISIONES) y ¿QUÉ HACER?
pide "Lanza tu primera misión" antes de la guarnición. La marca
`TutorialManager.first_sortie_done` (en la partida) se pone al ganar una salida; hasta
entonces cada salida es un solo nodo fácil con botín. El globo antiguo
`callout_skirmish` sigue atado al botón de la columna lateral, que ya no se abre desde
que MISIONES pasó al menú ☰: en la práctica no sale.

### Ayudas de las novedades (2026-10-14, rama `feat/ayudas-novedades`)

Cosas nuevas que no tenían ayuda. Todas son **básicas** (están en el índice desde el
principio) y salen solas una vez, cuando el jugador se encuentra con lo que explican.
Claves `HELP_T_*` / `HELP_B_*` (con `_TOUCH` donde se habla de ratón).

| Id | Tipo | Cuándo sale sola | Dispara |
|---|---|---|---|
| `saves` | consejo | al terminar el tutorial | `TutorialManager._connect_news` (`tutorial_guide_finished`) |
| `callout_speed` | globo (señala x1/x2) | detrás de los globos básicos, al terminar el tutorial o al cargar con él hecho | `HelperPanel.NEWS_AFTER_GUIDE` |
| `rank` y `flag` | consejos | el primer ascenso de rango (uno detrás de otro) | `governor_rank_up` |
| `night` | consejo | el primer anochecer | `day_phase_changed` (DUSK/NIGHT) |
| `farm` | consejo | la primera Granja terminada | `construction_completed` |
| `collect_full` | consejo | el primer edificio lleno sin recoger | `building_stock_changed` + `ProductionManager.is_full` |
| `island` | consejo | el primer intento de construir en el agua | los colocadores 3D y 2D, rama `"water"` |
| `bug_report` | consejo | tras pulsar Informar de un fallo (sale al cerrar el menú) | `PauseMenu.report_bug` |

Los targets nuevos de `HelpTargets` son `speed_button` (`GameSpeedButton`) y
`rank_badge` (`RankPanel`). Lo de combate (unidades, placa, aro, mira, ventaja por
tipo) va en otra rama (`feat/ensenar-combate`).

### Ayudas de combate (2026-10-14, rama `feat/ensenar-combate`)

Seis guías básicas en la categoría Ejército, al final de `HelpCatalog.ENTRIES`:
`guide_combat_units` (las tres unidades), `guide_combat_move` (turnos, mover y atacar,
el frente), `guide_type_advantage` (quién gana a quién), `guide_artillery_range` (la ✕),
`guide_combat_previews` (el daño previsto y Ver alcance enemigo) y
`guide_combat_defend` (Defender y Esperar). Claves `HELP_T_COMBAT_*` / `HELP_B_COMBAT_*`
(y `_TYPE_ADVANTAGE`, `_ARTILLERY_RANGE`), con `_TOUCH` donde se habla de hacer clic.
Sin números escritos a mano: si cambia el balance, el texto sigue valiendo (los números
están en la ficha de unidad, que los lee de `GameConfig`).

### Índice de AYUDA (`scripts/ui/HelpIndexPanel.gd`)

- Grupo **`help_index`**, método **`open()`**: el menú ☰ único lo abre con
  `get_tree().get_first_node_in_group("help_index").open()`. Lo crea `HelperPanel`.
- Arriba: el interruptor "Mostrar ayudas en pantalla", GUÍA DE EDIFICIOS, Repetir
  tutorial, Historia, Repetir combate guiado y **CÓMO FUNCIONA** (la guía rápida).
- **Páginas con números (17-10-2026, rama `feat/topes-mejoras-ayuda`):** cinco guías básicas
  con `"dyn": true` en `HelpCatalog`: **Topes de edificios** (`guide_limits`), **Mejorar
  edificios** (`guide_upgrades`), **Las eras** (`guide_eras`), **Taller: fabricar
  materiales** (`guide_workshop`) y **Torres** (`guide_towers`, solo donde hay Tormenta).
  Su texto lo escribe `BuildingHelpText.help_body(id)` leyendo `GameConfig` (topes por era,
  multiplicadores, repuestos, coste del Cuartel General, mitigación y dotaciones de las
  torres, recetas del taller, requisitos), así que no se queda viejo cuando cambia el
  balance. Su clave `body` (`HELP_B_LIMITS`…) es el resumen de una línea del tooltip
  (`HelpCatalog.summary()`). Tocar una **no** la manda a la tarjeta de abajo (con reloj de
  12 s no da tiempo a leerla): se lee dentro del índice, en grande y con scroll
  (`HelpIndexPanel.show_page()`), con **← VOLVER** a la lista; se marca vista.
- **GUÍA DE EDIFICIOS** (`HelperPanel`): cada edificio lleva una segunda línea con su tope
  por era, la era en que se puede construir, lo que pide antes y si se mejora
  (`BuildingHelpText.guide_rules_line()`); el coste incluye ya los materiales.
- Debajo, por categoría (Primeros pasos · Economía · Tormenta y Impuesto · Ejército y
  combate): las básicas siempre, y el resto en cuanto se han visto (✓). Respeta el modo:
  en Constructor no hay nada de Tormenta.
- Tocar una cierra el índice y la vuelve a abrir (`TutorialManager.reopen_help`),
  señalando su control.
- Funciona con el árbol en pausa (se abre desde la pausa o el menú principal).

### Textos corregidos con la línea jugable

`docs/22-linea-jugable.md` §8 (rama `balance/linea-jugable`) midió que varios textos
contradecían la partida. Van con claves nuevas en `# ── prologo-ayudas ──`:
`HELP_B_ARMY` (el camino en el orden de ¿QUÉ HACER?, guarnición de cinco con dos
artillerías), `HELP_B_STORM` (la Tormenta ya no se presenta al empezar: es una guía del
índice), `HELP_TIP_TITHE_BODY` (Cuota Mínima desde la segunda visita),
`HELP_TIP_BARRACKS_BODY`, `HELP_TIP_CONSUMPTION_BODY` (el Mercado) y
`HELP_TIP_AUDIT_BODY` (seis blindados). El "Listo" del tutorial menciona ¿QUÉ HACER?.

---

## 4. Para otros paneles

- **Botón CONSTRUIR:** que esté en el grupo `hud_build_button` (y el ☰ en
  `hud_menu_button`, el "☰ MENÚ" de `PauseMenu`). Sin grupo, CONSTRUIR cae en
  `HudRegistry`.
- **Tarjetas de la lista de construir:** se encuentran por el nombre del edificio; si
  `ConstructionMenu` les pone `set_meta("building_id", id)`, se usa eso.
- **Historia:** `TutorialManager.show_prologue()`.
- **AYUDA:** `get_tree().get_first_node_in_group("help_index").open()`.
- **Una ayuda nueva:** entrada en `HelpCatalog.ENTRIES` y claves en Tr (ES y EN; `_TOUCH`
  si habla de ratón). Si es un consejo, además en `TutorialManager.TIPS` con su
  disparador.

---

## 5. Pruebas y sonda

| Suite | Qué fija |
|---|---|
| `tests/tutorial/test_quick_guide.gd` | la guía rápida se abre sin pausar y avisa al cerrarse, sus cuatro bloques en ES y EN, los mismos bloques en el índice de AYUDA, y que cerrar el prólogo ya no la abre |
| `tests/tutorial/test_prologue_screen.gd` | 4 folios, Atrás/Siguiente/Saltar, Siguiente×2 + Atrás = folio 2, Atrás apagado en el primero, deslizar, máquina de escribir, pausa, variantes, textos ES/EN, estilo propio; la hoja final (última, Empezar, el plan en palabras llanas ES/EN sin botones, teclado y deslizar); la lámina de cada folio (todas las variantes la tienen, sigue al folio, se dibuja a tamaño PC, tableta y teléfono, `layout_for` al lado / encima / fuera, el tampón sobre la lámina) |
| `tests/tutorial/test_guide_steps.gd` | *(2026-10-16, sin correr aún: la meta y el Núcleo, girar/mover/derribar, los edificios del principio)* `derive_step`, recorrido entero, cancelar, saltar (API interna), fuera de orden, isla hecha, repetir, reanudar al cargar, guardado y basura |
| `tests/tutorial/test_guide_never_stuck.gd` | *(2026-10-16, sin correr aún: tarjetas de leer, cifras con iconos, "cómo conseguirlo", sin veta de oro, partida vieja, la lección de reparar)* sin "Saltar" (solo dev), repetir no salta, terminar un repaso, guardados saltados; un test por caso de atasco (§2.1); la granja y recoger entre aserradero y casa (§2.3) |
| `tests/tutorial/test_tutorial_panel.gd` | *(2026-10-16: el botón de las tarjetas de leer y la fila de cifras)* prólogo alojado, paso con texto y número, el velo no se come toques, sin botón de saltar, "Terminar repaso" solo en un repaso, esconderse en pausa y con el prólogo, la tarjeta no tapa lo señalado |
| `tests/tutorial/test_tutorial_manager.gd` | consejos una vez, prólogo pendiente hasta poder salir, modos, reset y guardado |
| `tests/ui/test_helper_callouts.gd` | una a la vez, ✕ y vista, reloj y pausa con el dedo, prioridad, silencios, interruptor, reabrir pedida |
| `tests/ui/test_helper_skirmish_callout.gd` | el globo de MISIONES sigue a su botón y sale una vez |
| `tests/tutorial/test_first_sortie_tip.gd` | el consejo `first_sortie` sale con la primera unidad (antes que el sueldo) y una vez, señala ☰ MENÚ, textos ES/EN con `_TOUCH`; la marca `first_sortie_done` solo con una victoria, guardado idempotente, `reset()` y guardados viejos |
| `tests/ui/test_help_index.gd` | grupo `help_index`, lista básicas y vistas, modo Constructor, reabrir |
| `tests/ui/test_topes_mejoras.gd` | *(17-10-2026, sin correr aún)* la frase del tope lleno (sube con la era, único, máximo), consejo de mejorar, MEJORAR UNO elige el de nivel más bajo, lo que llega con una era, la ficha (nivel N de 3, sin mejora con porqué, repuestos, por qué está apagado, no cabe en el almacén), `{HQ2_COST}`, las cinco páginas en ES/EN sin huecos, la página dentro del índice, CÓMO FUNCIONA, la guía de edificios y los textos de la bolsa con la comida |
| `tests/tutorial/test_combat_lessons.gd` | *(sin correr aún, 2026-10-14 y 2026-10-16)* qué lección toca, cada paso de `derive_combat_step`, ningún paso con Saltar, `skip_combat_lessons()` solo en dev, abandonar antes de atacar no gasta lo básico, textos ES/EN, números hasta `COMBAT_TOTAL`, guardado idempotente, `reset()`, guardados viejos, repetir |
| `tests/ui/test_combat_teaching.gd` | *(sin correr aún)* el combate guiado en la pantalla de verdad (tablero 2D): empieza solo, señala a la unidad, tocar tu pieza abre la ficha y pasa el paso 1, la tarjeta `encounter` no sale encima |
| `tests/ui/test_title_prologue_order.gd` | menú principal abierto → sin prólogo; Ajustes desde el menú arriba y sin nada encima; soltar → prólogo encima de todo; la pausa también lo retiene |

**Sonda con ventana:** `tools/onboarding_probe.gd` (siempre con un `override.cfg` de
carpeta propia):

```
godot --path . -s tools/onboarding_probe.gd -- --shot-size=1280x800 --profile=tablet
godot --path . -s tools/onboarding_probe.gd -- --shot-size=1280x720 --profile=pc --view=2d
godot --path . -s tools/onboarding_probe.gd -- --mode=builder
```

Arranca una partida nueva con el menú principal delante, lo suelta, pasa folios
(deslizando con el dedo en tablet), recorre tres pasos del tutorial con toques reales, lo
salta (con `skip_guide()`: en el editor es modo dev) y fotografía un globo, un consejo, el índice y una ayuda reabierta. Capturas en
`docs/media/dev/onboarding/` (ignorada por git).

## 6. Lo que queda

- El globo de cámara no sabe si el jugador ya movió la cámara: sale igual, una vez.
- El bosque que se señala es el más cercano al centro de la pantalla; puede caer bajo la
  cruceta en tablet, y puede ser uno tapado aunque haya otro libre (la meta solo se pasa
  de largo si no queda **ninguno**).
- Los flujos de Maestro (`qa/maestro/`) usaban `saltar_tutorial`: ahora solo espera. Un
  flujo que necesite el HUD sin la tarjeta tiene que hacer el tutorial.
- (Resuelto en la integración con el menú único: CONSTRUIR está siempre abajo y el
  paso 1 lo señala a él; ya no hay texto "abre ☰".)

---

## 7. Vocabulario (2026-10-16, rama `feat/tutorial-claro`)

El juego es para chavales de **10 a 15 años** (y adultos). Bryan: "los nombres que usas,
que si tasadores y demás, suenan muy difíciles de leer para preadolescentes". Esta tabla
es la que se aplicó a **todos los valores de `Tr.gd`** (ES y EN; las claves no cambian) y
la que tienen que seguir los textos nuevos. Criterio: **una palabra que un chaval de 12
años usa o entiende sin diccionario, que diga lo que la cosa hace**, y que conserve el
tono (dieselpunk, un Imperio que cobra). Los nombres propios de la historia se quedan si
se explican una vez.

| Palabra difícil | Palabra sencilla (ES) | Inglés antes → ahora | Criterio |
|---|---|---|---|
| Tasadores | **Cobradores** | Assessors → **Collectors** | Dice lo que hacen: vienen a cobrar. "Tasar" no lo usa un chaval |
| Diezmo | **Impuesto** (fase del HUD: IMPUESTO) | Tithe → **Tax** | "Impuesto" se aprende en el colegio; "diezmo" no |
| Cuota Mínima | **pago mínimo** | Minimum Quota → **minimum payment** | Palabras de todos los días |
| Auditoría Final / auditoría | **Ataque Final** / el ataque | Final Audit → **Final Assault** | Es un asedio de oleadas: que el nombre lo diga. La ironía de la Regencia contable queda en el prólogo |
| asedio | **Ataque Final** / ataque | siege → **Final Assault** / assault | Un solo nombre para la misma cosa |
| convocar (la Auditoría) | **llamar** | summon → **call** | Verbo corriente; el botón QUE BAJEN se queda |
| reentrenar / relevos | **entrenar más** / **refuerzos** | retrain / reliefs → **train** / **reinforcements** | Palabras de videojuego que ya conocen |
| Amortizados | **los Olvidados** | the Written-Off → **the Forgotten** | "Amortizar" es contabilidad; "olvidados" dice lo mismo (el Imperio nos dio por perdidos) |
| guarnición | **tropas en casa** / **tus tropas** | garrison → **home troops** | Dice dónde están y para qué |
| dotación (de torre) | **cañoneros** | crew → **gunners** | Lo que son: los que disparan el cañón de la torre |
| embargar / embargados | **quedarse con** / **perdidos** | seize / seized → **take** / **lost** | Sin palabras de juzgado |
| reclutados (leva) | **se llevan** (trabajadores) | conscripted → **they take** | Lo que pasa, dicho llano |
| Escaramuza(s) | **Misión(es)** (botón MISIONES) | Skirmish(es) → **Mission(s)** | La palabra de los juegos que ya juegan |
| Incursión | **Ataque rápido** | Raid (se queda) | — |
| Avanzadilla de la Regencia | **Campamento de la Regencia** | Regency outpost → **Regency camp** | — |
| columna (la que sale de expedición) | **tu grupo** | column → **your party** | — |
| tope de despliegue | **salen demasiadas unidades** | deploy cap → **too many units going out** | — |
| Vivienda | **Casa** | House (igual) | Más corta y más clara; es como la llama Bryan |
| Depósito (el edificio) | **Almacén** | Warehouse (igual) | "Depósito" chocaba con los depósitos del mapa (vetas, pozos) |
| Vehículo Blindado / blindados | **Tanque** / tanques | Armored Vehicle / armoured → **Tank** | Todos saben qué es un tanque |
| infante(s) | **soldado(s)** (la unidad sigue siendo Infantería) | infantry (igual) | "Infante" también es un niño o un príncipe |
| mitigar / suavizar el daño | **reducir** | mitigate / soften → **reduce** | — |
| desertar / Deserción | **se van** / Se van | desert / Desertion → **leave** / Leaving | — |
| Hambruna | **Hambre** | Famine → **Hunger** | — |
| Hito | **Logro** | Milestone → **Achievement** | La palabra de las consolas |
| Tasa de Corrupción | **Al cancelar solo vuelve el %** | Corruption Rate → **Cancel and only % comes back** | Decir la regla, no el nombre |
| iniciativa | **rapidez** ("el más rápido va primero") | initiative → **speed** | — |
| yacimiento | **veta** (de oro, de hierro) | deposit (igual) | — |
| el Libro (de la Regencia) | **sus cuentas** | the Ledger → **the books** | — |
| Bolsa Imperial | **el Mercado** | Imperial Exchange → **the Market** | Un nombre por cosa |
| Logística (rama de tecnología) | **Transporte** | Logistics → **Transport** | — |
| Racionamiento, Fortificación, Supremacía Militar, Monopolio Comercial, Imperio Logístico, Red de Depósitos | Raciones Justas, Muros y Trincheras, Ejército Imbatible, Dueños del Mercado, Red de Transporte, Red de Almacenes | Rationing… → Fair Rations, Walls and Trenches, Unbeatable Army, Market Masters, Transport Network, Warehouse Network | Nombres que se entienden al leerlos |
| Industrialista, Mercader (logros) | Fabricante, Comerciante | (igual) | — |
| Alojamiento | Sitio para vivir | Housing → Room to live | — |
| Rangos: Intendente, Regidor, Superintendente, Prefecto, Comisario de Hierro, Procurador, Tribuno, Cónsul, Legado, Gran Canciller, Archigobernador | Jefe de taller, Alcalde, Ingeniero jefe, Comandante, Capitán de Hierro, General, Gran General, Almirante, Ministro, Gran Consejero, Gobernador Supremo (y Concejal en el 5) | Quartermaster… → Workshop chief, Mayor, Chief engineer, Commander, Iron Captain, General, High General, Admiral, Minister, High Councillor, Supreme Governor | Cargos que un chaval reconoce, de menos a más. Siguen Colono, Capataz, Maestro de obras, Gobernador, Virrey y Señor del Acero |
| Banderas: Aspa, Cuartelado, Cantón | Cruz en X, Cuatro cuartos, Esquina | Saltire, Quartered, Canton → X cross, Four quarters, Corner | Heráldica fuera |
| obreros | **trabajadores** | workers (igual) | Un solo nombre en todo el juego |

**Se quedan, explicados una vez:** **la Regencia** (en el prólogo, y en la primera tarjeta
del tutorial: "la Regencia, los que mandan en el Imperio"), **la Tormenta Imperial**, **el
Imperio**, **el Núcleo**. Y palabras de juego que ya conocen: oleada, botín, expedición,
moral, era, tablero.

**Cómo aplicarla:** al escribir un texto nuevo, mira esta tabla antes. Si una palabra no
está y dudas, pregúntate si la usaría un chaval de 12 años hablando con un amigo; si no,
busca la que usaría él. Los textos antiguos que ya no se ven en el juego
(`TUT_INTRO_*`, `TUT_PLAY_1/3/4_BODY`, `LBL_OBJ_STEP_*`) se pasaron por la tabla de forma
automática, sin reescribirlos a mano.

## 8. Las tres campañas (2026-10-18, rama `feat/tres-campanas`)

Textos en `Tr.gd`, bloque "# Tres campañas (feat/tres-campanas)", ES y EN, para
10-15 años: frases cortas, sin siglas.

- **Guía básica "Las tres campañas"** (`guide_campaigns`, categoría ejército,
  siempre en el índice de AYUDA): qué es cada campaña, con qué edificio se abre, que
  cada misión ganada trae botín y rebaja el Impuesto, que perder no la borra y que las
  tres (más el CG nivel 3) abren el Ataque Final.
- **Consejo `campaigns`**: sale al ganar la primera escaramuza (se abre la de
  Tierra). Mismo texto que la guía.
- **Consejo y guía `final_gate`** ("Qué pide el Ataque Final"): sale al llegar a la
  era 3 o cuando el CG llega a nivel 3 sin las campañas (con el aviso "Para llamar al
  Ataque Final falta: ..."). Escondido donde no hay asedio (`needs: final_audit`).
- Textos de antes que decían "el CG a nivel 3 llama al Ataque Final", corregidos:
  `TUT_TIP_AUDIT_BODY`, `HELP_TIP_AUDIT_BODY`, `MODE_CAMPAIGN_DESC`, `OBJ_WHY_HQ_3`,
  `HELP_B_GOAL`.
- En MISIONES cada candado dice qué hacer ("Cerrada. Construye: Astillero", "Esta
  misión llega en la era 3", "La tropa descansa. Lista en 1:20"), y la tropa que no
  vale sale apagada con su motivo ("No puede atacar a los enemigos de esta campaña").
- El tutorial guiado no cambia: termina antes de que las campañas importen.

## 9. Los instructores (2026-10-18, rama `feat/instructores`)

Bryan pidió un personaje de guerra caricaturesco que explique el tutorial, para que
se sienta más vivo. Son **dos, fijos**: una mujer para la colonia y un hombre para
el combate. Siempre el mismo para lo mismo: así el jugador aprende quién le habla de
qué.

| | Capitana **Ada Remache** | Sargento Mayor **Casimiro Bombarda** |
|---|---|---|
| Rango | Capitana de Ingenieros | Sargento Mayor |
| En inglés | Capt. Ada Rivet | Sgt. Casimir Bombard |
| Explica | La colonia: tutorial guiado de construcción, consejos de lo básico y de economía/edificios | El combate: combate guiado, consejos de Tormenta, Impuesto, ejército y misiones, y los partes de guerra |
| Aspecto (caricatura a color, 2026-10-26) | Gorra de plato de acero azul, ladeada, con las gafas de aviador sobre la copa y la rueda dentada de la colonia en la cinta; flequillo y trenza pelirrojos con pasador de latón; ojos verdes grandes, pecas; guerrera de acero azul cruzada y cerrada hasta el cuello alto, charreteras de latón con flecos de ámbar, la insignia de la rueda en el pecho, cinturón de cuero; la otra mano en la cadera | Veterano corpulento: casco de acero con cresta, banda remachada y estrella de latón; cejas de cepillo, nariz de patata colorada, bigote de manillar, barba de tres días, una cicatriz pequeña, mandíbula cuadrada y una cerilla apagada mordida en la comisura; capote oliva con solapas e insignias rojas, galones de ámbar en las mangas, dos medallas y cinturón sobre la barriga |
| En una línea | Lo arregla todo con una llave inglesa y una lista, y cree que una carretera bien puesta vale más que un cañón. | Grita como un cañón y se emociona como un niño; a los Cobradores de la Regencia les tiene una manía que no se le quita ni con té. |

Humor ligero, nunca cruel: se ríen de los Cobradores y de sí mismos, no del jugador.
Una derrota la comentan con ánimo y con la pista de qué hacer ("con más soldados en
casa...").

### Dónde salen

- **Tutorial guiado** (`TutorialPanel`): la Capitana junto a la tarjeta de latón. Cara
  por paso (`InstructorBust.expression_for_step`): saluda en la meta, señala en los
  pasos de tocar, contenta al esperar una obra, recoger o terminar, preocupada en
  "consigue lo que falta" y en la lección de reparar, enfadada (de broma) al derribar,
  sorprendida al girar.
- **Combate guiado** (misma tarjeta, sobre el tablero): el Sargento. Saluda al elegir
  la unidad, enfadado al atacar y defender, preocupado en el turno enemigo,
  sorprendido ante el círculo de ventajas, señala en el resto.
- **Tarjeta de consejo** (`HelperPanel`, la de abajo al centro): quien habla sale de la
  categoría de `HelpCatalog`: Tormenta y ejército → Sargento; lo básico y la economía
  → Capitana (`who_for_category`, `expression_for_category`). Los globos pequeños
  pegados a un control del HUD **no** llevan busto: no hay sitio y taparían el HUD;
  si un globo no cabe y sale en la tarjeta de abajo, entonces sí.
- **Partes de guerra** (`WarReportScreen`): el Sargento comenta cada parte con una
  frase, debajo de las cifras y firmada ("— Sargento Mayor Casimiro Bombarda"). Seis
  casos (defensa ganada/perdida, Impuesto rechazado/cobrado, Impuesto de prueba
  rechazado/cobrado), **tres frases cada uno**, que se turnan empezando en un sitio al
  azar (`WarReportScreen.QUOTE_CASES`, `quote_key`). Cara: saluda tras una defensa
  ganada, contento si echa a los Cobradores, enfadado si se llevan algo, preocupado en
  el de prueba.

Textos en `Tr.gd`, bloque "# Instructores (feat/instructores)", ES y EN:
`INSTR_COLONY_*`, `INSTR_COMBAT_*` (nombre, rango, nombre corto de la placa, lema),
`INSTR_SIGNED`, `INSTR_QUOTE_<CASO>_<1-3>` y `HUD_INSTRUCTORS`.

### Cómo se dibujan (`scripts/ui/InstructorBust.gd`)

Arte propio, dibujado por código como las láminas del prólogo (`PrologueEngraving`):
sin imágenes, escala sin pixelarse y no pesa en el APK. Nada de Empires & Allies ni
de otros juegos: Bryan mandó una referencia de **actitud** (oficial segura, con mando
y humor) y la Capitana es un diseño nuevo con piezas del mundo de la Tormenta.

**Caricatura a color** (rediseño del 2026-10-26, rama `feat/instructores-caricatura`;
sustituye al primer busto y al grabado a dos tintas que se descartó):

- **Trazo grueso de tinta** (`_ow`: el 2 % del alto, nunca menos de 1,2 px), **colores
  planos con una sola sombra** abajo a la derecha (`_shape(..., shade)`: el polígono
  menos él mismo desplazado arriba a la izquierda, con `Geometry2D.clip_polygons`) y
  **ojos grandes** con iris, pupila, brillo y párpado (`_eye`, `_eye_pose`).
- Los colores de la figura son los de la paleta base de la interfaz, fijos: guerrera de
  **acero azul** (`#2E4A5E` es su sombra), **latón** `#C99A45` en charreteras, botones,
  gafas e insignias, **ámbar** `#E5AE3E` en flecos, galones y la bandera. El fondo del
  marco es la **pizarra** con un sol de rayos: latón oscuro detrás de la Capitana (su
  azul resalta) y acero detrás del Sargento (su oliva resalta).
- Público de 10 a 15 años: proporciones de caricatura normales (cabeza grande,
  cuerpo corto), **uniforme cerrado** hasta el cuello, nada sexualizado. El Sargento no
  fuma: lleva una cerilla apagada mordida (un puro, aunque apagado, cuenta como tabaco
  en las clasificaciones por edad).
- Un **busto de medio cuerpo** dentro de un marco: la figura hasta el cinturón y una
  placa con el nombre corto ("Cap. Remache", "Sgto. Bombarda") con un remache a cada
  lado. El marco se pinta encima, así recoge lo que asome.
- **Seis expresiones** (`EXPRESSIONS`), cada una con su cara y su gesto de brazo; la
  otra mano siempre en la cadera:

| Cara | Capitana | Sargento |
|---|---|---|
| `happy` | Guiño y media sonrisa, sujeta la bandera de la colonia | Ojos de risa, pulgar arriba |
| `point` | Mira y señala la tarjeta con el índice | Igual |
| `worried` | Cejas arriba, se rasca la nuca, gotas de sudor | Igual |
| `angry` | Cejas abajo, párpado bajado, la llave inglesa en alto (de broma) y la vena | El puño que tiembla y la vena |
| `salute` | Mirada orgullosa, la mano en la visera | La mano en el ala del casco |
| `surprised` | Ojos redondos, boca en O, la palma abierta y rayas | Igual |

- **Boca que se mueve** mientras se escribe el texto: `speak(label)` escribe la
  etiqueta poco a poco (`visible_ratio` con un Tween, 60 letras/s, entre 0,5 y 2,4 s)
  con `VC_CHARS_AFTER_SHAPING`, para que la tarjeta no cambie de tamaño mientras se
  escribe. Mientras tanto un `Timer` de 0,11 s abre y cierra la boca (`_mouth_shape`:
  cerrada y abierta para cada cara; la cerilla del Sargento va con la boca).
- **Mira hacia la tarjeta**: a su izquierda mira a la derecha; a su derecha, se dibuja
  en espejo (`facing`).
- **Marco con UITheme**: borde de latón (Capitana) o de peligro aclarado (Sargento),
  más grueso en alto contraste, fondo, rayos y placa con los tokens. La figura usa su
  propia tinta: es ilustración, no da información por color, así que no cambia con
  las paletas de daltonismo.
- **Un solo retrato para todo**: las caras en círculo (`CartoonTheme.CaptainFace`, la
  `InstructorFace` de la 1.2, la maqueta) llaman a `_draw_ada` / `_draw_bombarda`, que
  pintan la misma figura con su boca y sin brazos (`draw_figure(ci, rect, quien, cara,
  con_boca, con_brazos)`). La cabeza sigue en el mismo sitio (centro en v ≈ 0,39), así
  que el recorte de esas caras no cambia.
- **Hoja de contacto**: `godot --path . -s tools/instructores_sheet.gd` (con ventana y
  un `override.cfg` propio) pinta en un `SubViewport` las seis caras de los dos a 2x,
  de serie, con la boca abierta, en espejo, a tamaño de teléfono y en círculo, en
  `docs/media/dev/instructores/hoja_contacto.png`. Copia del rediseño en
  `docs/media/instructores_caricatura.png`. La tarjeta del tutorial con cada cara:
  `tools/instructores_probe.gd -- --only=tutorial --shot-size=1280x720 --profile=pc`
  (o `640x360 --profile=phone`).

### Coste

- El cuerpo se pinta **solo** al cambiar de quién, de cara, de tamaño o de lado; Godot
  guarda las órdenes de dibujo. No hay `_process`.
- La boca es un nodo hijo aparte (`Mouth`): lo único que se repinta mientras habla,
  unas 10 veces por segundo durante como mucho 2,4 s. El `Timer` se para al callarse.
- Colocarlo (`dock_to`) son unas cuantas cuentas con `Rect2` en el `_process` que el
  tutorial ya tenía; en la tarjeta de consejo solo al moverse la tarjeta
  (`item_rect_changed`).

### Que no tape lo que se enseña (`InstructorBust.dock_rect`, pura)

El busto va **pegado a la tarjeta**: a su izquierda (alineado abajo) o, si no cabe, a
su derecha; si tampoco, asomando encima de la tarjeta, en una esquina. Prueba tres
tamaños (100 %, 80 %, 62 %) y si en ninguno cabe **se oculta**. Nunca sale de la
pantalla, nunca entra en la franja del HUD de arriba en el tutorial, y nunca pisa lo
que se evita: lo que el tutorial señala (con el ✓ de colocar), los avisos y la ficha de
unidad en el combate, y el control que señala el marco azul de un consejo. En un
teléfono (lienzo de menos de 900 × 560) parte del tamaño pequeño (88 × 110 en vez de
112 × 140).

### Ajuste

Ajustes > Interfaz > "Instructores (Remache y Bombarda)": la lista de elementos del HUD
que se ocultan (`HudRegistry`, id `Instructors`, modo `instructors`). Se guarda en
`settings.cfg` (`[ui] instructors_visible`, `GameConfig.ui_instructors_visible`),
nunca en la partida, y emite `EventBus.instructors_visibility_changed`. Apagados, los
textos salen enteros de golpe y los partes no llevan la frase del Sargento.

### Pruebas

`tests/ui/test_instructors.gd`: colocación (izquierda, derecha en espejo, sin tapar lo
señalado, teléfono, oculto si no cabe), caras de todos los pasos y consejos, todas las
caras de los dos se dibujan, hablar escribe y mueve la boca, apagado no escribe, textos
en los dos idiomas, las frases se turnan, el parte lleva su frase y el ajuste está en la
lista de Interfaz.

## 10. Estilo nuevo (rediseño fase 2, 2026-10-18, rama `feat/ui2-menus`)

La guía es `docs/28-guia-ui.md`; las piezas, `CartoonTheme` (sección "MENÚS").
Lo de arriba sigue valiendo en el **qué** y el **cuándo**; cambia el **cómo se ve**
y **cuánto texto** sale de una vez. Sin animaciones en ninguna de las tres piezas.

| | Antes | Ahora |
|---|---|---|
| **Prólogo** | Papel, máquina de escribir, el texto se escribía solo y el tampón caía | Folio crema con borde grueso (`CartoonTheme.window_style`) sobre la pizarra del HUD; título en Baloo 2 y texto en Nunito Sans; la nota a mano conserva su letra. El folio sale **entero, de golpe**: Siguiente pasa de folio al primer toque (`is_typing()` siempre falso). Atrás es un redondo con la flecha; Siguiente / Empezar, la pastilla verde. Las láminas (`PrologueEngraving`), el sello y el tampón no cambian. |
| **Guía rápida** | Cuatro bloques de texto largo | Cuatro tarjetas con icono, título y **una frase** (`UI2M_QG_*_S`); tocar una despliega el texto entero (`QG_*_B`) en la misma tarjeta. Ventana con cinta azul CÓMO SE JUEGA. |
| **Tutorial** | Tarjeta de latón sobre metal, marco que latía, texto escrito poco a poco | **Bocadillo** crema con tinta gruesa (`CartoonTheme.bubble_style`) y su **piquito** (`CartoonTheme.Tail`, colocado con `place_tail`) hacia el busto de la Capitana o del Sargento, como en la maqueta. Arriba la pastilla de latón "Paso N de M" (`Badge`); luego **una frase grande** (la primera línea de `compose_card_text`) y, en pequeño debajo (`Detail`), lo que falta y cómo conseguirlo. `coach_text()` devuelve las dos. Botón por intención: verde la acción (`GuideOk`, `CombatOk`), crema "Terminar repaso". Marco y aro de latón quietos. |
| **Consejos y globos** | Tarjeta azul acero con todo el texto | Bocadillo crema: [?] título, **la primera frase** (`HelpCallout.first_sentence`) y **Más** para desplegar el resto; desplegada, el reloj se para. ✕ roja redonda, barra de tiempo en azul. La tarjeta de consejo lleva el piquito hacia el busto. Sin fundido al salir. |
| **Índice de AYUDA** | Lista de botones de texto | Ventana con cinta azul AYUDA. Arriba, pastillas con icono (Cómo se juega, Edificios, Tutorial, Historia, Combate; el nombre largo al mantener pulsado) y la fila "Consejos solos" con su interruptor. Debajo, una cabecera con icono por categoría y una tarjeta por ayuda (✓ si ya se vio). Las **páginas** enseñan el primer párrafo entero y cada párrafo siguiente como una **sección** plegada (su primera frase; tocar despliega). `page_text()` sigue devolviendo el texto entero. |
| **Guía de edificios** | Lista de líneas de texto | Una tarjeta por edificio: nombre y tamaño, costes como icono + cifra (`cost_chip`), trabajadores, y la línea pequeña de topes y requisitos (`GuideRules`). La descripción, al mantener pulsado. |

Los instructores ya **no hablan escribiendo** desde estas tarjetas (ni `speak()` ni la
boca que se mueve): ponen la cara del paso y el texto sale entero. `InstructorBust.speak`
sigue existiendo para quien lo use (los partes de guerra, de otro frente).
