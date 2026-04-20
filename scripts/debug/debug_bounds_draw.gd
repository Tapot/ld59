extends Node2D
# DEBUG: visualize monster field bounds — delete this file before commit


func _draw() -> void:
	var rect := Rect2(Globals.MONSTERS_FIELD_MIN, Globals.MONSTERS_FIELD_MAX - Globals.MONSTERS_FIELD_MIN)
	draw_rect(rect, Color(1, 0, 0, 0.4), false, 2.0)
	draw_circle(rect.position, 6.0, Color(1, 0, 0, 0.6))
	draw_circle(rect.position + rect.size, 6.0, Color(1, 0, 0, 0.6))
