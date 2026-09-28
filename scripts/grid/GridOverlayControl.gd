extends MeshInstance3D
## User-facing toggle for the map grid overlay (the shader-based cell grid).
## Visibility follows the persisted user preference; BuildingPlacer still
## forces the grid on while placing a building and restores the preference after.
##
## The plane and the shader are fitted to the REAL grid at runtime. The scene
## used to say "50x50 plane from (-25,-25)" while GridManager was 40 cells x 2.0
## units = 80x80 from (-40,-40), so the lines matched nothing. Reading the
## numbers from GridManager means the two cannot drift apart again.

## Extra half-width around the grid so the outermost lines are drawn whole
## instead of being cut in half by the plane's edge.
const EDGE_PAD := 0.2

func _ready() -> void:
	fit_to_grid()
	visible = GameConfig.ui_grid_visible
	EventBus.grid_overlay_toggled.connect(_on_grid_overlay_toggled)

func _on_grid_overlay_toggled(vis: bool) -> void:
	visible = vis

## Size the plane to the grid and align the shader's cell lines with
## GridManager's cell boundaries.
func fit_to_grid() -> void:
	var size: Vector2 = GridManager.get_world_size()
	var origin: Vector3 = GridManager.get_origin()
	if mesh is PlaneMesh:
		(mesh as PlaneMesh).size = size + Vector2(EDGE_PAD, EDGE_PAD) * 2.0
	# The plane is centred on its node: put the node in the middle of the grid.
	position.x = origin.x + size.x * 0.5
	position.z = origin.z + size.y * 0.5
	var mat := get_surface_override_material(0)
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("grid_origin", Vector2(origin.x, origin.z))
		(mat as ShaderMaterial).set_shader_parameter("cell_size", GridManager.cell_size)

## World-space size of the overlay plane (for tests and debugging).
func get_plane_size() -> Vector2:
	if mesh is PlaneMesh:
		return (mesh as PlaneMesh).size
	return Vector2.ZERO
