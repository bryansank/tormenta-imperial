class_name UILayoutConfig
## Single source of truth for UI panel layout.
## Defines screen slots and assigns each panel to a slot.

## Slot definitions: each slot is a screen region.
## anchor: Rect2(left, top, right, bottom) in 0..1 normalized coords
## margin: Dictionary with pixel offsets from anchor edges
## max_size: Vector2 — max pixel size (0 = unlimited on that axis)
## grow_h / grow_v: Control.GrowDirection values
const SLOTS := {
	"top_left": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 8, "right": 0, "bottom": 0},
		"max_size": Vector2(280, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"status_bar": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 62, "right": 0, "bottom": 0},
		"max_size": Vector2(260, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"top_center": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 62, "right": 0, "bottom": 0},
		"max_size": Vector2(440, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"sidebar_buttons": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 10, "right": 10, "bottom": 0},
		"max_size": Vector2(176, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"right_panel": {
		"anchor": Rect2(1, 0, 1, 1),
		"margin": {"left": 0, "top": 210, "right": 8, "bottom": 20},
		"max_size": Vector2(360, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"center_modal": {
		"anchor": Rect2(0.5, 0.5, 0.5, 0.5),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 0},
		"max_size": Vector2(1000, 660),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BOTH,
	},
	"left_panel": {
		"anchor": Rect2(0, 0, 0, 1),
		"margin": {"left": 10, "top": 186, "right": 0, "bottom": 10},
		"max_size": Vector2(354, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"toast_area": {
		"anchor": Rect2(0, 1, 0, 1),
		"margin": {"left": 10, "top": 0, "right": 0, "bottom": 200},
		"max_size": Vector2(344, 210),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	"bottom_center": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 20},
		"max_size": Vector2(250, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	"bottom_controls": {
		"anchor": Rect2(0, 0, 1, 1),
		"margin": {"left": 20, "top": 20, "right": 20, "bottom": 20},
		"max_size": Vector2.ZERO,
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BOTH,
	},
	"full_overlay": {
		"anchor": Rect2(0, 0, 1, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 0},
		"max_size": Vector2.ZERO,
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BOTH,
	},
}

## Panel-to-slot assignment
const PANEL_SLOTS := {
	"ResourceHUD":                "top_left",
	"NotificationPanel.status":   "status_bar",
	"NotificationPanel.objective":"top_center",
	"NotificationPanel.toasts":   "toast_area",
	"NotificationPanel.log":      "left_panel",
	"MarketPanel.sidebar_toggle": "sidebar_buttons",
	"MarketPanel.button":         "sidebar_buttons",
	"MarketPanel.modal":          "center_modal",
	"ObjectivePanel.button":      "sidebar_buttons",
	"ProgressPanel.button":       "sidebar_buttons",
	"ProgressPanel.modal":        "center_modal",
	"ArmyPanel.button":           "sidebar_buttons",
	"ArmyPanel.modal":            "center_modal",
	"SkirmishPanel.button":       "sidebar_buttons",
	"SkirmishPanel.modal":        "center_modal",
	"BattleScreen":               "full_overlay",
	"TechTreePanel.button":       "sidebar_buttons",
	"TechTreePanel.modal":        "center_modal",
	"SettingsPanel.button":       "sidebar_buttons",
	"SettingsPanel.modal":        "center_modal",
	"HelperPanel.modal":          "center_modal",
	"ConstructionMenu.button":    "bottom_center",
	"ConstructionMenu.modal":     "center_modal",
	"BuildingInfoPanel":          "right_panel",
	"ObjectivePanel":             "center_modal",
	"VictoryScreen":              "full_overlay",
	"OnScreenControls":           "bottom_controls",
}

## Per-panel size overrides (when smaller than slot max_size)
## Anchos subidos ~25% para acompanar la tipografia mayor (FONT_BODY 13 -> 17).
## UILayoutManager los recorta al viewport, asi que en 400x720 no se salen.
const PANEL_SIZES := {
	"MarketPanel.modal":       Vector2(540, 0),
	"ProgressPanel.modal":     Vector2(470, 0),
	"ArmyPanel.modal":         Vector2(620, 0),
	"SkirmishPanel.modal":     Vector2(640, 0),
	"TechTreePanel.modal":     Vector2(860, 0),
	"ObjectivePanel":          Vector2(640, 560),
	"SettingsPanel.modal":     Vector2(520, 0),
	"HelperPanel.modal":       Vector2(700, 600),
	"ConstructionMenu.modal":  Vector2(1000, 640),
	"VictoryScreen":           Vector2(560, 400),
}

## Sidebar button stacking order (top to bottom)
const SIDEBAR_BUTTON_ORDER := [
	"MarketPanel.sidebar_toggle",
	"ObjectivePanel.button",
	"ProgressPanel.button",
	"ArmyPanel.button",
	"SkirmishPanel.button",
	"MarketPanel.button",
	"TechTreePanel.button",
	"SettingsPanel.button",
]

## Slot conflicts: opening a panel in key slot also closes panels in value slots.
## center_modal closes right_panel because the backdrop obscures it.
const SLOT_CONFLICTS := {
	"center_modal": ["right_panel"],
}

## Height of each sidebar button + gap
## 44 px de lado: minimo tactil recomendado en movil.
const SIDEBAR_BTN_HEIGHT := 44
const SIDEBAR_BTN_GAP := 5
const SIDEBAR_TOGGLE_GAP := 6
const SIDEBAR_TOGGLE_SIZE := 44
const SIDEBAR_FIRST_Y := 10
