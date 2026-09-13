extends SceneTree
## Dev tool: rasteriza la marca del juego —emblema y banner— a PNG.
##
## El emblema sale directo del SVG. El banner se compone aqui porque lleva
## tipografia: las fuentes reales del juego, con tracking de verdad (Label no
## expone letter-spacing) y el emblema encajado a la izquierda.
##
## Uso (con ventana, NO headless: el banner se compone en un viewport):
##   godot --path . -s tools/render_brand.gd
##
## Salidas:
##   assets/branding/logo.png    512x512
##   assets/branding/banner.png  1600x500
##
## Companero de tools/render_branding.gd, que hace el key art.

const LOGO_SVG := "res://assets/branding/logo.svg"
const LOGO_PNG := "res://assets/branding/logo.png"
const BANNER_SVG := "res://assets/branding/banner.svg"
const BANNER_PNG := "res://assets/branding/banner.png"

const LOGO_SIZE := 512
const BANNER_W := 1600
const BANNER_H := 500
## El emblema dentro del banner: se rasteriza a su tamano final, no se reescala.
const MARK_SIZE := 300

func _initialize() -> void:
	var logo_img := _svg(LOGO_SVG, 512.0, LOGO_SIZE)
	if logo_img == null:
		_fail("no se pudo rasterizar " + LOGO_SVG)
		return
	var err := logo_img.save_png(LOGO_PNG)
	print("[brand] %s -> %dx%d (err %d)" % [LOGO_PNG, logo_img.get_width(), logo_img.get_height(), err])

	var mark_img := _svg(LOGO_SVG, 512.0, MARK_SIZE)
	var bg_img := _svg(BANNER_SVG, 1600.0, BANNER_W)
	if mark_img == null or bg_img == null:
		_fail("no se pudo rasterizar el banner")
		return

	DisplayServer.window_set_size(Vector2i(BANNER_W, BANNER_H))
	var root := get_root()
	# El proyecto usa stretch canvas_items sobre 1280x720; sin desactivarlo, este
	# lienzo se escala y se recorta.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(BANNER_W, BANNER_H)
	await process_frame
	await process_frame

	var painter := BannerPainter.new()
	painter.bg = ImageTexture.create_from_image(bg_img)
	painter.mark = ImageTexture.create_from_image(mark_img)
	painter.title_font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	painter.body_font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	painter.light_font = load("res://assets/fonts/Rajdhani-Medium.ttf")
	root.add_child(painter)
	painter.position = Vector2.ZERO
	painter.size = Vector2(BANNER_W, BANNER_H)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var shot := root.get_texture().get_image()
	err = shot.save_png(BANNER_PNG)
	print("[brand] %s -> %dx%d (err %d)" % [BANNER_PNG, shot.get_width(), shot.get_height(), err])
	quit(0)

func _fail(msg: String) -> void:
	printerr("[brand] " + msg)
	quit(1)

## Rasteriza un SVG a un ancho concreto. source_w es el width declarado del SVG.
func _svg(path: String, source_w: float, target_w: int) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var svg := f.get_as_text()
	f.close()
	var img := Image.new()
	if img.load_svg_from_string(svg, float(target_w) / source_w) != OK:
		return null
	return img


## Dibuja el banner a mano para controlar el tracking y la posicion exacta.
class BannerPainter extends Control:
	var bg: Texture2D
	var mark: Texture2D
	var title_font: Font
	var body_font: Font
	var light_font: Font

	const TITLE := "TORMENTA IMPERIAL"
	const TAGLINE := "Sobre el barro de la historia, construiremos monumentos de acero."
	const KICKER := "GESTION DIESELPUNK   ·   ESTRATEGIA POR TURNOS   ·   GODOT 4.7"

	const BRASS_HI := Color("#E8C468")
	const PARCHMENT := Color("#E8DBC7")
	const DIM := Color("#9A8A66")
	const RULE := Color("#C49629")

	## Columna de texto: empieza tras el emblema y respira hasta el borde.
	const TEXT_X := 452.0
	const TEXT_RIGHT := 1352.0

	func _draw() -> void:
		draw_texture_rect(bg, Rect2(Vector2.ZERO, Vector2(1600, 500)), false)
		draw_texture_rect(mark, Rect2(Vector2(96, 100), Vector2(300, 300)), false)

		var avail := TEXT_RIGHT - TEXT_X
		# El titulo manda: se encoge si no cabe, en vez de salirse del lienzo.
		var size := 78
		var tracking := 9.0
		while size > 40 and _tracked_width(title_font, TITLE, size, tracking) > avail:
			size -= 2

		_tracked(title_font, TITLE, size, tracking, TEXT_X, 254, Color(0, 0, 0, 0.8), Vector2(4, 5))
		_tracked(title_font, TITLE, size, tracking, TEXT_X, 254, BRASS_HI, Vector2.ZERO)

		# Filete de laton entre el titulo y el lema.
		draw_rect(Rect2(TEXT_X, 282, avail, 2), RULE * Color(1, 1, 1, 0.5))

		_left(body_font, TAGLINE, 29, TEXT_X, 330, PARCHMENT)
		_tracked(light_font, KICKER, 20, 2.5, TEXT_X, 378, DIM, Vector2.ZERO)

	func _tracked_width(font: Font, text: String, size: int, tracking: float) -> float:
		var total := 0.0
		for i in text.length():
			total += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if i < text.length() - 1:
				total += tracking
		return total

	## Dibuja desde x con separacion extra entre caracteres.
	func _tracked(font: Font, text: String, size: int, tracking: float,
			x0: float, baseline_y: float, color: Color, offset: Vector2) -> void:
		var x := x0 + offset.x
		for i in text.length():
			var ch := text[i]
			draw_string(font, Vector2(x, baseline_y + offset.y), ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + tracking

	func _left(font: Font, text: String, size: int, x0: float,
			baseline_y: float, color: Color) -> void:
		draw_string(font, Vector2(x0, baseline_y), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
