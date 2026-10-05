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

El lore contado como el **expediente 114-B de la Regencia** sobre nuestra isla. El texto
oficial va a máquina (Special Elite); en el margen, a mano y en tinta azul (Caveat), las
notas de los Amortizados cuentan lo que el papel calla ("El Perpetuo está muerto, y el
sello sigue bajando"). La portada lleva el tampón **DADO DE BAJA** y el último folio
**REABIERTO**; cada folio, el sello de lacre con "NADA SE PIERDE" (`RegenciaSeal.gd`,
dibujado, sin imagen). El papel y la mesa son ruido generado (`UITheme.parchment_texture`).

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
| Campaña, Supervivencia | Completo, 3 folios (quiénes somos, la Tormenta y el Diezmo, la reapertura) |
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

---

## 2. Tutorial guiado (`scripts/ui/TutorialPanel.gd`)

Coach marks sobre la interfaz real. Cada paso:

- **oscurece** la pantalla menos el control del que habla, con un marco de latón que
  late (el velo es `MOUSE_FILTER_IGNORE`: se puede tocar todo, también fuera de orden);
- **señala** con una flecha;
- pone **una línea** de lo que hay que hacer, con "TUTORIAL · PASO n DE 5" y
  `Saltar tutorial`. La tarjeta va junto a lo señalado (debajo si cabe, si no encima),
  nunca encima.

| # | Paso (`GUIDE_STEPS`) | Señala | Avanza cuando |
|---|---|---|---|
| 1 | `open_build` | CONSTRUIR, el botón grande de abajo, siempre a la vista (grupo `hud_build_button`) | se abre `ConstructionMenu` |
| 2 | `pick_sawmill` | la tarjeta del Aserradero dentro de la lista | se elige el aserradero para colocar |
| 3 | `place_sawmill` | un aro sobre el bosque más cercano (flecha al borde si no se ve); con el dedo conviven con las casillas verdes de `PlacementAssist` (docs/21 §9) | se coloca: con ratón, clic; con el dedo, tocar la casilla y ✓ CONSTRUIR AQUÍ (o el fantasma) |
| 4 | `wait_sawmill` | un aro sobre la obra | termina la obra (los obreros llegan solos) |
| 5 | `open_house` / `pick_house` / `place_house` | CONSTRUIR, la tarjeta de la Casa | se coloca una casa |
| — | `done` | el objetivo | "Entendido" o 10 s |

**El paso se deduce, no se cuenta.** `TutorialManager.derive_step(hechos)` es pura:
aserraderos (en obra y hechos), casas, lista de construir abierta, qué se tiene en la
mano. Por eso:

- **Fuera de orden** no se rompe: si coloca una casa primero, sigue pidiendo el
  aserradero y luego ya no pide la casa. Si cancela, vuelve un paso.
- **Al cargar** vuelve donde estaba: el estado `active` está en la partida y el paso sale
  de lo construido.
- **Partida vieja:** con aserradero y casa ya hechos se da por hecho sin enseñar nada;
  quien vio la intro vieja (que traía "Cómo se juega") no lo repite.
- **Repetir tutorial** (índice de AYUDA) cuenta desde lo que hay (`guide_baseline`): pide
  un aserradero más.

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
   de uno en uno (y si lo salta, primero el de construir). El de ESCARAMUZAS sale cuando
   aparece su botón. Los consejos, cuando pasa lo que explican.
5. **Se callan y vuelven** sin contar como vistas: con una ventana abierta, en pausa, con
   el índice de AYUDA abierto, colocando con el dedo y, los globos, con la Tormenta
   encima. Los consejos no se callan por la Tormenta: la explican.
6. **Sin sitio junto a su control** (tablet con la columna central bajada, pantalla
   estrecha) el globo sale en la tarjeta de abajo, y un marco azul señala el control.
7. **Interruptor global** (`GameConfig.ui_helper_visible`, el de Ajustes > Interfaz de
   #29 y el del índice): apaga las que salen solas; las que se piden en el índice salen
   igual.

**La primera escaramuza** (docs/15-combat.md §4). Al salir del cuartel la primera
unidad, el consejo `first_sortie` señala ☰ MENÚ (donde vive ESCARAMUZAS) y ¿QUÉ HACER?
pide "Lanza tu primera escaramuza" antes de la guarnición. La marca
`TutorialManager.first_sortie_done` (en la partida) se pone al ganar una salida; hasta
entonces cada salida es un solo nodo fácil con botín. El globo antiguo
`callout_skirmish` sigue atado al botón de la columna lateral, que ya no se abre desde
que ESCARAMUZAS pasó al menú ☰: en la práctica no sale.

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
| `tests/tutorial/test_prologue_screen.gd` | Atrás/Siguiente/Saltar, Siguiente×3 + Atrás = folio 2, Atrás apagado en el primero, deslizar, máquina de escribir, pausa, variantes, textos ES/EN, estilo propio |
| `tests/tutorial/test_guide_steps.gd` | `derive_step`, recorrido entero, cancelar, saltar, fuera de orden, isla hecha, repetir, reanudar al cargar, guardado y basura |
| `tests/tutorial/test_tutorial_panel.gd` | prólogo alojado, paso con texto y número, el velo no se come toques, saltar, esconderse en pausa y con el prólogo, la tarjeta no tapa lo señalado |
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
salta y fotografía un globo, un consejo, el índice y una ayuda reabierta. Capturas en
`docs/media/dev/onboarding/` (ignorada por git).

## 6. Lo que queda

- El globo de cámara no sabe si el jugador ya movió la cámara: sale igual, una vez.
- El bosque que se señala es el más cercano al centro de la pantalla; puede caer bajo la
  cruceta en tablet.
- (Resuelto en la integración con el menú único: CONSTRUIR está siempre abajo y el
  paso 1 lo señala a él; ya no hay texto "abre ☰".)
