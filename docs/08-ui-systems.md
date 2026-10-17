# UI Systems

## Overview

All UI is built programmatically in GDScript (no Godot editor UI design). Each panel is a CanvasLayer with a script that constructs its own widgets in `_setup_ui()`.

## UI Panels

### ResourceHUD (`scripts/ui/ResourceHUD.gd`)
- **Position:** Top-left card (slot `top_left`)
- **Shows:** one row of `[icon] number` chips, with no names written beside them: the unlocked resources (gold, wood, then steel/oil), the **free workers** and, once the Imperial Storm is armed, the **morale**. Under it, ONE shared storage bar with `500/600` at its right, no title.
- **Workers chip** (2026-10): the number is the workers that are free for the next building (`population - used`). Inhabitants, cap, working and withdrawn go to the tooltip. It turns `UITheme.WARNING` when a building is left without workers (`PopulationManager.get_understaffed_count()`). Follows `workers_changed` / `population_changed`.
- **Morale chip** (2026-10): hidden until the Storm cycle is armed (`ResourceHUD.morale_visible()` = `StormManager.is_armed() or is_halted()`; never in Constructor, where the Storm does not run). Number coloured by threshold (`POSITIVE` > 60, `WARNING` 31-60, `DANGER` ≤ 30); the tooltip says what it does (output multiplier, nobody is born below 30). Re-derived on `phase_advanced`, every `storm_*` signal, `game_load_completed` and `game_new_started` (deferred, after StormManager).
- **Behavior:** Resource values update in real-time via `EventBus.resource_changed`. Every chip has its meaning in a tooltip. Touch has no tooltips in Godot, so a tap (or click) on any chip or on the storage row unfolds the detail: a row per resource with name, amount and the colour swatch that is the legend of the bar, the workers and morale lines (same text as their tooltips) and the shared-cap explanation; another tap folds it. There is no ▼ button any more. With touch controls on, chips are at least `UITheme.MIN_BTN_H` tall. The row is an `HFlowContainer` that wraps before the ☰ MENÚ button when they would meet (phone in portrait). The bar turns red when full. Animates glow when a new resource unlocks.
- **Materials row** (2026-09-28): the workshop materials (planks, ingots, beams, fuel), outside the shared bar; the row appears once one material is unlocked or held. No "TALLER" title since 2026-10 (it is in the tooltip).
- **Layer:** 10

### ConstructionMenu (`scripts/ui/ConstructionMenu.gd`)
- **Position:** Bottom center: a big CONSTRUIR button (240x64, brass border), ALWAYS visible — it used to appear only while the ☰ column was open
- **Shows:** Scrollable list of all non-core buildings from `data/buildings/` (15 cards), with a category filter; the category colour is only the stripe of each card (docs/24)
- **Behavior:** Each card shows its cost as a row of resource icons with their amounts (`TextKit.cost_row`), only the missing amounts in red. Cards are picked on release inside them, and locked ones can be tapped too: the detail says what is missing. The cost sits at the top of the detail, before the preview, again as icons; production reads "+5 [steel] every 15 s"; workers, housing, morale and requirements share one line. When something blocks the build it is said next to the button in short (`PlacementRules.block_reasons_short`: "Bloqueado: vigas", "Antes: Refinería", "Te falta: 20 madera") and the button does not start; the full version (how each resource unlocks) is its tooltip. The road rule is one short line ("Carretera al Núcleo (1 oro por tramo)", full sentence as tooltip); size and description are the tooltip of the name. Columns follow the width. Rebuilds when resources unlock.
- **Placing:** one building per placement — after it, placement mode ends; only decorations, roads and `repeat_placement` buildings stay in hand (`PlacementRules.keeps_placing()`).
- **Layer:** 12
- **Rank locks:** a building gated by the governor rank (decorations) shows a drawn padlock and "Rango N" instead of its cost; the detail says "Necesitas rango N" (`PlacementRules.check_rank()`)

### BuildingInfoPanel (`scripts/ui/BuildingInfoPanel.gd`)
- **Position:** Right side, full height
- **Shows:** Selected building/deposit details
- **Sections:** Title (description in its tooltip), "Nv 1 · 2 trabajadores", production "+6 [wood] every 12 s", construction progress ("En obras 61% · 0:16"), upgrade button "MEJORAR → Nv 2" with what the next level gives and its cost as icons (only on buildings whose upgrade does something), repair with its cost as icons, process actions (via ProcessActionsPanel; the "Acciones" header only when there are any), move (what it does is its tooltip) / demolish, demolish confirmation
- **RETIRAR / PONER TRABAJADORES** on every building that uses workers, with a short state ("2 trabajando", "Parado por ti", "Sin veta: no produce"); the full explanation is the button's tooltip
- **ABRIR MERCADO / INVESTIGAR** on the Market and the Laboratory (`SCREENS`): the only way to open `MarketPanel` and `TechTreePanel`; disabled while the building has no road
- **Deposits:** uses left and one short line ("A mano se agota; con Aserradero al lado, no"); the long difference between mining by hand and its specialised building is the tooltip
- **Layer:** 10

### ProcessActionsPanel (`scripts/ui/ProcessActionsPanel.gd`)
- **Type:** Helper class (not a scene, instantiated by BuildingInfoPanel)
- **Shows:** Available manual processes for selected building, or the mining card for deposits. Since 2026-10-14 each one is a `ProcessCard` (`scripts/ui/ProcessCard.gd`), icons and numbers before words: name with time and, for hand mining, [worker icon] 2 on the right; then `[wood] 20 → +5 tablones` as icon rows (`TextKit.cost_inline`, product in green); "✖ reason" only when it cannot start; and a row of finger-sized batch buttons **×1 · ×5 · MÁX ×N** (`UITheme.touch_px`). The plain-text line ("20 madera → +5 tablones · 30 s · 2 trabajadores") is the card's tooltip (hold to read on tablet).
- **The Núcleo** shows three groups, each with a short dim header: **Del Núcleo** (its own processes), **Como en los talleres · tarda más** (every workshop recipe already unlocked) and **Sacar a mano · tarda más** (hand mining of each unlocked resource). The tooltip of a copied card says where it comes from ("Lo mismo que en: Aserradero. Aquí tarda más."). Rule in docs/02 §"El Núcleo, taller de todo".
- **Behavior:** Hides processes that use locked resources. Shows progress bar during active process ("Talar · 0:16"; a batch: "Talar · 2 de 5 · 1:40", time to finish the whole batch) and "Cancelar (vuelven 7 madera)" (the refund of everything paid and not delivered); the normal cancel rate is the button's tooltip, the Storm rate (it costs double) stays visible in red. Disables the batch buttons while something runs here or the building is under construction; ×5 is off when fewer than 5 can be paid or stored, MÁX when fewer than 2. What a card can afford is recalculated at most every 300 ms (`REFRESH_MS`), never rebuilt per frame. BuildingInfoPanel was not touched: it still calls `populate_building` / `populate_deposit` / `update_progress`.

### MarketPanel (`scripts/ui/MarketPanel.gd`)
- **Position:** Center overlay, opened from a Market building (ABRIR MERCADO in its BuildingInfoPanel); no menu entry since 2026-09-28
- **Shows:** One row per unlocked resource: its icon (name in the tooltip), buy/sell prices, amount selector (+-5), buy/sell buttons; the gold balance as icon + number
- **Behavior:** Prices update via `EventBus.market_prices_updated`. Rebuilds when resources unlock.
- **Layer:** 11

### ProgressPanel (`scripts/ui/ProgressPanel.gd`)
- **Position:** Center overlay, opened from ☰ MENÚ → COLONIA → Progreso
- **Shows:** Current era, progress bar, 9 milestones with [X]/[ ] checkmarks
- **Behavior:** Updates checkmarks on milestone completion. Milestone and era toasts go through a queue: one plate at a time at 30 % of the screen height, away from the centre column (they used to stack on top of each other and of the objective).
- **Layer:** 11

### VictoryScreen (`scripts/ui/VictoryScreen.gd`)
- **Position:** Center overlay (full screen)
- **Shows:** "VICTORIA IMPERIAL" title, flavor text, stats, continue/new game buttons
- **Trigger:** `EventBus.victory_achieved` (opens at once; the offline report it used to wait for is gone). "Nueva partida" goes through `GameManager.request_new_game()`
- **Layer:** 20

### TitleMenu (`scripts/ui/TitleMenu.gd`)
- **Shows:** keyart background (logo + name on portrait), Continuar (the last game played, only if a save was loaded or the player already played this session, and not a sealed run), Nueva partida (via `GameManager.request_new_game()`; never deletes, it creates another game), PARTIDAS n/5 (the saved-games list, `SavesPanel`), Ajustes, Salir
- **Behavior:** opens on launch over the already-loaded game and pauses the tree (`get_tree().paused`). Skipped headless and with `-- --no-title` (probes). Shown once per session (static flag survives the new-game reload)
- **Layer:** 30, `PROCESS_MODE_ALWAYS`

### PauseMenu (`scripts/ui/PauseMenu.gd`) — THE game menu
There is ONE menu (it replaced the "II" pause button and the ☰ sidebar, which
lived in opposite corners and overlapped). The node is still called `PauseMenu`.
- **Button:** "☰ MENÚ", top-right, finger-sized, always visible in play (hidden while the menu itself is open). No other menu button exists; the old sidebar buttons of each panel stay hidden (nobody emits `sidebar_toggled(true)` any more)
- **Card:** title, "Modo: X" (only when the run is not Campaña, 2026-10-04), and two groups side by side (one column with scroll below 700 px). Each group's sentence ("Los paneles de tu isla...", "La isla espera...") is the tooltip of its header:
  - **COLONIA** — ¿Qué hacer?, Progreso, Colonia (rank, flag and colour: `RankPanel`), Ejército and Escaramuzas (with a Barracks), Sandbox (in Sandbox mode), Registro (the activity log). Mercado and Tecnología left the menu on 2026-09-28: they open from their buildings. Only what is available is shown, so no gaps. Picking one closes the menu, unpauses and opens that panel (`open_colony_panel`)
  - **PARTIDA** — Reanudar, Guardar, Ajustes, Música sí/no, Ayuda (only if a node in group `help_index` exists; calls its `open()`), Informar de un fallo (copies `BugReport.build()` to the clipboard and says "Copiado. Pégalo en un mensaje." under the groups; nothing leaves the device, docs/19 §7), Historia (closes the menu, then `TutorialManager.show_prologue()` replays the prologue, docs/23), Menú principal, Guardar y salir
- **Speed button:** `PauseMenu._ready()` adds `GameSpeedButton` (x1 / x2, key F) as its sibling, so both views get it without touching the scenes (docs/21 §13)
- **Behavior:**
  - Real pause while open (`get_tree().paused`); tapping the backdrop resumes.
  - The button NEVER fails silently: it cancels a placement (`building_placement_cancelled`) and closes every UIManager window (`UIManager.close_all_windows()`) and then opens. `can_pause()` is only for ESC.
  - ESC: an open window or a building in hand keeps ESC for itself; otherwise ESC opens/closes the menu, or closes the borrowed screen.
  - Android back = ESC (`application/config/quit_on_go_back=false`; `NOTIFICATION_WM_GO_BACK_REQUEST` is turned into an ESC press).
  - Borrowed screens (Ajustes, Ayuda, the intro) get `PROCESS_MODE_ALWAYS` and a layer ABOVE the menu (`LAYER + 1`, re-pinned every frame and on every UIManager reorder) while in use, and their mode and layer back on close. TitleMenu does the same with Ajustes. Bug 1 was the intro (layer 17) sitting over Ajustes (UIManager put it at 13) and eating every touch.
  - Menú principal saves, cancels placement, closes windows and opens TitleMenu, in 3D and 2D and in every mode.
- **Layer:** 30
- **Tests:** `tests/ui/test_game_menu.gd`, `tests/support/test_bug_report.gd`, `tests/support/test_game_speed.gd`, `test_main_menu_exit.gd`, `test_settings_respond.gd` (real mouse events pushed at the slider and a toggle, from the title menu, the game menu and in play, with a full-screen trap layer at 17), `test_pause_menu.gd`
- **Probe:** `tools/menu_probe.gd` (`-- --shot-size=1280x800 --profile=tablet [--view=2d]`), screenshots in `docs/media/dev/menu/`

### RankPanel (`scripts/ui/RankPanel.gd`) — governor rank
- **Badge:** top-right, left of "☰ MENÚ" (own slot `rank_badge` in `UILayoutConfig`; under the menu button on a narrow screen, without the title). The colony flag, the rank number, the title and a thin XP bar. Registered in `HudRegistry` as `RankPanel` (hideable and movable). Tapping it opens the card
- **Rank-up toast:** "▲ 5 · Alcalde" and one short line per reward ("Fuente", "+1 % producción", "bandera nueva"), under the badge, ~4 s. Sound `rank_up` (AudioManager, its own clip `rank_up.ogg` since 2026-10-12; no longer an alias of `era_up`)
- **COLONIA card** (☰ MENÚ → COLONIA → Colonia, `RankPanel.modal` in `center_modal`): rank and XP, what the next rank brings, and the flag and colour galleries; what is not earned yet is disabled with a padlock and the rank
- **Layer:** 11. Reads everything from `RankManager`; holds no state. Docs: [06-progression-victory.md](06-progression-victory.md) §Governor rank

### War reports and the Final Audit screens
- `AuditWaveBanner` (layer 19): "Oleada X de N" on `final_audit_wave_ready`, with the cleared wave from `final_audit_wave_cleared` above it and the last-wave line. Ignores the mouse, fades by itself
- `WarReportScreen` (layer 19): queued, one at a time, never over an open board — after-action report for `defense_auto_resolved` (rounds, losses on both sides, tower crews, morale; it no longer repeats the result, which the title and the Tithe report behind it say), and the Tithe report with its COBRADO / REPELIDO stamp for `tithe_resolved`
- `AuditDefeatScreen` (layer 20): on `final_audit_lost` — wave reached, Tithe taken, storm damage, casualties, and what it takes to resummon (`final_audit_resummon_min_units`). Not a game over
- All built with `ModalKit` (`scripts/ui/ModalKit.gd`), which only places UITheme pieces

### NotificationPanel (`scripts/ui/NotificationPanel.gd`)
- **Position:** bottom-left toasts, left side log panel (under the resources)
- **Shows:** toast notifications and the scrollable activity log. The old status card under the resources ("Trabajadores: 26 de 32", "En su puesto…", "Moral 72 %…") was removed in 2026-10: workers and morale are chips of the ResourceHUD row. What was urgent in it already arrives as a toast from `PopulationManager` (no wood, no gold, low morale, starvation). The objective strip at the top centre ("Avanza hacia la Victoria Imperial. Construye el Cuartel General y mejóralo.") was removed on 2026-10-05: it was a per-phase sentence that repeated, less precisely, what ¿QUÉ HACER? says (`Objectives.next_step()`), which is now the only place for the next step. Its slot (`top_center`), its HUD entry and the help tip under it (`tip_center`) went with it; an old `settings.cfg` that hides or moves it loads without it (`HudRegistry.RETIRED`), and the helps that pointed at it (`callout_objective`, the guide's last step, the PROGRESO block) point at ¿QUÉ HACER?: its ☰ MENÚ entry when the menu is open, the ☰ MENÚ button otherwise (`HelpTargets.objective_entry`).
- **Behavior:** Listens to `EventBus.notification_posted`. Only `warning`, `danger` and `notice` become toasts (`shows_toast()`); routine news ("Camino construido", the population grew) goes to the log only. Toasts auto-fade after 4 seconds, at most 3 at a time (1 on a narrow screen), and drop under the CONSTRUIR window while it is open. The log stores the last 50 entries and opens from ☰ MENÚ → COLONIA → Registro (`open_log()`); the old REGISTRO DE AVISOS button on the HUD is gone. Colours come from `UITheme.notice_color(category)`.
- **Layer:** 11

### Status badge (`scripts/buildings/BuildingStatusBadge.gd`, `scripts/view2d/StatusBadge2D.gd`)
- Over every building that can work: a worker pictogram when it works, and "Zzz" plus WHY it is stopped when it does not: "sin trabajadores", "sin trabajadores (retirados)", "sin carretera", "sin veta", "en ruinas", "parado" (`BuildingStatusBadge.reason_text`). Same text in 3D and 2D.
- Under construction the badge steps aside: the construction label says "En obras 61% · faltan 16 s", with a progress bar above the building (3D and 2D).

### OnScreenControls (`scripts/ui/OnScreenControls.gd`)
- **Position:** Bottom-right
- **Shows:** D-pad for camera pan, rotate buttons, zoom buttons
- **Purpose:** Mobile/touch control support
- **Layer:** 10

### Other panels

| Panel | Layer | What it is |
|---|---|---|
| `TechTreePanel` | 11 | 3 branches x 5 tiers, research progress; each card "1 · Name / cost / advantage" (+ reason if blocked). Tapping a card (any, locked ones too) **chooses** it; a detail card beside the branches (below them on a canvas under 880 px) shows name, tier and branch, the tech's lore, the branch's sentence, the cost as icons (`TextKit.cost_row`, missing in red), the time (`TextKit.short_time`), the advantage, the requirement and the reason it cannot start, with the INVESTIGAR button (2026-10-05). The long intro is a tooltip; lore and branch sentence are also tooltips of the card and header. Opened from a Laboratory (INVESTIGAR) ([11-tech-tree.md](11-tech-tree.md)) |
| `QuickGuide` | 33 | Child of `TutorialPanel`: "how the game works" in four blocks (resources, extraction, buildings and roads, progress). It no longer opens by itself after the prologue (2026-10-14); the same texts are `guide_qg_*` in AYUDA |
| `ArmyPanel` | 11 | "Tropa 5/11 · En cola 1/1" (where each cap comes from in the tooltip), Military Power; per unit "×3", cost as icons, power and wage; who is away on campaign |
| `SkirmishPanel` | 11 | Commit troops ("Salen 3/6") and launch an expedition; campaign status while a column is out ("Nodos 2/5"); "QUE BAJEN" for the Final Audit ([15-combat.md](15-combat.md)) |
| `BattleScreen` | 18 | The 8x8 board plus the expedition map, draft modal and final report; outside UIManager's stack so ESC cannot dismiss a fight. Header in one row: encounter, round and whose turn; each initiative chip names its unit and HP in the tooltip |
| `ObjectivePanel` | 15 | ¿QUÉ HACER?: the next step from `Objectives.next_step()` and its why in one sentence (≤ 16 words); EL CAMINO by building name; the mode's mission is the title's tooltip ([22-linea-jugable.md](22-linea-jugable.md) §4) |
| `SettingsPanel` | 15 | Tabs Audio · Interfaz · Controles · Accesibilidad · Juego ([21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md)) |
| `StormHUD` | 16 (11 under modals) | Storm phase: colour and icon, no countdown |
| `SandboxPanel` | 11 | Sandbox only: the SANDBOX tab with INVOCAR TORMENTA / INVOCAR AUDITORÍA ([20-modos-de-juego.md](20-modos-de-juego.md)) |
| `NewGameDialog` | 40 | The mode picker, created by `GameManager.request_new_game()` from every "Nueva partida" |
| `SavesPanel` | 40 | PARTIDAS: the saved games (name, flag, mode/tier, era, time, date; Load / Delete), from the title menu and ☰ MENÚ → PARTIDA, and from Nueva partida with five games (`make_room`) |
| `LayoutEditor` | 35 | EDITAR DISPOSICIÓN: drag panels, saved per device profile |

Every panel exists in both `Main.tscn` and `Main2D.tscn` with the same name; the
full tree is in `CLAUDE.md` → "Scene Tree".

## Interfaz configurable y dispositivos (docs/21)

- **Perfiles** (`DeviceProfile`, autoload): PC / Tablet / Movil, detectados por
  features de SO y lado corto en dp, forzables en Ajustes. Traen escala, texto,
  lado tactil minimo, controles en pantalla en "Automatico" (sigue al perfil: nunca en PC) y
  textos de ayuda de raton o de dedo (`Tr.ti`).
- **Lienzo**: `aspect = expand` y `content_scale_factor` como escala de
  interfaz: sin bandas negras en 16:10, 4:3, 21:9 ni vertical.
- **Ajustes en pestanas**: Audio · Interfaz · Controles · Accesibilidad · Juego,
  cada una con scroll y Restablecer.
- **HUD**: `HudRegistry` decide que se puede ocultar y mover. Un elemento nuevo
  se anade a `HudRegistry.ELEMENTS` y llama a `HudRegistry.register(id, control)`
  despues de `add_child`.
- **Paneles movibles**: "Editar disposicion" (`LayoutEditor`); desplazamientos
  sobre el slot guardados por perfil y proporcion en `GameConfig.ui_layout`.
- **Colores**: los colores de `UITheme` son tokens (`UITheme.configure`):
  paletas rojo-verde y azul-amarillo, alto contraste, opacidad de paneles y
  tamano de texto. Nada de colores semanticos escritos a mano en los paneles.
- **Columna central** baja a la izquierda cuando no cabe (lienzo < 1080 px o
  columna izquierda real mas ancha: cuatro recursos + LIMPIAR). Ya no hay
  boton de pausa a la derecha de los recursos (`PAUSE_RESERVE = 0`): el menu
  unico va arriba a la derecha.

## Prologo, tutorial y ayudas (docs/23)

Tres piezas que no se mezclan, cada una con su estilo:

| Pieza | Script | Capa | Estilo | Que hace |
|---|---|---|---|---|
| Prologo | `PrologueScreen` (hija de `TutorialPanel`) | 32 | papel, maquina de escribir, lacre | El lore en tres folios y en lenguaje claro (la firma del Emperador, la Tormenta, quienes somos), sin membrete. Atras / Siguiente / Saltar historia, puntos de pagina, deslizar el dedo. Pausa el juego |
| Guia rapida | `QuickGuide` (hija de `TutorialPanel`) | 33 | tarjeta de `ModalKit` | Como funciona el juego en cuatro bloques. Desde el 14-10 ya **no se abre sola** al cerrar el prologo (Bryan: sobraba al empezar); sus textos siguen en AYUDA (`guide_qg_*`) |
| Tutorial guiado | `TutorialPanel` | 19 | laton sobre metal | Coach marks sobre la interfaz real: velo con hueco, marco, flecha, una linea. Avanza cuando el jugador hace la cosa (`TutorialManager.derive_step`). "Saltar tutorial" |
| Ayudas | `HelperPanel` (+ `HelpCallout`, `HelpCatalog`) | 14 (globos) / 19 (tarjeta) | azul acero | Una a la vez, en cola por prioridad, con ✕ y cierre solo (6-12 s, barra, pausa con el dedo encima). Cerrada = vista |
| Indice de AYUDA | `HelpIndexPanel` (grupo `help_index`, `open()`) | pila de UIManager | metal | Lo visto y lo basico, por categoria; tocar reabre esa ayuda senalando su control. Interruptor global, guia de edificios, Repetir tutorial, Historia |

- `TutorialManager.show_prologue()` (alias `show_intro()`) reabre el prologo: lo
  usan "Historia" de la pausa y el menu unico.
- El prologo nunca se abre con el menu principal delante ni con el arbol en
  pausa: queda pendiente (`is_prologue_pending`) y sale al soltarlo.
- Los controles se buscan por nombre estable (`HelpTargets`): grupos
  `hud_build_button` y `hud_menu_button`, y si no, `HudRegistry`.

## UI Construction Pattern

All panels follow this pattern:
```gdscript
func _ready() -> void:
    layer = N
    _setup_ui()
    EventBus.some_signal.connect(_on_handler)

func _setup_ui() -> void:
    # Create root Control
    # Create styled PanelContainer
    # Build widget tree programmatically
    # Store references to dynamic labels in instance vars
```

## Styling

Everything goes through `UITheme` (tokens, factories, `UITheme.style_tabs`).

- **One palette of ten colours** (2026-09-28): `UITheme._BASE` holds surface, neutral,
  brass, three text tones and four semantic colours; every other token is derived from
  them in `_derive()`. Colour-blind palettes and high contrast only change base
  colours. A new tone is a `darkened()` / `lightened()` of a palette colour, never a
  new `Color(...)`. From 71 hand-written UI colours to 10 + 4 resource colours. Full
  table: [24-paleta.md](24-paleta.md).
- **Plain boxes:** the textured metal plates under panels and buttons are off
  (`UITheme.METAL_TEXTURES = false`; the textures stay in `assets/`). Every panel and
  button uses a flat box that follows palette, contrast and opacity.
- **Drag to scroll:** every `ScrollContainer` drags with a finger or the mouse wherever
  the gesture starts (`scripts/ui/DragScroll.gd`, hooked by UIManager); a drag never
  presses what is under it, and the wheel scrolls the list instead of changing a
  slider.
- **Hold to read (touch):** with the touch input style, keeping a finger still
  `GameConfig.touch_tooltip_hold_sec` (0.5 s) on any `Control` with a tooltip shows it
  in a bubble above the finger; the button is not pressed. A short tap still presses.
  `scripts/ui/TouchTooltip.gd`, a child of `InputService`; full rules in
  [21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §9.

## Less text (2026-10-04)

Rules and tools for short panels (`TextKit`, tooltips, word caps, the
`tools/texto_probe.gd` probe and the `test_menos_texto_*` suites):
[21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md) §6, "Menos texto".

## Translation

All user-visible strings use `Tr.t("KEY")` for i18n support (ES/EN).
Resource names use `Tr.res_name("gold")` / `Tr.res_upper()` / `Tr.res_cap()`.
