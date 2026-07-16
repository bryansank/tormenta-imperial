extends SceneTree
## Re-runnable tool: composites the dieselpunk metal 9-patch UI sprites
## (assets/textures/ui/*_metal.png, wired in UITheme) from the owned Poly Haven
## metal_plate texture (CC0) + a drawn brass frame with corner rivets.
## Run: godot --headless --path . --script res://tools/gen_ui_textures.gd

const SRC := "res://assets/textures/metal_plate_diff_1k.jpg"

var _src: Image

func _initialize() -> void:
	_src = Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if _src == null:
		print("GEN_FAIL: could not load source metal texture")
		return

	_make_panel("panel_metal.png", 128, 0.52, Color(1.06, 0.98, 0.82), 6, 14, true)
	_make_panel("panel_inset_metal.png", 96, 0.42, Color(1.0, 0.97, 0.85), 3, 8, false)
	_make_button("button_metal.png", 160, 56)
	print("GEN_DONE")

# ── Sample the metal texture at (x,y), darkened and warm-tinted ──
func _metal_px(x: int, y: int, darken: float, tint: Color) -> Color:
	var c := _src.get_pixel(x % _src.get_width(), y % _src.get_height())
	c = c.darkened(darken)
	return Color(clampf(c.r * tint.r, 0, 1), clampf(c.g * tint.g, 0, 1), clampf(c.b * tint.b, 0, 1), 1.0)

func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)

func _rivet(img: Image, cx: int, cy: int, r: int) -> void:
	var shadow := Color(0.12, 0.10, 0.06)
	var body := Color(0.62, 0.50, 0.22)
	var hi := Color(0.85, 0.72, 0.38)
	for y in range(cy - r - 1, cy + r + 2):
		for x in range(cx - r - 1, cx + r + 2):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x - cx, y - cy).length()
			if d <= r + 1 and d > r - 0.5:
				img.set_pixel(x, y, shadow)                       # dark ring
			elif d <= r - 0.5:
				# body with a top-left highlight for a domed look
				var lit := (x - cx) < 0 and (y - cy) < 0
				img.set_pixel(x, y, hi if lit and d < r * 0.6 else body)

func _make_panel(fname: String, s: int, darken: float, tint: Color, frame: int, rivet_inset: int, rivets: bool) -> void:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	# brushed-metal fill
	for y in s:
		for x in s:
			img.set_pixel(x, y, _metal_px(x, y, darken, tint))
	# brass frame: outer bright edge + inner dark line
	var brass := Color(0.50, 0.40, 0.16)
	var brass_dark := Color(0.20, 0.15, 0.06)
	# top/bottom bands
	_fill_rect(img, 0, 0, s, frame, brass)
	_fill_rect(img, 0, s - frame, s, s, brass)
	_fill_rect(img, 0, 0, frame, s, brass)
	_fill_rect(img, s - frame, 0, s, s, brass)
	# 1px dark inner separation line
	_fill_rect(img, frame, frame, s - frame, frame + 1, brass_dark)
	_fill_rect(img, frame, s - frame - 1, s - frame, s - frame, brass_dark)
	_fill_rect(img, frame, frame, frame + 1, s - frame, brass_dark)
	_fill_rect(img, s - frame - 1, frame, s - frame, s - frame, brass_dark)
	if rivets:
		_rivet(img, rivet_inset, rivet_inset, 3)
		_rivet(img, s - rivet_inset, rivet_inset, 3)
		_rivet(img, rivet_inset, s - rivet_inset, 3)
		_rivet(img, s - rivet_inset, s - rivet_inset, 3)
	img.save_png(ProjectSettings.globalize_path("res://assets/textures/ui/" + fname))

func _make_button(fname: String, w: int, h: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# lighter metal, with a subtle top-to-bottom bevel (brighter top)
			var bevel := 0.30 + 0.18 * (float(y) / float(h))   # darker toward bottom
			img.set_pixel(x, y, _metal_px(x, y, bevel, Color(1.12, 1.0, 0.82)))
	var brass := Color(0.52, 0.42, 0.18)
	var brass_dark := Color(0.18, 0.14, 0.06)
	var f := 4
	_fill_rect(img, 0, 0, w, f, brass)
	_fill_rect(img, 0, h - f, w, h, brass)
	_fill_rect(img, 0, 0, f, h, brass)
	_fill_rect(img, w - f, 0, w, h, brass)
	# top highlight line (bevel sheen) + bottom dark lip
	_fill_rect(img, f, f, w - f, f + 1, Color(0.9, 0.82, 0.55, 0.5))
	_fill_rect(img, f, h - f - 1, w - f, h - f, brass_dark)
	img.save_png(ProjectSettings.globalize_path("res://assets/textures/ui/" + fname))

func _process(_delta: float) -> bool:
	return true
