@tool
extends Control
# The ghost that shows where to click (#44). It flies from his mouse to the thing in an arc, an
# inked ring draws itself around the thing like a pen stroke, and a small label names the action.
# It follows the thing if the layout moves, and stays until he clicks the thing, presses Esc, or
# half a minute passes. Other clicks don't end it, so a misclick doesn't lose the hint. It never
# takes a click itself. Colors are Knochengeist's own (identity/README.md), so it can't be mistaken
# for a part of Godot.

## clicked: he clicked the thing. cancelled: he pressed Esc. Neither: the thing went away, or time ran out.
signal finished(clicked: bool, cancelled: bool, gave_up: bool)

const Bubble := preload("bubble.gd")
const CANDLE := Color("e3b44a")
const INK := Color("1c221d")
const RING_S := 0.45            # the ring's pen stroke
const PULSE_S := 0.9            # each of the two pulses after it
const TYPE_CPS := 40.0          # the label types itself out
const LONGEST_S := 30.0
var longest_s := float(OS.get_environment("KG_HELPER_RING_S")) if OS.get_environment("KG_HELPER_RING_S") != "" else LONGEST_S

var ghost: Texture2D
var where := Callable()         # gives the thing's rect on screen now, or null once it's gone
var said := ""
var stays := false               # a text field: clicking it doesn't end the hint (he still has to type)
var s := 1.0                    # the editor's scale
var t := 0.0
var start := Vector2.ZERO
var fly_s := 0.8
var bubble: Control
var ring_a := PackedVector2Array()
var ring_b := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	s = EditorInterface.get_editor_scale()
	bubble = Bubble.new()
	bubble.visible = false
	add_child(bubble)


## Points at whatever `place` finds, saying `text` beside it.
func point(place: Callable, text: String) -> void:
	where = place
	said = text
	t = 0.0
	start = get_local_mouse_position()
	var r = _rect()
	if r == null:
		return
	var rect: Rect2 = r
	fly_s = clampf(start.distance_to(_rest(rect)) / (800.0 * s), 0.6, 1.4)
	if preload("brain.gd").less_motion():
		fly_s = 0.01                  # appears where it points instead of flying there
	ring_a = _ring(1)
	ring_b = _ring(2)
	bubble.say(text, 230.0)
	bubble.show_part(0.0)
	bubble.visible = false
	visible = true
	queue_redraw()


func stop(clicked := false, cancelled := false, gave_up := false) -> void:
	if not visible:
		return
	visible = false
	finished.emit(clicked, cancelled, gave_up)


func _rect():
	if not where.is_valid():
		return null
	var r = where.call()
	if r == null:
		return null
	return Rect2((r as Rect2).position - get_global_rect().position, (r as Rect2).size)


# Where the ghost settles: just below and to the right of the thing, leaning in; above or to the
# left instead when that would put it outside the window (a button at the bottom of a dialog).
func _rest(rect: Rect2) -> Vector2:
	var off := Vector2(20, 24) * s
	var room := 28.0 * s
	var at := rect.end + off
	if at.y + room > size.y:
		at.y = rect.position.y - off.y
	if at.x + room > size.x:
		at.x = rect.position.x - off.x
	return at.clamp(Vector2(room, room), size - Vector2(room, room))


# Where the card goes: beside the ghost, inside the window, and never over the thing or the ghost.
func _card_at(rect: Rect2, rest: Vector2) -> Vector2:
	var gap := 26.0 * s
	var edge := 8.0 * s
	var at := rest + Vector2(gap, -6 * s)
	if at.x + bubble.size.x + edge > size.x:
		at.x = rest.x - gap - bubble.size.x
	at = at.clamp(Vector2(edge, edge), (size - bubble.size - Vector2(edge, edge)).max(Vector2(edge, edge)))
	var keep_clear := rect.grow(10 * s).merge(Rect2(rest - Vector2(gap, gap), Vector2(gap, gap) * 2.0))
	if Rect2(at, bubble.size).intersects(keep_clear):
		var above := keep_clear.position.y - bubble.size.y - edge
		at.y = above if above >= edge else minf(keep_clear.end.y + edge, size.y - bubble.size.y - edge)
	return at


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	var r = _rect()
	if r == null:
		stop()
		return
	if t > longest_s:
		stop(false, false, true)
		return
	var landed := t - fly_s
	if landed > 0.0:
		var rest := _rest(r)
		bubble.visible = true
		bubble.position = _card_at(r, rest)
		bubble.show_part(clampf(landed * TYPE_CPS / maxf(1.0, said.length()), 0.0, 1.0))
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		stop(false, true)
	elif event is InputEventMouseButton and event.pressed and where.is_valid():
		var r = where.call()
		if r != null and (r as Rect2).has_point(event.global_position) and not stays:
			stop(true)


func _draw() -> void:
	var r = _rect()
	if r == null:
		return
	var rect: Rect2 = r
	var rest := _rest(rect)
	var u := clampf(t / fly_s, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	# the flight: an arc from his mouse, lifted in the middle, the ghost a little bigger mid-flight
	var mid := (start + rest) * 0.5 - Vector2(0, minf(start.distance_to(rest) * 0.2, 80.0 * s))
	var at := start.lerp(mid, u).lerp(mid.lerp(rest, u), u)
	var landed := t - fly_s
	if landed > 0.0:
		var ring := rect.grow(6 * s)
		_stroke(ring, ring_a, clampf(landed / RING_S, 0.0, 1.0), 1.0)
		_stroke(ring, ring_b, clampf((landed - RING_S * 0.6) / RING_S, 0.0, 1.0), 0.7)
		for i in 2:
			var p := (landed - RING_S * 1.6 - i * PULSE_S) / PULSE_S
			if p > 0.0 and p < 1.0:
				var e := 1.0 - pow(1.0 - p, 3.0)
				draw_rect(ring.grow(18 * s * e), Color(CANDLE, 0.6 * (1.0 - e)), false, 2.0 * s)
	if ghost:
		var big := 44.0 * s * (1.0 + 0.3 * sin(u * PI))
		var lean := lerpf(-0.75, -0.3, u) + (sin(landed * 2.2) * 0.04 if landed > 0.0 else 0.0)
		var bob := Vector2(0, sin(landed * 2.2) * 2.0 * s) if landed > 0.0 else Vector2.ZERO
		draw_set_transform(at + bob, lean, Vector2.ONE)
		draw_texture_rect(ghost, Rect2(-Vector2(big, big) * 0.5, Vector2(big, big)), false, Color(1, 1, 1, clampf(t / 0.15, 0.0, 1.0)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A hand-drawn pass around a rect: points on its outline, each pushed a little off, as unit
# offsets so the ring can follow the rect when it moves. `seed` makes each pass its own.
func _ring(seed: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919
	var pts := PackedVector2Array()
	var n := 44
	var from := rng.randf() * 0.1
	for i in n + 4:                        # a little past the start, like a pen overshooting
		var a := (from + float(i) / n) * TAU
		pts.append(Vector2(cos(a), sin(a)) * (1.0 + rng.randf_range(-0.05, 0.05)))
	return pts


func _stroke(ring: Rect2, unit: PackedVector2Array, shown: float, alpha: float) -> void:
	var count := int(unit.size() * shown)
	if count < 2:
		return
	var c := ring.get_center()
	var half := ring.size * 0.5
	var pts := PackedVector2Array()
	for i in count:
		# a squared-off circle: hugs a small button without swallowing its neighbours
		var d := unit[i]
		var k := pow(pow(absf(d.x), 4.0) + pow(absf(d.y), 4.0), -0.25) * d.length()
		pts.append(c + Vector2(d.x / d.length() * half.x, d.y / d.length() * half.y) * k)
	draw_polyline(pts, Color(INK, 0.55 * alpha), 6.0 * s, true)
	draw_polyline(pts, Color(CANDLE, alpha), 3.0 * s, true)
