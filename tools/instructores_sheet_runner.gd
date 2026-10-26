extends Node
## Pinta la hoja de contacto de los instructores: ver tools/instructores_sheet.gd.

const Bust := preload("res://scripts/ui/InstructorBust.gd")
const OUT := "res://docs/media/dev/instructores/hoja_contacto.png"
const SHEET := Vector2i(1560, 1840)

class _Face extends Control:
	var who := "colony"
	var mood := "happy"

	func _draw() -> void:
		var sz := minf(size.x, size.y)
		var center := size * 0.5
		draw_circle(center, sz * 0.5, Color("f7e7c4"))
		var h := sz * 2.15
		var w := h * 0.8
		var rect := Rect2(Vector2(size.x * 0.5 - w * 0.5, -0.1 * h), Vector2(w, h))
		if who == Bust.COMBAT:
			Bust._draw_bombarda(self, rect, mood)
		else:
			Bust._draw_ada(self, rect, mood)
		draw_arc(center, sz * 0.5 - 1.5, 0.0, TAU, 40, UITheme.ACCENT, 3.0, true)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := OUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var vp := SubViewport.new()
	vp.size = SHEET
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = UITheme.SURFACE.darkened(0.25)
	bg.size = Vector2(SHEET)
	vp.add_child(bg)
	var y := 10.0
	for who in Bust.WHO:
		_label(vp, Tr.t(Bust.name_key(who)), Vector2(12, y), 20)
		y += 30.0
		# 2x, de serie y teléfono, una fila cada uno.
		for row in [[2.0, false, 1], [1.0, false, 1], [1.0, true, 1], [1.0, false, -1]]:
			var sz: Vector2 = Bust.BASE_SIZE * float(row[0])
			var col_w := 254.0
			for i in Bust.EXPRESSIONS.size():
				var x := 12.0 + col_w * float(i)
				var b: Control = Bust.new()
				vp.add_child(b)
				b.custom_minimum_size = Vector2.ZERO
				b.size = sz
				b.position = Vector2(x, y)
				b.call("show_as", who, Bust.EXPRESSIONS[i], int(row[2]))
				b.set("mouth_open", bool(row[1]))
				if float(row[0]) >= 2.0:
					_label(vp, Bust.EXPRESSIONS[i], Vector2(x, y + sz.y + 2.0), 14)
			y += sz.y + (24.0 if float(row[0]) >= 2.0 else 8.0)
		# Teléfono: el pequeño y su 62 %, y la cara en círculo a 64 y 40 px.
		for i in Bust.EXPRESSIONS.size():
			var x := 12.0 + 254.0 * float(i)
			var px := x
			for s in [1.0, 0.62]:
				var sz: Vector2 = Bust.SMALL_SIZE * s
				var b: Control = Bust.new()
				vp.add_child(b)
				b.custom_minimum_size = Vector2.ZERO
				b.size = sz
				b.position = Vector2(px, y)
				b.call("show_as", who, Bust.EXPRESSIONS[i], 1)
				px += sz.x + 6.0
			for fpx in [64.0, 40.0]:
				var f := _Face.new()
				f.who = who
				f.mood = Bust.EXPRESSIONS[i]
				f.clip_contents = true
				f.size = Vector2(fpx, fpx)
				f.position = Vector2(px, y)
				vp.add_child(f)
				px += fpx + 4.0
		y += Bust.SMALL_SIZE.y + 22.0
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.crop(SHEET.x, mini(SHEET.y, int(y) + 4))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(out))
	print("instructores_sheet: ", ProjectSettings.globalize_path(out))
	get_tree().quit()

func _label(parent: Node, text: String, pos: Vector2, fs: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88))
	parent.add_child(l)
