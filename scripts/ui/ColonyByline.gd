extends HBoxContainer
## La firma del pais en los partes, la victoria y el tablero: la bandera pequena
## y el nombre, en una fila corta. No anade frases: el nombre va aparte, encima
## del titulo, asi el texto de cada parte no se alarga (regla de menos texto).
## Se repinta sola al oir colony_identity_changed.
##
##   var byline = preload("res://scripts/ui/ColonyByline.gd").new()
##   column.add_child(byline)

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")

const FLAG_PX := Vector2(36, 24)

var size_name := "small"
var color := Color.TRANSPARENT
var flag_px := FLAG_PX

var _flag: TextureRect
var _label: Label

func _init(p_size_name: String = "small", p_color: Color = Color.TRANSPARENT, p_flag_px: Vector2 = FLAG_PX) -> void:
	size_name = p_size_name
	color = p_color
	flag_px = p_flag_px
	name = "ColonyByline"
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)

func _ready() -> void:
	_flag = TextureRect.new()
	_flag.name = "BylineFlag"
	_flag.custom_minimum_size = flag_px
	_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flag.stretch_mode = TextureRect.STRETCH_SCALE
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flag)
	_label = UITheme.make_label("", size_name, UITheme.ACCENT if color.a == 0.0 else color)
	_label.name = "BylineName"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	EventBus.colony_identity_changed.connect(_on_identity_changed)
	refresh()

func _on_identity_changed(_n: String, _s: Dictionary) -> void:
	refresh()

func refresh() -> void:
	if _label == null:
		return
	_flag.texture = ColonyFlag.current_small_texture() if flag_px.x <= ColonyFlag.SMALL_W * 1.25 else ColonyFlag.current_texture()
	_label.text = RankManager.get_colony_name().to_upper()

func text() -> String:
	return _label.text if _label != null else ""
