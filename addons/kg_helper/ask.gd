@tool
extends "bubble.gd"
# The ghost, asked without leaving Godot (#44): the same card as its speech, with a field for any
# question about Godot. It shows the answer in words, then a Show me button when the answer named
# something on screen: words first, then where. Esc closes it.

signal asked(said: String)
signal show_me
signal closed

const CREAM := Color("fff8e4")

var field: LineEdit
var ask_button: Button
var show_button: Button
var close_button: Button
var row: HBoxContainer


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	field = LineEdit.new()
	field.placeholder_text = "What is a shader? Where do I add a node?"
	var inside := StyleBoxFlat.new()
	inside.bg_color = CREAM
	inside.border_color = INK
	inside.set_border_width_all(int(round(1.5 * s)))
	inside.set_content_margin_all(6 * s)
	for state in ["normal", "focus", "read_only"]:
		field.add_theme_stylebox_override(state, inside)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", Color(INK, 0.55))
	field.add_theme_color_override("caret_color", INK)
	field.add_theme_font_size_override("font_size", int(16 * s))
	if _font(450):
		field.add_theme_font_override("font", _font(450))
	field.text_submitted.connect(func(text: String): asked.emit(text))
	add_child(field)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * s))
	ask_button = _button("Ask", true)
	ask_button.pressed.connect(func(): asked.emit(field.text))
	show_button = _button("Show me", true)
	show_button.pressed.connect(func(): show_me.emit())
	close_button = _button("Close", false)
	close_button.pressed.connect(close)
	for b in [ask_button, show_button, close_button]:
		row.add_child(b)
	add_child(row)
	visible = false


# Buttons are in the readable serif, never blackletter: oxblood for the main one, an outline for the rest.
func _button(text: String, main: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var box := StyleBoxFlat.new()
	box.bg_color = OXBLOOD if main else Color(0, 0, 0, 0)
	box.border_color = OXBLOOD if main else INK
	box.set_border_width_all(int(round(1.5 * s)))
	box.content_margin_left = 14 * s
	box.content_margin_right = 14 * s
	box.content_margin_top = 4 * s
	box.content_margin_bottom = 4 * s
	var over: StyleBoxFlat = box.duplicate()
	over.bg_color = OXBLOOD.lightened(0.12) if main else Color(INK, 0.08)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", over)
	b.add_theme_stylebox_override("pressed", over)
	for color in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(color, BONE if main else INK)
	b.add_theme_font_size_override("font_size", int(16 * s))
	if _font(750):
		b.add_theme_font_override("font", _font(750))
	return b


## Opens ready for a question.
func open(course: bool) -> void:
	_show("[b]Ask the ghost[/b]\nAnything about Godot." + (" Leave it empty if you're stuck on your lesson step." if course else "") + "\n[color=#1c221d99]Enter to ask, Esc to close.[/color]", true, false)
	ask_button.text = "Ask"
	field.text = ""
	field.grab_focus()


## Opens with a question already written about what he right-clicked; typing replaces it.
func ask_about(question: String, note: String) -> void:
	if note != "":
		say("[b]Ask the ghost[/b]\n%s\n[color=#1c221d99]Enter to ask, Esc to close.[/color]" % note, 300.0)
	field.text = question
	field.select_all()
	field.grab_focus()


func thinking() -> void:
	_show("", false, false)
	close_button.visible = false
	muse()


func saying(so_far: String) -> void:
	_show(so_far, false, false)
	close_button.visible = false


func answered(answer: String, can_show: bool) -> void:
	_show(answer, false, can_show)


## The question stays in the field, so Ask again sends it as it was.
func failed(why: String) -> void:
	_show(why, false, false)
	ask_button.text = "Ask again"
	ask_button.visible = field.text.strip_edges() != ""


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _show(text: String, asking: bool, can_show: bool) -> void:
	field.visible = asking
	ask_button.visible = asking
	show_button.visible = can_show
	close_button.visible = true
	visible = true
	say(text, 300.0)
	show_part(1.0)


func _fit() -> void:
	var pad := Vector2(14, 10) * s
	var gap := 8 * s
	row.reset_size()
	var field_h := field.get_combined_minimum_size().y if field.visible else 0.0
	under = (field_h + gap if field.visible else 0.0) + row.size.y + gap
	super()
	var y := pad.y + words.size.y + gap
	if field.visible:
		field.position = Vector2(pad.x, y)
		field.size = Vector2(wide, field_h)
		y += field_h + gap
	row.position = Vector2(pad.x, y)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		accept_event()
