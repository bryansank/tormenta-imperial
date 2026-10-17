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
generado (`UITheme.parchment_texture`).

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
siguen en el índice de AYUDA (`guide_qg_*`) y el nodo existe (`TutorialPanel.open_quick_guide()`)
por si se quiere volver a ofrecer. Un `quick_guide` en `helps_seen` de una partida vieja
se carga y no cambia nada. Lo que sigue describe la pantalla.

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

Coach marks sobre la interfaz real. Cada paso:

- **oscurece** la pantalla menos el control del que habla, con un marco de latón que
  late (el velo es `MOUSE_FILTER_IGNORE`: se puede tocar todo, también fuera de orden);
- **señala** con una flecha;
- pone **una línea** de lo que hay que hacer, con "TUTORIAL · PASO n DE 12"; debajo,
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
derribar** un edificio. Doce pasos:

| # | Paso (`GUIDE_STEPS`) | Señala | Avanza cuando | Qué explica |
|---|---|---|---|---|
| 1 | `goal` (tarjeta de leer) | nada: tarjeta abajo al centro | botón **¡A por ello!** (`confirm_step`, hecho `goal_seen`) | **La meta**: 3 eras, Cuartel General a nivel 3, aguantar el Ataque Final de la Regencia, y la Tormenta se detiene para siempre |
| 2 | `core` (tarjeta de leer) | un aro sobre el Núcleo | botón **Entendido** (hecho `core_seen`) | **Núcleo**: el corazón de la isla; todo va unido a él por carretera. Cifras: +5 viven aquí |
| 3 | `open_build` / `pick_sawmill` / `place_sawmill` / `wait_sawmill` | CONSTRUIR, la tarjeta, el bosque más cercano, la obra | se abre la lista, se elige, se coloca, acaba la obra | **Aserradero**: corta madera; casi todo se construye con ella. En la espera, **la carretera**: llega sola desde el Núcleo y sin ella un edificio no trabaja |
| 4 | `collect` | el aserradero | se recoge algo (`note_guide_fact("collected")`) | recoger lo producido |
| 5 | `open_farm` / `pick_farm` / `place_farm` | CONSTRUIR, la tarjeta de la Granja | se coloca una granja | **Granja**: comida; tu gente come cada poco |
| 6 | `rotate` / `rotate_pick` / `rotate_now`, y luego `place_house` | CONSTRUIR, la tarjeta de la Casa, y con la Casa en la mano el botón **R ↻** de la pantalla (tablet y móvil; en PC no hay botón: es la tecla R) | **gira** el edificio en la mano (`building_rotate_requested`, hecho `rotated`) y después se coloca la casa | **Girar**: R en PC, R ↻ con el dedo; un cuarto de vuelta cada vez. **Casa**: aquí vive tu gente, +6 trabajadores |
| 7 | `move` / `move_place` | MOVER en la ficha si está abierta (`info_move`); si no, la Casa en el mapa (`built:house`) | se mueve cualquier edificio (`building_moved`, hecho `moved`) | **Mover**: gratis, conserva el nivel |
| 8 | `road_open` / `road_pick` / `road_place`, y `demolish` | CONSTRUIR, la tarjeta de la Carretera; después Confirmar, DEMOLER o el tramo puesto (`info_demolish_confirm\|info_demolish\|practice_road`) | se pone a mano un tramo de carretera (1 oro, hecho `road_placed`) y se derriba algo (`building_demolished`, hecho `demolished`) | **Derribar**: devuelve la mitad de lo que costó; el Núcleo y la carretera que une edificios no se quitan. Se practica con 1 oro: no se pierde nada importante |
| 9 | `open_gold_mine` / `pick_gold_mine` / `place_gold_mine` | CONSTRUIR, la tarjeta, la veta de oro más cercana (`deposit:gold_vein`) | se coloca una mina | **Mina de oro**: oro de una veta; paga edificios y soldados |
| 10 | `open_market` / `pick_market` / `place_market` | CONSTRUIR, la tarjeta del Mercado | se coloca un mercado | **Mercado**: vende lo que sobra, compra lo que falta |
| 11 | `open_warehouse` / `pick_warehouse` / `place_warehouse` | CONSTRUIR, la tarjeta del Almacén | se coloca un almacén | **Almacén**: más sitio; lo que no cabe se pierde. Cifras: +500 de almacén |
| 12 | `open_laboratory` / `pick_laboratory` / `place_laboratory` | CONSTRUIR, la tarjeta del Laboratorio | se coloca un laboratorio | **Laboratorio**: mejoras para siempre (más producción, más sitio, obras más rápidas) |
| — | `done` | ¿QUÉ HACER? | "Entendido" o 25 s | **La meta otra vez**, en una línea, y que ¿QUÉ HACER? dice el paso siguiente |

El orden de los edificios sigue la línea de ¿QUÉ HACER? (`Objectives.LINE`: aserradero,
granja, mina, casa, mercado, almacén); la casa va antes de la mina porque la mina pide 3
trabajadores y el Núcleo solo da sitio a 5. El Laboratorio va el último: no está en la
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
| Tope de edificios (un repaso con los 5 aserraderos; el Mercado y el Laboratorio, únicos) | Se pasa de largo (`goal_impossible_reason` = `limit`; también `prereq` y `rank`) | `the_building_limit_reached` |
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
  tutorial, Historia.
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
| `tests/tutorial/test_prologue_screen.gd` | 4 folios, Atrás/Siguiente/Saltar, Siguiente×2 + Atrás = folio 2, Atrás apagado en el primero, deslizar, máquina de escribir, pausa, variantes, textos ES/EN, estilo propio; la hoja final (última, Empezar, el plan en palabras llanas ES/EN sin botones, teclado y deslizar) |
| `tests/tutorial/test_guide_steps.gd` | *(2026-10-16, sin correr aún: la meta y el Núcleo, girar/mover/derribar, los edificios del principio)* `derive_step`, recorrido entero, cancelar, saltar (API interna), fuera de orden, isla hecha, repetir, reanudar al cargar, guardado y basura |
| `tests/tutorial/test_guide_never_stuck.gd` | *(2026-10-16, sin correr aún: tarjetas de leer, cifras con iconos, "cómo conseguirlo", sin veta de oro, partida vieja, la lección de reparar)* sin "Saltar" (solo dev), repetir no salta, terminar un repaso, guardados saltados; un test por caso de atasco (§2.1); la granja y recoger entre aserradero y casa (§2.3) |
| `tests/tutorial/test_tutorial_panel.gd` | *(2026-10-16: el botón de las tarjetas de leer y la fila de cifras)* prólogo alojado, paso con texto y número, el velo no se come toques, sin botón de saltar, "Terminar repaso" solo en un repaso, esconderse en pausa y con el prólogo, la tarjeta no tapa lo señalado |
| `tests/tutorial/test_tutorial_manager.gd` | consejos una vez, prólogo pendiente hasta poder salir, modos, reset y guardado |
| `tests/ui/test_helper_callouts.gd` | una a la vez, ✕ y vista, reloj y pausa con el dedo, prioridad, silencios, interruptor, reabrir pedida |
| `tests/ui/test_helper_skirmish_callout.gd` | el globo de MISIONES sigue a su botón y sale una vez |
| `tests/tutorial/test_first_sortie_tip.gd` | el consejo `first_sortie` sale con la primera unidad (antes que el sueldo) y una vez, señala ☰ MENÚ, textos ES/EN con `_TOUCH`; la marca `first_sortie_done` solo con una victoria, guardado idempotente, `reset()` y guardados viejos |
| `tests/ui/test_help_index.gd` | grupo `help_index`, lista básicas y vistas, modo Constructor, reabrir |
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
