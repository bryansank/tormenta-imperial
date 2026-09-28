extends RefCounted
## Cuentas de la vista 2D: mundo (el de GridManager) <-> pixeles del mapa plano
## <-> pantalla. Todo estatico y puro, para que los tests fijen el mapeo sin
## abrir una ventana.
##
## El mundo es el de siempre: la rejilla de GridManager, en unidades de mundo
## sobre el plano XZ (40x40 celdas de 2.0, origen en -40,-40). La vista 2D lo
## pinta desde arriba: X del mundo -> X de pantalla, Z del mundo -> Y de pantalla,
## con PX_PER_UNIT pixeles por unidad. Asi "arriba" en 2D es "hacia -Z", que es
## hacia donde mira la camara 3D con giro cero: una partida se lee igual en las
## dos vistas.
##
## Se usa por preload (sin class_name) para no depender de la cache global de
## clases del editor.

## Pixeles de mapa por unidad de mundo. Con celdas de 2.0 salen 32 px por celda.
const PX_PER_UNIT := 16.0

## Distancia de camara 3D <-> zoom de Camera2D. La partida guarda "distance"
## (MonumentalCamera); la vista 2D la traduce con zoom = ZOOM_K / distance para
## que la misma partida abra con un encuadre parecido en las dos vistas.
const ZOOM_K := 36.0

static func cell_px() -> float:
	return GridManager.cell_size * PX_PER_UNIT

## Punto del mundo (Vector3, plano XZ) -> pixel del mapa 2D.
static func world_to_px(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z) * PX_PER_UNIT

## Pixel del mapa 2D -> punto del mundo sobre el suelo (Y = 0).
static func px_to_world(px: Vector2) -> Vector3:
	return Vector3(px.x / PX_PER_UNIT, 0.0, px.y / PX_PER_UNIT)

## Esquina superior izquierda de una celda, en pixeles.
static func cell_origin_px(cell: Vector2i) -> Vector2:
	var o: Vector3 = GridManager.get_origin()
	return Vector2(o.x + cell.x * GridManager.cell_size, o.z + cell.y * GridManager.cell_size) * PX_PER_UNIT

## Rectangulo en pixeles de una huella `size` con origen en `cell`.
static func footprint_rect_px(cell: Vector2i, size: Vector2i) -> Rect2:
	return Rect2(cell_origin_px(cell), Vector2(size) * cell_px())

## Centro en pixeles de una huella (el mismo que GridManager.building_center).
static func footprint_center_px(cell: Vector2i, size: Vector2i) -> Vector2:
	return world_to_px(GridManager.building_center(cell, size))

## Celda bajo un pixel del mapa, SIN recortar a la rejilla: fuera del mapa
## devuelve una celda invalida (GridManager.is_valid_cell dira que no). A
## diferencia de GridManager.world_to_cell, que recorta, aqui un clic en el agua
## no se convierte en un clic en la celda del borde.
static func px_to_cell(px: Vector2) -> Vector2i:
	var o: Vector3 = GridManager.get_origin()
	var cs: float = GridManager.cell_size
	return Vector2i(floori((px.x / PX_PER_UNIT - o.x) / cs), floori((px.y / PX_PER_UNIT - o.z) / cs))

## Pantalla -> pixel del mapa, con la transformacion de lienzo del viewport (la
## que pone la Camera2D). `canvas_xform` es viewport.get_canvas_transform().
static func screen_to_px(canvas_xform: Transform2D, screen_pos: Vector2) -> Vector2:
	return canvas_xform.affine_inverse() * screen_pos

static func screen_to_cell(canvas_xform: Transform2D, screen_pos: Vector2) -> Vector2i:
	return px_to_cell(screen_to_px(canvas_xform, screen_pos))

## Pixel del mapa -> pantalla.
static func px_to_screen(canvas_xform: Transform2D, px: Vector2) -> Vector2:
	return canvas_xform * px

## El mismo contrato que InputService.screen_drag_to_world_delta, en 2D: cuanto
## hay que mover el objetivo de la camara (en unidades de mundo XZ) para que el
## punto del mapa que estaba bajo `from_pos` acabe bajo `to_pos`.
static func screen_drag_to_world_delta(canvas_xform: Transform2D, from_pos: Vector2, to_pos: Vector2) -> Vector2:
	var a := screen_to_px(canvas_xform, from_pos)
	var b := screen_to_px(canvas_xform, to_pos)
	return (a - b) / PX_PER_UNIT

static func distance_to_zoom(distance: float) -> float:
	return ZOOM_K / maxf(distance, 0.001)

static func zoom_to_distance(zoom: float) -> float:
	return ZOOM_K / maxf(zoom, 0.001)
