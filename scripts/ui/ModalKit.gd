class_name ModalKit
## Piezas comunes de los menus y partes a pantalla completa (menu principal,
## pausa, derrota del asedio, partes de guerra). Todo sale de UITheme: aqui solo
## se decide la COLOCACION, que es lo que estas pantallas repetian a mano.
##
## Las pantallas nuevas no pasan por UILayoutConfig a proposito: ese archivo es
## de otro frente de trabajo, y un menu centrado no necesita ranura. Se recortan
## al viewport igual que hace UILayoutManager, para que en 400x720 no se salgan.

## Margen minimo a los bordes de pantalla.
const EDGE := 16.0

## Tarjeta de metal centrada, con su columna ya dentro. Devuelve la tarjeta; la
## columna es su primer hijo (`card.get_child(0)`).
static func make_card(separation: int = UITheme.SEPARATION) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", separation)
	card.add_child(column)
	return card

## Centra `card` en el viewport con un ancho maximo, recortado a la pantalla.
## El alto lo decide el contenido.
static func fit_center(card: Control, max_width: float, viewport_size: Vector2) -> void:
	var width: float = minf(max_width, maxf(viewport_size.x - EDGE * 2.0, 120.0))
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(width, 0)
	card.size = Vector2(width, 0)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.offset_left = -width * 0.5
	card.offset_right = width * 0.5
	card.offset_top = 0.0
	card.offset_bottom = 0.0

## Boton de menu: ancho completo de la columna, alto tactil.
static func make_menu_button(text: String, color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, UITheme.MIN_BTN_H + 6)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	UITheme.style_button(btn, color, UITheme.FONT_BUTTON)
	btn.pressed.connect(callback)
	return btn

## Etiqueta centrada que envuelve.
static func make_text(text: String, size: String = "body", color: Color = UITheme.TEXT) -> Label:
	var label := UITheme.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

## Fondo oscuro a pantalla completa que se traga los clics.
static func make_backdrop(alpha: float = 0.6) -> ColorRect:
	var rect := UITheme.make_backdrop()
	rect.color = Color(0.02, 0.02, 0.015, alpha)
	return rect

## Sello de tinta: texto en mayusculas dentro de un marco, girado. Lo usan los
## partes del Diezmo ("COBRADO" / "REPELIDO"). Devuelve un Control de tamano fijo
## para que el giro no descoloque la columna que lo contiene.
static func make_stamp(text: String, color: Color, degrees: float = -12.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 70)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stamp := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.border_color = color
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	stamp.add_theme_stylebox_override("panel", style)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UITheme.make_label(text, "title", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_child(label)
	holder.add_child(stamp)

	stamp.set_anchors_preset(Control.PRESET_CENTER)
	stamp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stamp.grow_vertical = Control.GROW_DIRECTION_BOTH
	stamp.rotation = deg_to_rad(degrees)
	# El pivote al centro se fija cuando el sello ya sabe cuanto mide.
	stamp.resized.connect(func(): stamp.pivot_offset = stamp.size * 0.5)
	holder.set_meta("stamp_text", text)
	return holder
