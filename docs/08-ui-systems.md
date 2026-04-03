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
- **Trigger:** `EventBus.victory_achieved`
- **Layer:** 20

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
