class_name HudRegistry
## Registro central de los elementos del HUD: cuales se pueden ocultar desde
## Ajustes > Interfaz y cuales se pueden mover en "Editar disposicion".
##
## Para que un elemento nuevo entre:
##   1. Anadelo a ELEMENTS (id, clave Tr del nombre, hideable, movable, modo).
##      Si es movible, su id tiene que ser su panel_id de UILayoutConfig.
##   2. En el panel, DESPUES de add_child: HudRegistry.register("MiPanel", control).
##   3. Anade la clave Tr (ES y EN).
## Lo esencial (el menu ☰ y la pausa II) no se registra: no se puede ocultar.
##
## Ocultar no toca el `visible` del control, que es de su panel (el estado de
## poblacion se esconde solo hasta la fase de asentamiento, la Tormenta en
## calma...). En modo "holder" el control se mete en un Control contenedor a
## pantalla completa y lo que se oculta es el contenedor; en modo "visible"
## (elementos sueltos dentro de una columna, que nadie mas oculta) se usa
## `visible` directamente. El apilado de UILayoutManager ve el oculto como
## ausente (is_visible_in_tree) y compacta la columna.

const ELEMENTS := {
	"ResourceHUD": {"label": "HUD_RESOURCES", "hideable": true, "movable": true, "mode": "holder"},
	"NotificationPanel.status": {"label": "HUD_STATUS", "hideable": true, "movable": true, "mode": "holder"},
	"NotificationPanel.log_button": {"label": "HUD_LOG_BUTTON", "hideable": true, "movable": false, "mode": "visible"},
	"NotificationPanel.log": {"label": "HUD_LOG", "hideable": false, "movable": true, "mode": "holder"},
	"NotificationPanel.objective": {"label": "HUD_OBJECTIVE", "hideable": true, "movable": true, "mode": "holder"},
	"StormHUD": {"label": "HUD_STORM", "hideable": true, "movable": true, "mode": "holder"},
	"NotificationPanel.toasts": {"label": "HUD_TOASTS", "hideable": true, "movable": true, "mode": "holder"},
	"HelperPanel.callouts": {"label": "HUD_HELP", "hideable": true, "movable": false, "mode": "helper"},
	"BattleScreen.turn": {"label": "HUD_TURN", "hideable": true, "movable": false, "mode": "visible"},
	"ConstructionMenu.button": {"label": "HUD_BUILD_BUTTON", "hideable": false, "movable": true, "mode": "none"},
	"BuildingInfoPanel": {"label": "HUD_BUILDING_PANEL", "hideable": false, "movable": true, "mode": "none"},
	## La pestana SANDBOX (y su tarjeta, que la sigue). Solo existe en Sandbox:
	## fuera de ese modo su capa esta oculta y el editor no la enmarca.
	"SandboxPanel": {"label": "HUD_SANDBOX", "hideable": true, "movable": true, "mode": "holder"},
}

## Orden en Ajustes y en el editor.
const ORDER := [
	"ResourceHUD", "NotificationPanel.status", "NotificationPanel.log_button",
	"NotificationPanel.objective", "StormHUD", "NotificationPanel.toasts",
	"HelperPanel.callouts", "BattleScreen.turn", "SandboxPanel",
	"NotificationPanel.log", "ConstructionMenu.button", "BuildingInfoPanel",
]

## id -> WeakRef del control registrado mas reciente (y de su contenedor).
static var _controls := {}
static var _holders := {}

static func hideable_ids() -> Array:
	return ORDER.filter(func(id): return bool(ELEMENTS[id]["hideable"]))

static func movable_ids() -> Array:
	return ORDER.filter(func(id): return bool(ELEMENTS[id]["movable"]))

static func label_key(id: String) -> String:
	return String(ELEMENTS.get(id, {}).get("label", id))

## Registra un control ya metido en el arbol. Devuelve el contenedor (modo
## holder) o el propio control. Un id desconocido no rompe: avisa y no hace nada.
static func register(id: String, control: Control) -> Control:
	if not ELEMENTS.has(id):
		push_warning("HudRegistry: id desconocido '%s'" % id)
		return control
	_controls[id] = weakref(control)
	var mode := String(ELEMENTS[id]["mode"])
	var target: Control = control
	if mode == "holder":
		target = _wrap(id, control)
		_holders[id] = weakref(target)
	_apply(id)
	return target

static func _wrap(id: String, control: Control) -> Control:
	var parent := control.get_parent()
	if parent == null:
		push_warning("HudRegistry: '%s' se registra antes de add_child" % id)
		return control
	# Ya envuelto (registro repetido del mismo control).
	if parent.has_meta("hud_holder_id"):
		return parent as Control
	var holder := Control.new()
	holder.name = "Hud_" + id.replace(".", "_")
	holder.set_meta("hud_holder_id", id)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	var idx := control.get_index()
	parent.add_child(holder)
	parent.move_child(holder, idx)
	control.reparent(holder, false)
	return holder

static func control_of(id: String) -> Control:
	var ref: WeakRef = _controls.get(id, null)
	if ref == null:
		return null
	var c: Variant = ref.get_ref()
	return c as Control if c != null and is_instance_valid(c) else null

static func holder_of(id: String) -> Control:
	var ref: WeakRef = _holders.get(id, null)
	if ref == null:
		return null
	var c: Variant = ref.get_ref()
	return c as Control if c != null and is_instance_valid(c) else null

static func is_hidden(id: String) -> bool:
	if String(ELEMENTS.get(id, {}).get("mode", "")) == "helper":
		return not GameConfig.ui_helper_visible
	return id in GameConfig.ui_hud_hidden

## Oculta o muestra un elemento, lo guarda y lo aplica al momento.
static func set_hidden(id: String, hidden: bool, persist: bool = true) -> void:
	if not ELEMENTS.has(id) or not bool(ELEMENTS[id]["hideable"]):
		return
	if String(ELEMENTS[id]["mode"]) == "helper":
		GameConfig.ui_helper_visible = not hidden
		if persist:
			GameConfig.save_user_settings()
		EventBus.helper_visibility_changed.emit(not hidden)
		return
	var list: Array = GameConfig.ui_hud_hidden
	if hidden and not id in list:
		list.append(id)
	elif not hidden:
		list.erase(id)
	if persist:
		GameConfig.save_user_settings()
	_apply(id)

## Todo a la vista (Restablecer de la pestana Interfaz).
static func show_all() -> void:
	GameConfig.ui_hud_hidden.clear()
	GameConfig.ui_helper_visible = true
	GameConfig.save_user_settings()
	EventBus.helper_visibility_changed.emit(true)
	for id in ELEMENTS:
		_apply(id)

static func _apply(id: String) -> void:
	var mode := String(ELEMENTS[id]["mode"])
	var hidden := is_hidden(id)
	match mode:
		"holder":
			var h := holder_of(id)
			if h != null:
				h.visible = not hidden
		"visible":
			var c := control_of(id)
			if c != null:
				c.visible = not hidden
