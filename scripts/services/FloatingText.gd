class_name FloatingText
## Static utility for spawning floating 3D text labels that animate upward and fade out.

static func spawn(scene_tree: SceneTree, world_pos: Vector3, text: String, color: Color) -> void:
	if not scene_tree or not scene_tree.current_scene:
		return
	var label := Label3D.new()
	label.text = text
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 3
	label.modulate = color
	scene_tree.current_scene.add_child(label)
	label.global_position = world_pos + Vector3(randf_range(-0.3, 0.3), 2.5, randf_range(-0.3, 0.3))
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", world_pos.y + 5.0, 1.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.8).set_delay(0.4)
	tween.tween_callback(label.queue_free)

static func spawn_resource(scene_tree: SceneTree, world_pos: Vector3, amount: int, res_name: String) -> void:
	var color: Color = GameConfig.resource_colors.get(res_name, Color.WHITE)
	spawn(scene_tree, world_pos, "+%d %s" % [amount, Tr.res_name(res_name)], color)
