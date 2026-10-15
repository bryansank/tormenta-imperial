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
(`UITheme.hand_font()`), una nota de los Amortizados (`PRO_<n>_NOTE`). El primer folio
lleva el tampón **FIRMADO** y el tercero **VIVOS** (la hoja final no lleva tampón); cada folio, el sello de lacre con
"NADA SE PIERDE" (`RegenciaSeal.gd`, dibujado, sin imagen). El papel y la mesa son ruido
generado (`UITheme.parchment_texture`).

| Folio | Título | Qué cuenta |
|---|---|---|
| 1 | La firma del Emperador | El Imperio manda en casi todo el mundo; el Emperador lleva un siglo muerto y la Regencia firma por él |
| 2 | La Tormenta | La ceniza que manda el Imperio, los Tasadores y el Diezmo |
| 3 | Quiénes somos | Los Amortizados, la isla dada por perdida, y lo que vamos a hacer: construir, aguantar y no pagar |
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
- pone **una línea** de lo que hay que hacer, con "TUTORIAL · PASO n DE 7", y debajo
  **lo que falta** si algo lo impide. La tarjeta va junto a lo señalado (debajo si cabe,
  si no encima), nunca encima.

**No se salta** (decisión de Bryan, 2026-10-04). La tarjeta ya no tiene `Saltar
tutorial`: el tutorial de una partida nueva se hace entero. `TutorialManager.skip_guide()`
queda como API interna para sondas y pruebas, y fuera de `GameConfig.dev_mode` no hace
nada. Los guardados con el tutorial ya saltado (`"skipped"`) o hecho cargan igual. El
**repaso** que se pide en AYUDA > Repetir tutorial (`replay_guide()`) sí tiene `Terminar
repaso` (`stop_replay()`): lo pidió el jugador. Con el tutorial de verdad aún en marcha,
Repetir tutorial no hace nada (si no, sería la forma de saltarlo).

| # | Paso (`GUIDE_STEPS`) | Señala | Avanza cuando |
|---|---|---|---|
| 1 | `open_build` | CONSTRUIR, el botón grande de abajo, siempre a la vista (grupo `hud_build_button`) | se abre `ConstructionMenu` |
| 2 | `pick_sawmill` | la tarjeta del Aserradero dentro de la lista | se elige el aserradero para colocar |
| 3 | `place_sawmill` | un aro sobre el bosque más cercano (flecha al borde si no se ve); con el dedo conviven con las casillas verdes de `PlacementAssist` (docs/21 §9) | se coloca: con ratón, clic; con el dedo, tocar la casilla y ✓ CONSTRUIR AQUÍ (o el fantasma) |
| 4 | `wait_sawmill` | un aro sobre la obra | termina la obra (la carretera se tiende sola y los trabajadores llegan andando) |
| 5 | `collect` | el aserradero (su icono flotante sale cuando ha producido) | se recoge algo (`EventBus.production_collected` → `note_guide_fact("collected")`) |
| 6 | `open_farm` / `pick_farm` / `place_farm` | CONSTRUIR, la tarjeta de la Granja | se coloca una granja (sin esperar a la obra) |
| 7 | `open_house` / `pick_house` / `place_house` | CONSTRUIR, la tarjeta de la Casa | se coloca una casa |
| — | `done` | ¿QUÉ HACER? (su entrada del ☰ MENÚ, o el botón ☰ MENÚ) | "Entendido" o 10 s |

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
(`GUIDE_PRESS_BUILD`). La tarjeta pedida (la Vivienda es la última de la lista) se
desplaza sola a la vista. Con otra ventana abierta encima (Tecnología, Mercado...) la
marca no se pinta; con CONSTRUIR sí, porque los pasos ocurren ahí dentro.

### 2.1 Que ningún paso se atasque

Sin botón de saltar, ningún paso puede quedarse pidiendo algo imposible. Cada segundo
(`GUIDE_CHECK_SECONDS`), con el tutorial activo, `TutorialManager` repasa las metas:

| Caso | Qué hace | Prueba (`tests/tutorial/test_guide_never_stuck.gd`) |
|---|---|---|
| Sin bosque al que llegar (agotado, tapado, sin carretera posible) | La meta del aserradero se pasa de largo (`has_reachable_deposit`, en los dos giros) y pide la casa. Si vuelve a haber sitio, la vuelve a pedir | `no_reachable_forest`, `no_forest_at_all`, `a_forest_lost_mid_guide` |
| Mapa aún sin sortear | No se salta nada a ciegas | `a_map_not_drawn_yet` |
| Tope de edificios (un repaso con los 5 aserraderos) | Se pasa de largo (`goal_impossible_reason` = `limit`; también `prereq`) | `the_building_limit_reached` |
| Paso ya cumplido antes de llegar | El paso sale de lo construido: no lo pide | `a_step_already_done`, `a_sawmill_built_before` |
| Faltan recursos | Debajo del paso, "Te falta: 70 oro \| 50 madera" (`step_hint` con `OBJ_MISSING`, ≤ 8 palabras: el aserradero y la casa solo cuestan oro y madera) | `short_of_resources`, `the_panel_shows_the_missing_line` |
| Faltan obreros | "Faltan obreros: construye antes una Vivienda." (`GUIDE_NEED_WORKERS`); la casa no pide obreros | `short_of_workers` |
| Táctil | Todos los pasos tienen texto con el dedo; lo que falta se dice igual | `touch_steps_all_resolve` |
| Vista 2D | El bosque se busca en el generador registrado (`GameManager.map_generator()`, también `MapGenerator2D`) y su punto sin Camera3D | `the_2d_view_finds_the_forest_too` |

Las metas imposibles (`blocked_goals()`) no se guardan: se recalculan al cargar y cada
segundo. La obra (`wait_sawmill`) no puede atascarse: termina por tiempo.

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
Auditoría. Se esconde durante el prólogo, la pausa, el menú principal y el tablero.

---

## 3. Ayudas (`HelperPanel`, `HelpCallout`, `HelpCatalog`)

`HelpCatalog` es la lista de todas: los globos del HUD (`callout_*`), los consejos de
`TutorialManager.TIPS` y las guías básicas (`guide_*`, lo que eran las páginas "Cómo se
juega"). Cada una tiene id, categoría, título, texto (`Tr.ti`) y el control al que
apunta.

**Reglas:**

1. **Una a la vez.** Cola por prioridad (`HelpCatalog.priority`): los consejos de algo
   que acaba de pasar (100) van delante; luego ESCARAMUZAS, construir, objetivo,
   recursos, cámara, zoom y menú. Entre dos que salen solas hay 1,2 s de respiro.
2. **Cada una con ✕ y cierre solo:** de 6 a 12 s según el largo del texto
   (`auto_close_seconds`), con una barra fina que se vacía. El reloj se para mientras el
   dedo está apoyado encima o el ratón pasa por encima.
3. **Cerrada o agotada, vista** (`TutorialManager.helps_seen`, en la partida). No vuelve
   a salir sola.
4. **Contextual:** nada sale durante el tutorial guiado. Al terminarlo salen los básicos
   de uno en uno (y si se saltó, solo posible con la API interna, primero el de construir). El de ESCARAMUZAS sale cuando
   aparece su botón. Los consejos, cuando pasa lo que explican.
5. **Se callan y vuelven** sin contar como vistas: con una ventana abierta, en pausa, con
   el índice de AYUDA abierto, colocando con el dedo y, los globos, con la Tormenta
   encima. Los consejos no se callan por la Tormenta: la explican.
6. **Sin sitio junto a su control** (tablet con la columna central bajada, pantalla
   estrecha) el globo sale en la tarjeta de abajo, y un marco azul señala el control.
7. **Interruptor global** (`GameConfig.ui_helper_visible`, el de Ajustes > Interfaz de
   #29 y el del índice): apaga las que salen solas; las que se piden en el índice salen
   igual.
8. **Cortos** (2026-10-04): un globo está junto a su control, así que no lo describe
   ("CONSTRUIR (el botón grande de abajo)" sobraba). Cada globo, en 14 palabras como
   mucho, con su `_TOUCH` (`test_menos_texto_avisos.gd`). El de ☰ MENÚ ya no nombra
   Mercado ni Tecnología, que se abren desde sus edificios. Las explicaciones que los
   paneles mandan al tooltip (descripción del edificio, regla de la carretera, intro
   del árbol tecnológico) siguen en la guía rápida, la guía de edificios y los
   consejos del índice: en táctil es donde se leen (docs/21 §6, "Menos texto").

**La primera escaramuza** (docs/15-combat.md §4). Al salir del cuartel la primera
unidad, el consejo `first_sortie` señala ☰ MENÚ (donde vive ESCARAMUZAS) y ¿QUÉ HACER?
pide "Lanza tu primera escaramuza" antes de la guarnición. La marca
`TutorialManager.first_sortie_done` (en la partida) se pone al ganar una salida; hasta
entonces cada salida es un solo nodo fácil con botín. El globo antiguo
`callout_skirmish` sigue atado al botón de la columna lateral, que ya no se abre desde
que ESCARAMUZAS pasó al menú ☰: en la práctica no sale.

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

### Índice de AYUDA (`scripts/ui/HelpIndexPanel.gd`)

- Grupo **`help_index`**, método **`open()`**: el menú ☰ único lo abre con
  `get_tree().get_first_node_in_group("help_index").open()`. Lo crea `HelperPanel`.
- Arriba: el interruptor "Mostrar ayudas en pantalla", GUÍA DE EDIFICIOS, Repetir
  tutorial, Historia.
- Debajo, por categoría (Primeros pasos · Economía · Tormenta y Diezmo · Ejército y
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
| `tests/tutorial/test_guide_steps.gd` | `derive_step`, recorrido entero, cancelar, saltar (API interna), fuera de orden, isla hecha, repetir, reanudar al cargar, guardado y basura |
| `tests/tutorial/test_guide_never_stuck.gd` | sin "Saltar" (solo dev), repetir no salta, terminar un repaso, guardados saltados; un test por caso de atasco (§2.1); la granja y recoger entre aserradero y casa (§2.3) |
| `tests/tutorial/test_tutorial_panel.gd` | prólogo alojado, paso con texto y número, el velo no se come toques, sin botón de saltar, "Terminar repaso" solo en un repaso, esconderse en pausa y con el prólogo, la tarjeta no tapa lo señalado |
| `tests/tutorial/test_tutorial_manager.gd` | consejos una vez, prólogo pendiente hasta poder salir, modos, reset y guardado |
| `tests/ui/test_helper_callouts.gd` | una a la vez, ✕ y vista, reloj y pausa con el dedo, prioridad, silencios, interruptor, reabrir pedida |
| `tests/ui/test_helper_skirmish_callout.gd` | el globo de ESCARAMUZAS sigue a su botón y sale una vez |
| `tests/tutorial/test_first_sortie_tip.gd` | el consejo `first_sortie` sale con la primera unidad (antes que el sueldo) y una vez, señala ☰ MENÚ, textos ES/EN con `_TOUCH`; la marca `first_sortie_done` solo con una victoria, guardado idempotente, `reset()` y guardados viejos |
| `tests/ui/test_help_index.gd` | grupo `help_index`, lista básicas y vistas, modo Constructor, reabrir |
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
