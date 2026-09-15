class_name UILayoutConfig
## Single source of truth for UI panel layout.
## Defines screen slots and assigns each panel to a slot.

## Slot definitions: each slot is a screen region.
## anchor: Rect2(left, top, right, bottom) in 0..1 normalized coords
## margin: Dictionary with pixel offsets from anchor edges
## max_size: Vector2 — max pixel size (0 = unlimited on that axis)
## grow_h / grow_v: Control.GrowDirection values
##
## stack_after (opcional): id del panel bajo el que se coloca este slot. En vez
## de un `margin.top` fijo, UILayoutManager pone el panel justo debajo del borde
## inferior REAL del referido, y lo vuelve a colocar cada vez que ese panel
## cambia de altura, se muestra u oculta, o cambia la ventana. Si el referido
## esta oculto, el panel ocupa su sitio (la columna se compacta).
## Por que: los huecos eran offsets en pixeles calibrados para la tipografia
## antigua; al subir las fuentes cada panel crecio y se comio el hueco del
## siguiente. Con apilado real no hay numeros magicos por panel que mantener.
## gap (opcional): separacion en px con el panel de arriba (por defecto,
## UILayoutManager.DEFAULT_STACK_GAP).
## `margin.top` en un slot apilado solo se usa si el referido no existe.
const SLOTS := {
	## Columna izquierda: recursos -> poblacion/moral -> log.
	"top_left": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 8, "right": 0, "bottom": 0},
		"max_size": Vector2(300, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"status_bar": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 62, "right": 0, "bottom": 0},
		"max_size": Vector2(300, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "ResourceHUD",
	},
	"left_panel": {
		"anchor": Rect2(0, 0, 0, 1),
		"margin": {"left": 10, "top": 186, "right": 0, "bottom": 10},
		"max_size": Vector2(354, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "NotificationPanel.status",
	},
	## Columna central: fase de la Tormenta -> objetivo.
	## La Tormenta va ARRIBA: cuando hay ceniza en camino es lo mas importante
	## de la pantalla y el jugador tiene que leerla sin buscarla. En calma el
	## indicador se oculta y el objetivo sube a ocupar su sitio.
	"storm_banner": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 8, "right": 0, "bottom": 0},
		"max_size": Vector2(380, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"top_center": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 62, "right": 0, "bottom": 0},
		"max_size": Vector2(440, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "StormHUD",
	},
	## Columna derecha: botones del menu lateral -> panel de edificio.
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
		"stack_after": "sidebar_buttons",
		"gap": 8,
	},
	"center_modal": {
		"anchor": Rect2(0.5, 0.5, 0.5, 0.5),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 0},
		"max_size": Vector2(1000, 660),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BOTH,
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
	## Globos del tutorial (HelperPanel). Cada uno se apila bajo el panel que
	## explica, asi siguen al HUD cuando este cambia de tamano en vez de vivir
	## en coordenadas fijas que dejan de valer con la siguiente tipografia.
	"tip_left": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 200, "right": 0, "bottom": 0},
		"max_size": Vector2(260, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "NotificationPanel.log",
		"gap": 8,
	},
	"tip_center": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 120, "right": 0, "bottom": 0},
		"max_size": Vector2(300, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "NotificationPanel.objective",
		"gap": 8,
	},
	## A la izquierda del boton ☰ (44 px + 10 de margen + 10 de hueco).
	"tip_top_right": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 10, "right": 64, "bottom": 0},
		"max_size": Vector2(280, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	## Encima del boton CONSTRUIR (bottom_center: 20 de margen + 44 de boton).
	"tip_bottom_center": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 80},
		"max_size": Vector2(320, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	## Camara en escritorio: esquina inferior izquierda, sin D-pad que tapar.
	"tip_bottom_left": {
		"anchor": Rect2(0, 1, 0, 1),
		"margin": {"left": 10, "top": 0, "right": 0, "bottom": 20},
		"max_size": Vector2(260, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	## Camara en tactil: encima del D-pad (3 botones de 50 px + margen 20).
	"tip_above_dpad": {
		"anchor": Rect2(0, 1, 0, 1),
		"margin": {"left": 20, "top": 0, "right": 0, "bottom": 200},
		"max_size": Vector2(230, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	## Zoom/rotar en tactil: encima de los botones de la esquina inferior derecha.
	"tip_bottom_right": {
		"anchor": Rect2(1, 1, 1, 1),
		"margin": {"left": 0, "top": 0, "right": 20, "bottom": 150},
		"max_size": Vector2(230, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
}

## Referencia virtual para `stack_after`: la columna de botones del menu ☰.
## Esos botones no pasan por apply_layout (cada panel coloca el suyo con
## get_sidebar_button_offset), asi que UILayoutManager calcula su borde
## inferior a partir de SIDEBAR_* y de si el menu esta desplegado.
const SIDEBAR_STACK_REF := "sidebar_buttons"

## Panel-to-slot assignment
const PANEL_SLOTS := {
	"ResourceHUD":                "top_left",
	"NotificationPanel.status":   "status_bar",
	"NotificationPanel.objective":"top_center",
	"StormHUD":                   "storm_banner",
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
	"HelperPanel.button":         "sidebar_buttons",
	"HelperPanel.modal":          "center_modal",
	"HelperPanel.tip_resources":  "tip_left",
	"HelperPanel.tip_objective":  "tip_center",
	"HelperPanel.tip_menus":      "tip_top_right",
	"HelperPanel.tip_build":      "tip_bottom_center",
	"HelperPanel.tip_camera":     "tip_bottom_left",
	"HelperPanel.tip_camera_touch": "tip_above_dpad",
	"HelperPanel.tip_zoom":       "tip_bottom_right",
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
## La ayuda va dentro del menu (A6): un boton flotante menos en pantalla.
const SIDEBAR_BUTTON_ORDER := [
	"MarketPanel.sidebar_toggle",
	"ObjectivePanel.button",
	"ProgressPanel.button",
	"ArmyPanel.button",
	"SkirmishPanel.button",
	"MarketPanel.button",
	"TechTreePanel.button",
	"SettingsPanel.button",
	"HelperPanel.button",
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
## Ancho del boton de menu lateral (los paneles lo usan para colocarse a -176).
const SIDEBAR_BTN_WIDTH := 164
