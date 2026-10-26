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
## follow_moved (opcional): si el jugador movio el referido (Editar
## disposicion), por defecto este slot ocupa su hueco en la columna; con true lo
## sigue a donde este (los globos de ayuda, que hablan de ese panel).
const SLOTS := {
	## Columna izquierda: recursos (con obreros y moral en la misma fila) -> log.
	## La tarjeta de estado de debajo ("status_bar") se quito en 2026-10.
	"top_left": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 14, "top": 14, "right": 0, "bottom": 0},
		"max_size": Vector2(300, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	"left_panel": {
		"anchor": Rect2(0, 0, 0, 1),
		"margin": {"left": 10, "top": 186, "right": 0, "bottom": 10},
		"max_size": Vector2(354, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "ResourceHUD",
	},
	## Pestana SANDBOX (solo en ese modo): al pie de la columna izquierda, bajo lo
	## que haya en ella (poblacion, y la Tormenta cuando baja a la
	## izquierda). Se apila tras el globo de los recursos, que a su vez va tras el
	## registro: oculto cualquiera de los dos, ocupa su sitio. `margin.top` es el
	## hueco que tenia antes de apilarse, por si ninguno existe.
	"sandbox_tab": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 228, "right": 0, "bottom": 0},
		"max_size": Vector2(120, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "HelperPanel.tip_resources",
		"gap": 8,
	},
	## Columna central: la fase de la Tormenta. La franja de objetivo que iba
	## debajo ("top_center") se quito el 2026-10-05: el siguiente paso es ¿QUE
	## HACER?, en el menu ☰.
	## La Tormenta va ARRIBA: cuando hay ceniza en camino es lo mas importante
	## de la pantalla y el jugador tiene que leerla sin buscarla. En calma el
	## indicador se oculta.
	"storm_banner": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 8, "right": 0, "bottom": 0},
		"max_size": Vector2(380, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	## El boton de velocidad x1 / x2 (GameSpeedButton): bajo la Tormenta, y en
	## calma (la Tormenta oculta) en su sitio, arriba en el centro.
	"speed_button": {
		"anchor": Rect2(0.5, 0, 0.5, 0),
		"margin": {"left": 0, "top": 8, "right": 0, "bottom": 0},
		"max_size": Vector2(64, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "StormHUD",
		"gap": 6,
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
		"margin": {"left": 0, "top": 210, "right": 18, "bottom": 112},
		"max_size": Vector2(360, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "sidebar_buttons",
		"gap": 8,
	},
	## Insignia del rango del gobernador: a la izquierda del ☰ redondo (PauseMenu:
	## 54 px + 14 de margen + 8 de hueco), en la misma franja (rediseno 2026-10).
	"rank_badge": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 14, "right": 76, "bottom": 0},
		"max_size": Vector2(200, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	## La Tormenta, un icono redondo solo, debajo del ☰ (docs/28 §12): 14 + 54 +
	## 8 de alto; centrada bajo el ☰ (54 - 50) / 2 = 2. La Orden de la Regencia se
	## despliega debajo, hacia la izquierda.
	"storm_icon": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 76, "right": 16, "bottom": 0},
		"max_size": Vector2(0, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	## La barra de abajo (BottomBar): Ejercito y Misiones a la izquierda de
	## CONSTRUIR, Mercado, Investigar y Ayuda a la derecha. Centrada y con el
	## mismo margen de abajo que CONSTRUIR (bottom_center): el hueco del centro
	## mide lo que CONSTRUIR.
	"bottom_bar": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 20},
		"max_size": Vector2.ZERO,
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	## ¿QUE HACER? como una linea plegable con la cara de la Capitana (docs/28
	## §12), abajo a la izquierda. `above_dpad`: con la cruceta en pantalla
	## (tablet) sube por encima de ella (UILayoutManager.get_slot).
	## Encima de la barra de abajo (2026-10-19): en la misma fila se montaba sobre
	## Ejercito / Misiones con textos largos (20 + 64 del redondo + nombre + 12).
	"next_step": {
		"anchor": Rect2(0, 1, 0, 1),
		"margin": {"left": 14, "top": 0, "right": 0, "bottom": 118},
		"max_size": Vector2(0, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
		"above_dpad": true,
	},
	"center_modal": {
		"anchor": Rect2(0.5, 0.5, 0.5, 0.5),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 0},
		"max_size": Vector2(1000, 660),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BOTH,
	},
	## La columna de avisos (NotificationPanel, Bryan 2026-10-18): el UNICO
	## sitio de los avisos, logros y ascensos. Bajo los recursos (y bajo la
	## Tormenta cuando esta baja a la izquierda): se apila tras el registro,
	## que casi siempre esta oculto y le cede su sitio (y abierto, los avisos
	## esperan). Lejos de CONSTRUIR y su
	## consejo (abajo al centro), de ¿QUE HACER? y la insignia (arriba a la
	## derecha) y de la cruceta (abajo a la izquierda: NotificationPanel.capacity
	## deja uno si no caben dos).
	"toast_area": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 186, "right": 0, "bottom": 0},
		"max_size": Vector2(330, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"grow_v": Control.GROW_DIRECTION_END,
		"stack_after": "NotificationPanel.log",
		"gap": 8,
	},
	"bottom_center": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 20},
		"max_size": Vector2(250, 0),
		"grow_h": Control.GROW_DIRECTION_BOTH,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
	## El boton ESCARAMUZAS (SkirmishButton), a la derecha de CONSTRUIR en la
	## misma franja de abajo: media anchura de CONSTRUIR (240 / 2) + 12 de hueco.
	"skirmish_button": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 132, "top": 0, "right": 0, "bottom": 20},
		"max_size": Vector2(176, 0),
		"grow_h": Control.GROW_DIRECTION_END,
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
		# Bajo la columna de avisos (vacia mide 0 y el globo queda donde estaba).
		"stack_after": "NotificationPanel.toasts",
		"gap": 8,
		"follow_moved": true,
	},
	## "tip_center" (el globo bajo la franja de objetivo) se quito con ella el
	## 2026-10-05: la ayuda del objetivo sale junto al menu ☰ (tip_top_right).
	## A la izquierda del boton "☰ MENU" (PauseMenu: 118 px + 10 de margen +
	## 10 de hueco).
	"tip_top_right": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 76, "right": 76, "bottom": 0},
		"max_size": Vector2(280, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_END,
	},
	## Encima del boton CONSTRUIR (bottom_center: 20 de margen + 64 de boton
	## + 12 de hueco; ConstructionMenu.BUILD_BTN_H).
	"tip_bottom_center": {
		"anchor": Rect2(0.5, 1, 0.5, 1),
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 96},
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
		# Por encima de girar + zoom (dos filas de ~60 px + margen 20).
		"margin": {"left": 0, "top": 0, "right": 20, "bottom": 190},
		"max_size": Vector2(230, 0),
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"grow_v": Control.GROW_DIRECTION_BEGIN,
	},
}

## Por debajo de este ancho de viewport (movil en vertical, 400x720) la columna
## central no cabe entre la izquierda (300 px) y el menu ☰: NARROW_SLOTS la baja
## a la columna izquierda, que queda recursos -> Tormenta -> registro. UILayoutManager.get_slot() mezcla estos cambios sobre
## SLOTS; lo que no se nombra aqui no cambia.
const NARROW_WIDTH := 720.0
## Solo la columna central tiene un umbral mas alto: centrada, la columna
## (440 px de referencia) empieza en ancho/2 - 220 y la columna izquierda acaba en 310. Por
## debajo de ~1060 px de lienzo se tocan (tablet 4:3: 960x720 o 1002x626 con la
## escala de tablet). Entre COLUMN_NARROW_WIDTH y NARROW_WIDTH solo bajan a la
## izquierda los slots de COLUMN_SLOTS; CONSTRUIR, avisos y globos no cambian.
const COLUMN_NARROW_WIDTH := 1080.0
const COLUMN_SLOTS := ["storm_banner", "left_panel"]
## Media anchura de la columna central y hueco minimo con la izquierda. Se
## midio con la franja de objetivo (440 px), ya quitada; la Tormenta (380 px)
## cabe de sobra y se deja asi para no mover los umbrales de las tablets.
const CENTER_COLUMN_HALF_WIDTH := 220.0
const COLUMN_GAP := 6.0
## Paneles cuyo ancho REAL marca el borde de la columna izquierda, y lo que
## ocupa el boton de pausa que va a su derecha (hueco + 44).
const LEFT_COLUMN_IDS := ["ResourceHUD"]
const PAUSE_GAP := 4.0
## El boton II de pausa ya no existe (menu unico, arriba a la derecha): la
## columna izquierda no reserva nada a su derecha.
const PAUSE_RESERVE := 0.0
## Lo que cambia SOLO con la columna bajada (no en movil): con la columna
## izquierda llena hasta media pantalla, los avisos suben desde abajo a la
## izquierda y la tapaban. Pasan al centro, encima de CONSTRUIR.
const COLUMN_NARROW_SLOTS := {
	## La Tormenta baja a la izquierda: la velocidad se queda arriba en el centro,
	## sin apilarse tras ella (cae en mitad de la columna izquierda).
	"speed_button": {"stack_after": ""},
}
const NARROW_SLOTS := {
	"storm_banner": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 62, "right": 0, "bottom": 0},
		"grow_h": Control.GROW_DIRECTION_END,
		"stack_after": "ResourceHUD",
	},
	## Rediseno 2026-10: la Tormenta ya no baja a esta columna (es un icono bajo
	## el ☰), asi que el registro sigue bajo los recursos.
	"left_panel": {
		"stack_after": "ResourceHUD",
	},
	## CONSTRUIR sube por encima de las flechas y del zoom: en 400 px de ancho
	## los tres no caben en la misma franja de abajo.
	"bottom_center": {
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 196},
	},
	## Los avisos, mas estrechos (uno a la vez, bajo la Tormenta como el registro).
	"toast_area": {"max_size": Vector2(300, 0)},
	## ESCARAMUZAS no cabe a la derecha de CONSTRUIR en 400 px: va centrado justo
	## encima (196 + 64 de CONSTRUIR + 8 de hueco), por debajo de los avisos.
	"skirmish_button": {
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 268},
		"grow_h": Control.GROW_DIRECTION_BOTH,
	},
	## La insignia del rango, bajo el boton ☰ MENU (10 + 48 + 6): a su izquierda
	## chocaria con la columna de recursos.
	"rank_badge": {
		"margin": {"left": 0, "top": 64, "right": 10, "bottom": 0},
		"max_size": Vector2(120, 0),
	},
	## Rediseno 2026-10: la Tormenta bajo la insignia (que va bajo el ☰); la barra
	## de abajo entera encima de CONSTRUIR (196 + 64 + 8; BottomBar esconde el
	## hueco central) y la linea del siguiente paso encima de la barra.
	"storm_icon": {
		"margin": {"left": 0, "top": 118, "right": 10, "bottom": 0},
	},
	## CONSTRUIR ya va dentro de la barra (BarBuild): la barra se ancla abajo
	## como en apaisado, no 268 px mas arriba (en vertical quedaba a media pantalla).
	"bottom_bar": {
		"margin": {"left": 0, "top": 0, "right": 0, "bottom": 20},
	},
	"next_step": {
		"margin": {"left": 10, "top": 0, "right": 0, "bottom": 118},
		"above_dpad": false,
	},
	## La velocidad, bajo la insignia del rango (el centro de arriba choca con
	## los recursos en 400 px).
	"speed_button": {
		"anchor": Rect2(1, 0, 1, 0),
		"margin": {"left": 0, "top": 118, "right": 10, "bottom": 0},
		"grow_h": Control.GROW_DIRECTION_BEGIN,
		"stack_after": "RankPanel",
	},
	## El globo del menu ☰ (con la guia de edificios) es el unico que cabe en
	## una pantalla estrecha: HelperPanel oculta los demas (NARROW_TIPS).
	"tip_top_right": {
		"anchor": Rect2(0, 0, 0, 0),
		"margin": {"left": 10, "top": 200, "right": 0, "bottom": 0},
		# 250 y no 280: a la derecha, en tactil, estan girar/zoom (x >= 272).
		"max_size": Vector2(250, 0),
		"grow_h": Control.GROW_DIRECTION_END,
		"stack_after": "NotificationPanel.toasts",
		"gap": 8,
	},
}

## ── Controles en pantalla (OnScreenControls) a su tamano (docs/21 §9) ──
## Huella de serie (100 %): la cruceta son 3 botones de 48 con 4 de hueco
## (152 x 152); la columna derecha, colocando, mide ~130 de ancho (CANCELAR) y
## 48 + 50 + 50 + 48 de botones con 3 huecos de 12 (232 de alto). 20 de margen.
const TOUCH_DPAD_SIDE := 152.0
const TOUCH_RIGHT_COLUMN_W := 130.0
const TOUCH_RIGHT_COLUMN_H := 232.0
const TOUCH_CONTROLS_MARGIN := 20.0
## Lo que se deja libre arriba para el boton ☰ MENU y la insignia del rango.
const TOUCH_TOP_RESERVE := 130.0
## Nunca por debajo de "Pequeno": mas chicos ya no se aciertan con el dedo.
const TOUCH_SCALE_FLOOR := 0.85

## Escala que de verdad cabe en un lienzo `vp` (puro): la pedida, salvo que la
## cruceta y la columna derecha no quepan lado a lado (movil en vertical, 400 de
## ancho) o la columna no quepa de alto bajo el menu. Asi nada se sale.
static func touch_controls_fit(requested: float, vp: Vector2) -> float:
	var s := requested
	if vp.x > 0.0:
		var w_room := vp.x - TOUCH_CONTROLS_MARGIN * 2.0 - 16.0
		s = minf(s, w_room / (TOUCH_DPAD_SIDE + TOUCH_RIGHT_COLUMN_W))
	if vp.y > 0.0:
		var h_room := vp.y - TOUCH_CONTROLS_MARGIN * 2.0 - TOUCH_TOP_RESERVE
		s = minf(s, h_room / TOUCH_RIGHT_COLUMN_H)
	return maxf(s, TOUCH_SCALE_FLOOR)

## Cuanto suben los slots que van encima de los controles (avisos, globos de la
## camara y del zoom; en pantalla estrecha tambien CONSTRUIR y ESCARAMUZAS)
## cuando los controles crecen por encima del 100 %. Puro.
static func touch_controls_lift(scale: float) -> float:
	return maxf(0.0, (scale - 1.0) * TOUCH_DPAD_SIDE)

## Si un slot va encima de los controles en pantalla: anclado abajo y, fuera de
## la pantalla estrecha, en una esquina (lo del centro abajo, CONSTRUIR y lo que
## se le apila, queda entre la cruceta y el zoom y no se toca).
static func sits_above_touch_controls(slot_name: String, slot: Dictionary, narrow: bool) -> bool:
	if slot_name == "bottom_controls" or not slot.has("anchor"):
		return false
	var a: Rect2 = slot["anchor"]
	if not is_equal_approx(a.position.y, 1.0):
		return false
	if narrow:
		return true
	return is_equal_approx(a.position.x, 0.0) or is_equal_approx(a.position.x, 1.0)

## Globos que siguen en pantalla estrecha. Seis globos en 400 px se tapan entre
## si y tapan el mapa; el de ☰ lleva a AYUDA y a la guia, y la intro del
## tutorial ya explica lo demas.
const NARROW_TIPS := ["HelperPanel.tip_menus"]

## Referencia virtual para `stack_after`: la columna de botones del menu ☰.
## Esos botones no pasan por apply_layout (cada panel coloca el suyo con
## get_sidebar_button_offset), asi que UILayoutManager calcula su borde
## inferior a partir de SIDEBAR_* y de si el menu esta desplegado.
const SIDEBAR_STACK_REF := "sidebar_buttons"

## Panel-to-slot assignment
const PANEL_SLOTS := {
	"ResourceHUD":                "top_left",
	## Rediseno 2026-10 (docs/28 §12): la Tormenta es un icono bajo el ☰.
	"StormHUD":                   "storm_icon",
	"BottomBar":                  "bottom_bar",
	"ObjectivePanel.line":        "next_step",
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
	"SettingsPanel.music_button": "sidebar_buttons",
	"HelperPanel.button":         "sidebar_buttons",
	"HelperPanel.modal":          "center_modal",
	"HelperPanel.tip_resources":  "tip_left",
	## La ayuda del objetivo senala ¿QUE HACER?, que vive en el menu ☰.
	"HelperPanel.tip_objective":  "tip_top_right",
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
	"SandboxPanel":               "sandbox_tab",
	"RankPanel":                  "rank_badge",
	"GameSpeedButton":            "speed_button",
	"RankPanel.modal":            "center_modal",
	"SkirmishButton":             "skirmish_button",
	"ContractPanel.modal":        "center_modal",
}

## Per-panel size overrides (when smaller than slot max_size)
## Anchos subidos ~25% para acompanar la tipografia mayor (FONT_BODY 13 -> 17).
## UILayoutManager los recorta al viewport, asi que en 400x720 no se salen.
const PANEL_SIZES := {
	"MarketPanel.modal":       Vector2(540, 0),
	"ProgressPanel.modal":     Vector2(470, 0),
	"ArmyPanel.modal":         Vector2(620, 0),
	"ContractPanel.modal":     Vector2(620, 0),
	"SkirmishPanel.modal":     Vector2(640, 0),
	## 1000: tres ramas y, a su derecha, la ficha de la tecnologia elegida.
	"TechTreePanel.modal":     Vector2(1000, 0),
	"ObjectivePanel":          Vector2(640, 560),
	"SettingsPanel.modal":     Vector2(640, 0),
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
	"SettingsPanel.music_button",
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
## Alto del boton "☰ MENU" (PauseMenu), que ocupa el sitio del antiguo ☰:
## el panel de edificio se apila debajo de el.
const SIDEBAR_TOGGLE_SIZE := 48
const SIDEBAR_FIRST_Y := 10
## Ancho del boton de menu lateral (los paneles lo usan para colocarse a -176).
const SIDEBAR_BTN_WIDTH := 164

## ── Telefono (rediseno 2026-10, docs/28 §4) ──
## Con CartoonTheme.phone (lienzo de menos de 450 de lado corto: 640x360,
## 800x360) UILayoutManager.get_slot() mezcla esto sobre SLOTS, antes que
## NARROW_SLOTS (vertical gana). Margenes de 8 al borde; el ☰ y los redondos
## miden 48, CONSTRUIR 52, la Tormenta 44:
##   arriba: recursos a la izquierda; rango a la izquierda del ☰ (8 + 48 + 6);
##           la Tormenta bajo el ☰ (8 + 48 + 6, centrada: 8 + 2).
##   abajo:  CONSTRUIR y la barra a 8 del borde; la linea del siguiente paso
##           encima de la barra (8 + 52 + 8).
const PHONE_SLOTS := {
	"top_left": {"margin": {"left": 8, "top": 8, "right": 0, "bottom": 0}},
	"rank_badge": {"margin": {"left": 0, "top": 8, "right": 62, "bottom": 0},
		"max_size": Vector2(128, 0)},
	"storm_icon": {"margin": {"left": 0, "top": 62, "right": 10, "bottom": 0}},
	"tip_top_right": {"margin": {"left": 0, "top": 62, "right": 62, "bottom": 0}},
	"bottom_center": {"margin": {"left": 0, "top": 0, "right": 0, "bottom": 8}},
	"bottom_bar": {"margin": {"left": 0, "top": 0, "right": 0, "bottom": 8}},
	"next_step": {"margin": {"left": 8, "top": 0, "right": 0, "bottom": 68}},
	"toast_area": {"margin": {"left": 8, "top": 186, "right": 0, "bottom": 0},
		"max_size": Vector2(300, 0), "gap": 6},
	"tip_bottom_center": {"margin": {"left": 0, "top": 0, "right": 0, "bottom": 68}},
}

## Lo que sube un slot `above_dpad` con la cruceta en pantalla: la cruceta de
## serie (TOUCH_DPAD_SIDE) y un hueco. Lo que crezca por encima del 100 % lo
## suma touch_controls_lift().
const ABOVE_DPAD_GAP := 10.0
