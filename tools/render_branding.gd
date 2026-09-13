extends SceneTree
## Dev tool: compone el key art final —ilustracion SVG mas tipografia con las
## fuentes reales del juego— y lo guarda como PNG.
##
## Uso (con ventana, NO headless: hace falta la GPU para rasterizar):
##   godot --path . -s tools/render_branding.gd
##
## Salida: assets/branding/keyart.png

const SVG_PATH := "res://assets/branding/keyart.svg"
const OUT_PATH := "res://assets/branding/keyart.png"
const W := 1600
const H := 900

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var root := get_root()
	# El proyecto usa stretch canvas_items sobre 1280x720; sin desactivarlo, este
	# lienzo de 1600x900 se escala y se recorta.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(W, H)
	await process_frame
	await process_frame

	var art := _load_svg(SVG_PATH, W)
	if art == null:
		print("[branding] no se pudo cargar el SVG")
		quit(1)
		return

	var painter := Painter.new()
	painter.art = art
	painter.title_font = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	painter.body_font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	painter.light_font = load("res://assets/fonts/Rajdhani-Medium.ttf")
	root.add_child(painter)
	painter.position = Vector2.ZERO
	painter.size = Vector2(W, H)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	print("[branding] %s -> %dx%d (err %d)" % [OUT_PATH, img.get_width(), img.get_height(), err])
	quit(0)

func _load_svg(path: String, target_width: int) -> ImageTexture:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var svg := f.get_as_text()
	f.close()
	var img := Image.new()
	if img.load_svg_from_string(svg, float(target_width) / 1600.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Dibuja todo a mano: asi la tipografia queda exactamente donde se quiere,
## con tracking real (Label no expone letter-spacing).
class Painter extends Control:
	var art: Texture2D
	var title_font: Font
	var body_font: Font
	var light_font: Font

	const TITLE := "TORMENTA IMPERIAL"
	const TAGLINE := "Sobre el barro de la historia, construiremos monumentos de acero."
	const SUBTITLE := "GESTION DIESELPUNK   ·   ESTRATEGIA POR TURNOS   ·   GODOT 4.7"

	const BRASS_HI := Color("#E8C468")
	const PARCHMENT := Color("#E8DBC7")
	const DIM := Color("#9A8A66")

	func _draw() -> void:
		draw_texture_rect(art, Rect2(Vector2.ZERO, Vector2(1600, 900)), false)

		# Titulo: sombra dura primero, luego el laton encima.
		_tracked(title_font, TITLE, 74, 14.0, 800, 806, Color(0, 0, 0, 0.8), Vector2(4, 5))
		_tracked(title_font, TITLE, 74, 14.0, 800, 806, BRASS_HI, Vector2.ZERO)

		# Lema.
		_centered(body_font, TAGLINE, 28, 800, 848, PARCHMENT)

		# Linea de credito bajo el arte.
		_tracked(light_font, SUBTITLE, 18, 3.0, 800, 884, DIM, Vector2.ZERO)

	## Dibuja centrado en center_x con separacion extra entre caracteres.
	func _tracked(font: Font, text: String, size: int, tracking: float,
			center_x: float, baseline_y: float, color: Color, offset: Vector2) -> void:
		var total := 0.0
		for i in text.length():
			total += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if i < text.length() - 1:
				total += tracking
		var x := center_x - total * 0.5 + offset.x
		for i in text.length():
			var ch := text[i]
			draw_string(font, Vector2(x, baseline_y + offset.y), ch,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + tracking

	func _centered(font: Font, text: String, size: int, center_x: float,
			baseline_y: float, color: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(center_x - w * 0.5, baseline_y), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
