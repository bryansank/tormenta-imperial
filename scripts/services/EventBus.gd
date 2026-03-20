extends Node
## Global signal bus for decoupled communication between systems.
## All game-wide events flow through here. Systems emit signals, others subscribe.

# ── Camera ──
signal camera_pan_requested(direction: Vector2)
signal camera_zoom_requested(amount: float)
signal camera_drag_moved(delta: Vector2)
