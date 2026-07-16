extends MeshInstance3D
## User-facing toggle for the map grid overlay (the shader-based cell grid).
## Visibility follows the persisted user preference; BuildingPlacer still
## forces the grid on while placing a building and restores the preference after.

func _ready() -> void:
	visible = GameConfig.ui_grid_visible
	EventBus.grid_overlay_toggled.connect(func(vis: bool): visible = vis)
