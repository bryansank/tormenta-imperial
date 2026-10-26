extends Control
## La cara de un instructor en un circulo (Capitana Remache o Sargento
## Bombarda), sin animacion: el mismo dibujo de InstructorBust, recortado, como
## CartoonTheme.CaptainFace pero con los dos. La usan el final con eleccion
## (VictoryScreen) y el archipielago (v1.2).
##
## Rendimiento: un _draw que solo se repite al cambiar quien, el gesto o el
## tamano. Sin _process.

const Bust := preload("res://scripts/ui/InstructorBust.gd")

## Bust.COLONY (Capitana Remache) o Bust.COMBAT (Sargento Bombarda).
var who: String = Bust.COLONY:
	set(v):
		who = v
		queue_redraw()
## Uno de Bust.EXPRESSIONS.
var mood: String = "happy":
	set(v):
		mood = v
		queue_redraw()

static func make(who_id: String, mood_id: String, px: int) -> Control:
	var f = load("res://scripts/ui/InstructorFace.gd").new()
	f.who = who_id
	f.mood = mood_id
	f.custom_minimum_size = Vector2(px, px)
	f.size = Vector2(px, px)
	return f

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	var sz := minf(size.x, size.y)
	if sz <= 1.0:
		return
	var center := size * 0.5
	# El hueco de la cara, como CartoonTheme.CaptainFace (token de la piel).
	draw_circle(center, sz * 0.5, CartoonTheme.c("hud", "CARD_ALT"))
	var h := sz * 2.15
	var w := h * 0.8
	var rect := Rect2(Vector2(size.x * 0.5 - w * 0.5, -0.1 * h), Vector2(w, h))
	if who == Bust.COMBAT:
		Bust._draw_bombarda(self, rect, mood)
	else:
		Bust._draw_ada(self, rect, mood)
	draw_arc(center, sz * 0.5 - 1.5, 0.0, TAU, 40, CartoonTheme.sem("ACCENT"), 3.0, true)
