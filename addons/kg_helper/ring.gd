@tool
extends Control
# A ring around the toolbar ghost, filled to how much of the Claude plan's limit is used, shown once
# it's nearly used up. It never moves, so reduce motion needs nothing.

const SHOW_FROM := 0.8
const RED_FROM := 0.95

var used := 0.0


func _init() -> void:
	name = "LimitRing"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Shows the ring for this share used, or hides it below SHOW_FROM (unless Claude Code warned).
func show_used(share: float, warned: bool) -> void:
	used = share
	visible = share >= 0.0 and (share >= SHOW_FROM or warned)
	queue_redraw()


func _draw() -> void:
	var s := EditorInterface.get_editor_scale()
	var width := 2.0 * s
	var radius := minf(size.x, size.y) / 2.0 - width
	var center := size / 2.0
	var theme := EditorInterface.get_editor_theme()
	var color := theme.get_color("error_color", "Editor") if used >= RED_FROM else theme.get_color("warning_color", "Editor")
	draw_arc(center, radius, 0.0, TAU, 48, Color(color, 0.25), width, true)
	draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(used, 0.0, 1.0), 48, color, width, true)
