extends Control
## El sello de lacre de la Regencia, dibujado a mano (sin imagen): un borron de
## cera roja con el borde irregular, un anillo con el lema "NADA SE PIERDE" y
## una R en el centro. Lo usa PrologueScreen al pie de cada folio.
##
## Todo sale de _draw, asi que escala sin pixelarse con el tamano del control.

const MOTTO := "· NADA SE PIERDE · NADA SE PIERDE "

var wax := Color(0.55, 0.09, 0.07)
var wax_dark := Color(0.36, 0.05, 0.04)
var wax_light := Color(0.72, 0.2, 0.14)
var letter_font: Font = null
var ring_font: Font = null

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.5
	if r < 4.0:
		return
	# Borron de cera: un circulo con el borde ondulado, como el lacre que rebosa.
	var pts := PackedVector2Array()
	var n := 72
	for i in n:
		var a := TAU * float(i) / float(n)
		var k := 1.0 + 0.05 * sin(a * 7.0 + 0.6) + 0.03 * sin(a * 17.0) + 0.02 * cos(a * 11.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r * 0.97 * k)
	draw_colored_polygon(pts, wax)
	# Sombra y brillo: dos medias lunas que le dan relieve.
	draw_arc(c + Vector2(r * 0.04, r * 0.05), r * 0.8, 0.2, PI - 0.2, 40, wax_dark, r * 0.1, true)
	draw_arc(c - Vector2(r * 0.03, r * 0.04), r * 0.78, PI + 0.4, TAU - 0.4, 40, wax_light, r * 0.05, true)
	# El cuno: dos aros hundidos.
	draw_arc(c, r * 0.74, 0.0, TAU, 64, wax_dark, maxf(1.5, r * 0.04), true)
	draw_arc(c, r * 0.5, 0.0, TAU, 64, wax_dark, maxf(1.2, r * 0.03), true)
	# El lema en el anillo, letra a letra.
	if ring_font != null:
		var fs := int(maxf(6.0, r * 0.17))
		var ring_r := r * 0.62
		var count := MOTTO.length()
		for i in count:
			var a := -PI * 0.5 + TAU * float(i) / float(count)
			var pos := c + Vector2(cos(a), sin(a)) * ring_r
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			var ch := MOTTO.substr(i, 1)
			var w := ring_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(ring_font, Vector2(-w * 0.5, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, wax_dark)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# La R de la Regencia.
	if letter_font != null:
		var ls := int(r * 0.62)
		var sz := letter_font.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, ls)
		var base := c + Vector2(-sz.x * 0.5, ls * 0.34)
		draw_string(letter_font, base + Vector2(1.5, 1.5), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, ls, wax_dark)
		draw_string(letter_font, base, "R", HORIZONTAL_ALIGNMENT_LEFT, -1, ls, wax_light)
