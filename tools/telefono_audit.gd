extends Node
## Auditor de pantalla pequeña (QA teléfono, docs/26 y docs/28 §4.1). Va junto a
## otra sonda de capturas (lo carga tools/telefono_probe.gd) y, cada 0,4 s, mira
## todo lo visible de la interfaz y anota, una vez por nodo:
##
##   toque    botón pulsable con un lado < 48 del lienzo (en teléfono, dp)
##   letra    Label/Button con letra efectiva < 12 (suelo de docs/28 §3.1)
##   corte    Label de una línea cuyo texto no cabe (recortado o con "…")
##   fuera    botón o texto que se sale del lienzo
##
## Escribe docs/media/dev/telefono/audit_<tag>.tsv (ignorada por git). No toca
## nada del juego: solo lee.

const OUT_DIR := "res://docs/media/dev/telefono"
const MIN_TOUCH := 48.0
const MIN_FONT := 12.0

var tag := "audit"
var _seen := {}
var _file: FileAccess
var _t := 0.0
var _counts := {"toque": 0, "letra": 0, "corte": 0, "fuera": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_file = FileAccess.open("%s/audit_%s.tsv" % [OUT_DIR, tag], FileAccess.WRITE)
	_file.store_line("tipo\tcapa\tnodo\ttexto\tdetalle")
	get_tree().root.tree_exiting.connect(_close)

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	var vp := get_viewport().get_visible_rect()
	for c in get_tree().root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl == null or not ctl.is_visible_in_tree():
			continue
		var r := ctl.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if not vp.intersects(r):
			continue
		if _clipped_out(ctl, r):
			continue
		if ctl is BaseButton:
			_check_button(ctl as BaseButton, r, vp)
		if ctl is Label or ctl is Button:
			_check_text(ctl, r, vp)

## Fuera de la parte visible de un ScrollContainer o de un padre que recorta.
func _clipped_out(ctl: Control, r: Rect2) -> bool:
	var p := ctl.get_parent()
	while p:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			if not (p as Control).get_global_rect().grow(1.0).encloses(r):
				return true
		p = p.get_parent()
	return false

func _check_button(b: BaseButton, r: Rect2, vp: Rect2) -> void:
	if b.disabled or b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	var s := r.size * _scale(b)
	if minf(s.x, s.y) < MIN_TOUCH:
		_note("toque", b, "%dx%d" % [roundi(s.x), roundi(s.y)])
	if not vp.grow(2.0).encloses(r):
		_note("fuera", b, _rect_str(r))

func _check_text(ctl: Control, r: Rect2, vp: Rect2) -> void:
	var text := String(ctl.get("text"))
	if text.strip_edges() == "":
		return
	var fs := float(ctl.get_theme_font_size("font_size"))
	if ctl is Label and (ctl as Label).label_settings:
		fs = float((ctl as Label).label_settings.font_size)
	var eff := fs * _scale(ctl)
	if eff < MIN_FONT:
		_note("letra", ctl, "%.1f" % eff)
	if ctl is Label:
		var l := ctl as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF and not text.contains("\n"):
			var font := l.get_theme_font("font")
			if l.label_settings and l.label_settings.font:
				font = l.label_settings.font
			if font:
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
				if w > l.size.x + 2.0 and (l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
					_note("corte", l, "%d de %d" % [roundi(l.size.x), roundi(w)])
	if not vp.grow(2.0).encloses(r):
		_note("fuera", ctl, _rect_str(r))

func _scale(ctl: Control) -> float:
	return absf(ctl.get_global_transform().get_scale().y)

func _rect_str(r: Rect2) -> String:
	return "x%d y%d %dx%d" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]

func _note(kind: String, ctl: Control, detail: String) -> void:
	var key := "%s|%s" % [kind, ctl.get_path()]
	if _seen.has(key):
		return
	_seen[key] = true
	_counts[kind] += 1
	var layer := ""
	var p: Node = ctl
	while p:
		if p is CanvasLayer:
			layer = String(p.name)
			break
		p = p.get_parent()
	var text := String(ctl.get("text")).replace("\n", " ").replace("\t", " ").left(40)
	if _file:
		_file.store_line("%s\t%s\t%s\t%s\t%s" % [kind, layer, String(ctl.name), text, detail])
		_file.flush()

func _close() -> void:
	if _file:
		_file.store_line("# total\t%s" % str(_counts))
		_file.close()
		_file = null
		print("telefono_audit: ", tag, " ", _counts)
