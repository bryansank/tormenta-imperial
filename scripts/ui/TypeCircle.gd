extends Control
## El circulo de ventajas (paso 7 del combate guiado, docs/23 §2.4): las tres
## siluetas en triangulo y una flecha de quien gana a quien, leidas de
## GameConfig.combat_type_advantage.beats. Dibujado, sin imagen; si manana entra
## una cuarta unidad en `beats`, sale en el circulo sin tocar esto.

const ICON_PX := 42

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 176)

## Los tipos del circulo, en el orden de `beats`. Aire y mar (2026-10-17): cada
## medio tiene su circulo; por defecto el de tierra, que es el que ensena el
## combate guiado. Los cruces entre medios no salen aqui (estan en la ficha de
## cada unidad y en la ayuda "Aire y mar").
static func circle_ids(domain: String = "land") -> Array:
	var beats: Dictionary = GameConfig.combat_type_advantage.get("beats", {})
	var out: Array = []
	for id in beats:
		if GameConfig.get_unit_domain(String(id)) == domain:
			out.append(String(id))
	return out

## Las flechas: [ganador, perdedor] por cada pareja de `beats` dentro del medio.
static func arrows(domain: String = "land") -> Array:
	var beats: Dictionary = GameConfig.combat_type_advantage.get("beats", {})
	var out: Array = []
	for a in beats:
		if GameConfig.get_unit_domain(String(a)) != domain:
			continue
		for b in beats[a]:
			if GameConfig.get_unit_domain(String(b)) == domain:
				out.append([String(a), String(b)])
	return out

func _points(ids: Array) -> Dictionary:
	var c := size * 0.5 + Vector2(0, -6)
	var r := minf(size.x, size.y) * 0.34
	var out := {}
	for i in ids.size():
		var a := -PI * 0.5 + TAU * float(i) / float(maxi(1, ids.size()))
		out[ids[i]] = c + Vector2(cos(a), sin(a)) * r
	return out

func _draw() -> void:
	var ids := circle_ids()
	var at := _points(ids)
	var font := get_theme_default_font()
	var half := float(ICON_PX) * 0.5
	for pair in arrows():
		if not at.has(pair[0]) or not at.has(pair[1]):
			continue
		var p0: Vector2 = at[pair[0]]
		var p1: Vector2 = at[pair[1]]
		var dir := (p1 - p0).normalized()
		var from := p0 + dir * (half + 6.0)
		var to := p1 - dir * (half + 8.0)
		draw_line(from, to, UITheme.OUTLINE_COLOR, 6.0)
		draw_line(from, to, UITheme.POSITIVE, 3.0)
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([to + dir * 8.0, to - dir * 4.0 + n * 7.0, to - dir * 4.0 - n * 7.0]), UITheme.POSITIVE)
	for id in ids:
		var p: Vector2 = at[id]
		var tex := UITheme.unit_icon(id, ICON_PX)
		draw_circle(p, half + 4.0, UITheme.BG_DARK)
		if tex != null:
			draw_texture_rect(tex, Rect2(p - Vector2(half, half), Vector2(ICON_PX, ICON_PX)), false, UITheme.unit_icon_tint(true))
		if font != null:
			var label := Tr.t(String(GameConfig.get_unit_def(id).get("name", id)))
			var fs := UITheme.FONT_SMALL
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, p + Vector2(-w * 0.5, half + fs + 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.TEXT_BRIGHT)
