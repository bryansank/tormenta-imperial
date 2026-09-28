# UI Systems

## Overview

All UI is built programmatically in GDScript (no Godot editor UI design). Each panel is a CanvasLayer with a script that constructs its own widgets in `_setup_ui()`.

## UI Panels

### ResourceHUD (`scripts/ui/ResourceHUD.gd`)
- **Position:** Top-left card (slot `top_left`)
- **Shows:** Unlocked resource amounts (gold, wood, then steel/oil when unlocked) and ONE shared storage bar labelled "ALMACÉN COMPARTIDO 500 / 600"
- **Behavior:** Resource values update in real-time via `EventBus.resource_changed`. Each number has its name in a tooltip; a tap (or click) on a number or on the storage row unfolds a row per resource with name, amount and a colour swatch that is the legend of the storage bar, plus one line explaining the shared cap. The bar turns red when full. Animates glow when a new resource unlocks.
- **Layer:** 10

### ConstructionMenu (`scripts/ui/ConstructionMenu.gd`)
- **Position:** Bottom center: a big CONSTRUIR button (240x64, brass border), ALWAYS visible — it used to appear only while the ☰ column was open
- **Shows:** Scrollable list of all non-core buildings from `data/buildings/`
- **Behavior:** Each button shows name, size, cost, production, prerequisites, worker requirements. Buildings requiring locked resources are grayed out. Rebuilds when resources unlock.
- **Layer:** 10

### BuildingInfoPanel (`scripts/ui/BuildingInfoPanel.gd`)
- **Position:** Right side, full height
- **Shows:** Selected building/deposit details
- **Sections:** Title, level, description, production info, construction progress, upgrade button+cost, process actions (via ProcessActionsPanel), move/demolish buttons, demolish confirmation
- **Layer:** 10

### ProcessActionsPanel (`scripts/ui/ProcessActionsPanel.gd`)
- **Type:** Helper class (not a scene, instantiated by BuildingInfoPanel)
- **Shows:** Available manual processes for selected building, or mining button for deposits
- **Behavior:** Hides processes that use locked resources. Shows progress bar during active process. Disables buttons while process running or building constructing.

### MarketPanel (`scripts/ui/MarketPanel.gd`)
- **Position:** Center overlay, button top-right
- **Shows:** Buy/sell prices for each unlocked resource, amount selector (+-5), buy/sell buttons, gold balance
- **Behavior:** Prices update via `EventBus.market_prices_updated`. Rebuilds when resources unlock.
- **Layer:** 11

### ProgressPanel (`scripts/ui/ProgressPanel.gd`)
- **Position:** Center overlay, button top-right (below market)
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
  - **COLONIA** — ¿Qué hacer?, Progreso, Mercado (from the ECONOMY phase), Tecnología, Ejército and Escaramuzas (with a Barracks), Sandbox (in Sandbox mode). Only what is available is shown, so no gaps. Picking one closes the menu, unpauses and opens that panel (`open_colony_panel`)
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
- **Position:** Top-left status bar (pop/workers/morale), bottom-left toasts, left side log panel
- **Shows:** "Habitantes: 26 de 32", "Obreros: 14 trabajan, 12 libres", "Moral 72 %: producción x1.1" (tooltips per row; a tap on the card unfolds the three explanations), the REGISTRO DE AVISOS button, scrollable activity log, toast notifications
- **Behavior:** Listens to `EventBus.notification_posted`. Toasts auto-fade after 4 seconds. Log stores last 50 entries.
- **Layer:** 11

### Status badge (`scripts/buildings/BuildingStatusBadge.gd`, `scripts/view2d/StatusBadge2D.gd`)
- Over every building that can work: a worker pictogram when it works, and "Zzz" plus WHY it is stopped when it does not: "sin obreros" (red), "parado", "en obras", "en ruinas" (`BuildingStatusBadge.reason_text`). Same text in 3D and 2D.

### OnScreenControls (`scripts/ui/OnScreenControls.gd`)
- **Position:** Bottom-right
- **Shows:** D-pad for camera pan, rotate buttons, zoom buttons
- **Purpose:** Mobile/touch control support
- **Layer:** 10

## Interfaz configurable y dispositivos (docs/21)

- **Perfiles** (`DeviceProfile`, autoload): PC / Tablet / Movil, detectados por
  features de SO y lado corto en dp, forzables en Ajustes. Traen escala, texto,
  lado tactil minimo, controles en pantalla en "Automatico" (nunca en PC) y
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
| Prologo | `PrologueScreen` (hija de `TutorialPanel`) | 32 | papel, maquina de escribir, lacre | El lore como expediente de la Regencia. Atras / Siguiente / Saltar historia, puntos de pagina, deslizar el dedo. Pausa el juego |
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
Historic defaults of the dark theme:
- Background: `Color(0.08-0.12, alpha 0.85-0.96)`
- Borders: `Color(0.7, 0.55, 0.15)` (gold accent)
- Buttons: `_style_button(btn, bg_color)` helper (each panel has its own)
- Font sizes: 11-18px range
- Gold text: `Color(0.95, 0.82, 0.25)` for titles

## Translation

All user-visible strings use `Tr.t("KEY")` for i18n support (ES/EN).
Resource names use `Tr.res_name("gold")` / `Tr.res_upper()` / `Tr.res_cap()`.
