# UI Systems

## Overview

All UI is built programmatically in GDScript (no Godot editor UI design). Each panel is a CanvasLayer with a script that constructs its own widgets in `_setup_ui()`.

## UI Panels

### ResourceHUD (`scripts/ui/ResourceHUD.gd`)
- **Position:** Top bar, full width
- **Shows:** Unlocked resource amounts (gold, wood, then steel/oil when unlocked)
- **Behavior:** Resource values update in real-time via `EventBus.resource_changed`. Flashes orange when at storage cap. Animates glow when a new resource unlocks.
- **Layer:** 10

### ConstructionMenu (`scripts/ui/ConstructionMenu.gd`)
- **Position:** Bottom center ("BUILD" button), panel grows upward
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
- **Behavior:** Updates checkmarks on milestone completion. Shows toast notifications for milestones and era transitions.
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

### PauseMenu (`scripts/ui/PauseMenu.gd`)
- **Shows:** Reanudar, Guardar, Ajustes, Historia (replays the intro), Menu principal, Guardar y salir; plus an always-visible "II" touch button (top-left next to the HUD; bottom-centre on narrow screens)
- **Behavior:** ESC opens it only when no UIManager window is open, `BuildingPlacer.is_idle()` and the title menu is closed. Real pause: services stop; the menu, AudioManager and whatever panel it lends (SettingsPanel, TutorialPanel) get `PROCESS_MODE_ALWAYS` while in use and their mode back on close
- **Layer:** 30

### War reports and the Final Audit screens
- `AuditWaveBanner` (layer 19): "Oleada X de N" on `final_audit_wave_ready`, with the cleared wave from `final_audit_wave_cleared` above it and the last-wave line. Ignores the mouse, fades by itself
- `WarReportScreen` (layer 19): queued, one at a time, never over an open board — after-action report for `defense_auto_resolved`, and the Tithe report with its COBRADO / REPELIDO stamp for `tithe_resolved`
- `AuditDefeatScreen` (layer 20): on `final_audit_lost` — wave reached, Tithe taken, storm damage, casualties, and what it takes to resummon (`final_audit_resummon_min_units`). Not a game over
- All built with `ModalKit` (`scripts/ui/ModalKit.gd`), which only places UITheme pieces

### NotificationPanel (`scripts/ui/NotificationPanel.gd`)
- **Position:** Top-left status bar (pop/workers/morale), bottom-left toasts, left side log panel
- **Shows:** Population/workers/morale status, scrollable activity log, toast notifications
- **Behavior:** Listens to `EventBus.notification_posted`. Toasts auto-fade after 4 seconds. Log stores last 50 entries.
- **Layer:** 11

### OnScreenControls (`scripts/ui/OnScreenControls.gd`)
- **Position:** Bottom-right
- **Shows:** D-pad for camera pan, rotate buttons, zoom buttons
- **Purpose:** Mobile/touch control support
- **Layer:** 10

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

All panels use a consistent dark theme:
- Background: `Color(0.08-0.12, alpha 0.85-0.96)`
- Borders: `Color(0.7, 0.55, 0.15)` (gold accent)
- Buttons: `_style_button(btn, bg_color)` helper (each panel has its own)
- Font sizes: 11-18px range
- Gold text: `Color(0.95, 0.82, 0.25)` for titles

## Translation

All user-visible strings use `Tr.t("KEY")` for i18n support (ES/EN).
Resource names use `Tr.res_name("gold")` / `Tr.res_upper()` / `Tr.res_cap()`.
