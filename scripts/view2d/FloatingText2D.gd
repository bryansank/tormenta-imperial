extends RefCounted
## Texto flotante de la vista 2D: una etiqueta que sube desde el edificio y se
## desvanece. Es la pareja 2D de FloatingText.spawn (Label3D); los servicios no
## la llaman nunca directamente, pasan por FloatingText.spawn_on(node, ...).

const View2D := preload("res://scripts/view2d/View2D.gd")

## Cuanto sube la etiqueta (pixeles de mapa) y cuanto dura.
const RISE_PX := 46.0
const DURATION := 1.8

static func spawn(anchor: Node2D, text: String, color: Color, offset: float = 0.0) -> void:
	if anchor == null or not anchor.is_inside_tree():
		return
	var tree := anchor.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene else anchor.get_parent()
	if parent == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 60
	label.z_as_relative = false
	parent.add_child(label)
	label.reset_size()
	var start: Vector2 = anchor.global_position + Vector2(offset * View2D.PX_PER_UNIT * 2.0 + randf_range(-4.0, 4.0), -18.0)
	label.position = start - Vector2(label.size.x * 0.5, label.size.y)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - RISE_PX, DURATION).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, DURATION).set_delay(0.4)
	tween.tween_callback(label.queue_free)
