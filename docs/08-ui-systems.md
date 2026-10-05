# UI Systems

## Overview

All UI is built programmatically in GDScript (no Godot editor UI design). Each panel is a CanvasLayer with a script that constructs its own widgets in `_setup_ui()`.

## UI Panels

### ResourceHUD (`scripts/ui/ResourceHUD.gd`)
- **Position:** Top-left card (slot `top_left`)
- **Shows:** Unlocked resource amounts (gold, wood, then steel/oil when unlocked) and ONE shared storage bar labelled "ALMACÉN COMPARTIDO 500 / 600"
- **Behavior:** Resource values update in real-time via `EventBus.resource_changed`. Each number has its name in a tooltip; a tap (or click) on a number or on the storage row unfolds a row per resource with name, amount and a colour swatch that is the legend of the storage bar, plus one line explaining the shared cap. The bar turns red when full. Animates glow when a new resource unlocks.
- **TALLER row** (2026-09-28): the workshop materials (planks, ingots, beams, fuel), outside the shared bar; the row appears once one material is unlocked or held.
- **Layer:** 10

### ConstructionMenu (`scripts/ui/ConstructionMenu.gd`)
- **Position:** Bottom center: a big CONSTRUIR button (240x64, brass border), ALWAYS visible — it used to appear only while the ☰ column was open
- **Shows:** Scrollable list of all non-core buildings from `data/buildings/` (15 cards), with a category filter; the category colour is only the stripe of each card (docs/24)
- **Behavior:** Each card shows its cost (red when it cannot be paid). Cards are picked on release inside them, and locked ones can be tapped too: the detail says everything that is missing (resource to unlock and what brings it, previous buildings by translated name, limit, workers, cost). The cost sits at the top of the detail, before the preview; when something blocks the build it is said next to the button ("Te falta: 20 Madera") and the button does not start. The detail also states the road rule. Columns follow the width. Rebuilds when resources unlock.
- **Placing:** one building per placement — after it, placement mode ends; only decorations, roads and `repeat_placement` buildings stay in hand (`PlacementRules.keeps_placing()`).
- **Layer:** 12

### BuildingInfoPanel (`scripts/ui/BuildingInfoPanel.gd`)
- **Position:** Right side, full height
- **Shows:** Selected building/deposit details
- **Sections:** Title, level, description, production info, construction progress, upgrade button+cost with what the next level gives (only on buildings whose upgrade does something), process actions (via ProcessActionsPanel), move/demolish buttons, demolish confirmation
- **RETIRAR / PONER TRABAJADORES** on every building that uses workers, with a line saying how many it frees or takes (or "sin veta" when its deposit is gone)
- **ABRIR MERCADO / INVESTIGAR** on the Market and the Laboratory (`SCREENS`): the only way to open `MarketPanel` and `TechTreePanel`; disabled while the building has no road
- **Deposits:** uses left, plus the difference between mining it by hand (it runs out, holds 2 workers, needs a road) and putting its specialised building next to it (produces without using it up)
- **Layer:** 10

### ProcessActionsPanel (`scripts/ui/ProcessActionsPanel.gd`)
- **Type:** Helper class (not a scene, instantiated by BuildingInfoPanel)
- **Shows:** Available manual processes for selected building, or mining button for deposits
- **Behavior:** Hides processes that use locked resources. Shows progress bar during active process. Disables buttons while process running or building constructing.

### MarketPanel (`scripts/ui/MarketPanel.gd`)
- **Position:** Center overlay, opened from a Market building (ABRIR MERCADO in its BuildingInfoPanel); no menu entry since 2026-09-28
- **Shows:** Buy/sell prices for each unlocked resource, amount selector (+-5), buy/sell buttons, gold balance
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
- **Trigger:** `EventBus.victory_achieved`. Waits for `GameManager.offline_report_closed` if the offline report (also layer 20) is still open. "Nueva partida" goes through `GameManager.request_new_game()`
- **Layer:** 20

### TitleMenu (`scripts/ui/TitleMenu.gd`)
- **Shows:** keyart background (logo + name on portrait), Continuar (only if a save was loaded or the player already played this session), Nueva partida (via `GameManager.request_new_game()` when there is something to lose), Ajustes, Salir
- **Behavior:** opens on launch over the already-loaded game and pauses the tree (`get_tree().paused`). Skipped headless and with `-- --no-title` (probes). Shown once per session (static flag survives the new-game reload)
- **Layer:** 30, `PROCESS_MODE_ALWAYS`

### PauseMenu (`scripts/ui/PauseMenu.gd`) — THE game menu
There is ONE menu (it replaced the "II" pause button and the ☰ sidebar, which
lived in opposite corners and overlapped). The node is still called `PauseMenu`.
- **Button:** "☰ MENÚ", top-right, finger-sized, always visible in play (hidden while the menu itself is open). No other menu button exists; the old sidebar buttons of each panel stay hidden (nobody emits `sidebar_toggled(true)` any more)
- **Card:** title, "Modo: X", and two groups side by side (one column with scroll below 700 px):
  - **COLONIA** — ¿Qué hacer?, Progreso, Ejército and Escaramuzas (with a Barracks), Sandbox (in Sandbox mode), Registro (the activity log). Mercado and Tecnología left the menu on 2026-09-28: they open from their buildings. Only what is available is shown, so no gaps. Picking one closes the menu, unpauses and opens that panel (`open_colony_panel`)
  - **PARTIDA** — Reanudar, Guardar, Ajustes, Música sí/no, Ayuda (only if a node in group `help_index` exists; calls its `open()`), Historia (closes the menu, then `TutorialManager.show_prologue()` replays the prologue, docs/23), Menú principal, Guardar y salir
- **Behavior:**
  - Real pause while open (`get_tree().paused`); tapping the backdrop resumes.
  - The button NEVER fails silently: it cancels a placement (`building_placement_cancelled`) and closes every UIManager window (`UIManager.close_all_windows()`) and then opens. `can_pause()` is only for ESC.
  - ESC: an open window or a building in hand keeps ESC for itself; otherwise ESC opens/closes the menu, or closes the borrowed screen.
  - Android back = ESC (`application/config/quit_on_go_back=false`; `NOTIFICATION_WM_GO_BACK_REQUEST` is turned into an ESC press).
  - Borrowed screens (Ajustes, Ayuda, the intro) get `PROCESS_MODE_ALWAYS` and a layer ABOVE the menu (`LAYER + 1`, re-pinned every frame and on every UIManager reorder) while in use, and their mode and layer back on close. TitleMenu does the same with Ajustes. Bug 1 was the intro (layer 17) sitting over Ajustes (UIManager put it at 13) and eating every touch.
  - Menú principal saves, cancels placement, closes windows and opens TitleMenu, in 3D and 2D and in every mode.
- **Layer:** 30
- **Tests:** `tests/ui/test_game_menu.gd`, `test_main_menu_exit.gd`, `test_settings_respond.gd` (real mouse events pushed at the slider and a toggle, from the title menu, the game menu and in play, with a full-screen trap layer at 17), `test_pause_menu.gd`
- **Probe:** `tools/menu_probe.gd` (`-- --shot-size=1280x800 --profile=tablet [--view=2d]`), screenshots in `docs/media/dev/menu/`

### War reports and the Final Audit screens
- `AuditWaveBanner` (layer 19): "Oleada X de N" on `final_audit_wave_ready`, with the cleared wave from `final_audit_wave_cleared` above it and the last-wave line. Ignores the mouse, fades by itself
- `WarReportScreen` (layer 19): queued, one at a time, never over an open board — after-action report for `defense_auto_resolved`, and the Tithe report with its COBRADO / REPELIDO stamp for `tithe_resolved`
- `AuditDefeatScreen` (layer 20): on `final_audit_lost` — wave reached, Tithe taken, storm damage, casualties, and what it takes to resummon (`final_audit_resummon_min_units`). Not a game over
- All built with `ModalKit` (`scripts/ui/ModalKit.gd`), which only places UITheme pieces

### NotificationPanel (`scripts/ui/NotificationPanel.gd`)
- **Position:** Top-left status bar (workers/morale), bottom-left toasts, left side log panel
- **Shows:** "Trabajadores: 26 de 32", "En su puesto: 14 · libres: 12", "Moral 72 %: producción x1.1" (tooltips per row; a tap on the card unfolds the three explanations), toast notifications, scrollable activity log
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
| `TechTreePanel` | 11 | 3 branches x 5 tiers, research progress, what each branch and tech gives; opened from a Laboratory (INVESTIGAR) ([11-tech-tree.md](11-tech-tree.md)) |
| `QuickGuide` | 33 | Child of `TutorialPanel`: "how the game works" in four blocks (resources, extraction, buildings and roads, progress), once per game after the prologue; the same texts are `guide_qg_*` in AYUDA |
| `ArmyPanel` | 11 | Training slots, Military Power, upkeep, who is away on campaign |
| `SkirmishPanel` | 11 | Commit troops and launch an expedition; campaign status while a column is out; "QUE BAJEN" for the Final Audit ([15-combat.md](15-combat.md)) |
| `BattleScreen` | 18 | The 8x8 board plus the expedition map, draft modal and final report; outside UIManager's stack so ESC cannot dismiss a fight |
| `ObjectivePanel` | 15 | ¿QUÉ HACER?: the next step from `Objectives.next_step()` ([22-linea-jugable.md](22-linea-jugable.md) §4) |
| `SettingsPanel` | 15 | Tabs Audio · Interfaz · Controles · Accesibilidad · Juego ([21-interfaz-y-dispositivos.md](21-interfaz-y-dispositivos.md)) |
| `StormHUD` | 16 (11 under modals) | Storm phase: colour and icon, no countdown |
| `SandboxPanel` | 11 | Sandbox only: the SANDBOX tab with INVOCAR TORMENTA / INVOCAR AUDITORÍA ([20-modos-de-juego.md](20-modos-de-juego.md)) |
| `NewGameDialog` | 40 | The mode picker, created by `GameManager.request_new_game()` from every "Nueva partida" |
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
| Guia rapida | `QuickGuide` (hija de `TutorialPanel`) | 33 | tarjeta de `ModalKit` | Como funciona el juego en cuatro bloques. Una vez por partida, al cerrar el prologo y antes del tutorial; despues, en AYUDA |
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

## Translation

All user-visible strings use `Tr.t("KEY")` for i18n support (ES/EN).
Resource names use `Tr.res_name("gold")` / `Tr.res_upper()` / `Tr.res_cap()`.
