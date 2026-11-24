@tool
extends "bubble.gd"

# The ghost, asked without leaving Godot (#44): the same card as its speech, with a field for any
# question about Godot. It shows the answer in words, then a Show me button when the answer named
# something on screen: words first, then where. Esc closes it.

signal asked(said: String)
signal show_me
signal closed
signal stopped
signal rated(helped: bool, note: String)
signal copied
signal opened(address: String)

const System := preload("system.gd")
const Markdown := preload("markdown.gd")
const COPY_ALL := 0
const SELECT_ALL := 1
const BOTTOM_MARGIN := 14.0
const CODE_FONT_SIZE := 15

const CREAM := Color("fff8e4")
const ASKING_HINT := "What is a shader? Where do I add a node?"

var field: LineEdit
var ask_button: Button
var show_button: Button
var close_button: Button
var stop_button: Button
var for_course := false            # opened with the lesson line, so Stop opens it the same way
var row: HBoxContainer
var following := false             # the box under an answer, for a follow-up
var rate_row: HBoxContainer        # Did this help? Yes / No, under a finished answer
var note_row: HBoxContainer        # what was wrong, after No
var note_field: LineEdit
var codes := PackedStringArray()
var answer_menu: PopupMenu


func _init() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_STOP
	words.mouse_filter = Control.MOUSE_FILTER_STOP
	words.fit_content = false        # its height is set in _fit, so a long answer scrolls
	words.scroll_following = true
	words.selection_enabled = true
	words.deselect_on_focus_loss_enabled = false   # the right-click menu takes focus, and must still copy the selection
	words.context_menu_enabled = false              # its own menu writes to the clipboard directly; this one goes through System
	words.focus_mode = Control.FOCUS_CLICK
	var mono := EditorInterface.get_editor_theme().get_font("source", "EditorFonts") if EditorInterface.get_editor_theme() else null
	if mono:
		words.add_theme_font_override("mono_font", mono)
	words.add_theme_font_size_override("mono_font_size", int(CODE_FONT_SIZE * s))
	words.add_theme_color_override("selection_color", Color(OXBLOOD, 0.25))
	words.gui_input.connect(_words_input)
	words.meta_clicked.connect(_link_clicked)
	answer_menu = PopupMenu.new()
	answer_menu.add_item(L.t("Copy"), COPY_ALL)
	answer_menu.add_item(L.t("Select all"), SELECT_ALL)
	answer_menu.id_pressed.connect(_menu_chose)
	add_child(answer_menu)
	field = LineEdit.new()
	field.placeholder_text = L.t(ASKING_HINT)
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
	ask_button = _button(L.t("Ask"), true)
	ask_button.pressed.connect(func(): asked.emit(field.text))
	show_button = _button(L.t("Show me"), true)
	show_button.pressed.connect(func(): show_me.emit())
	close_button = _button(L.t("Close"), false)
	close_button.pressed.connect(close)
	stop_button = _button(L.t("Stop"), false)
	stop_button.pressed.connect(_stop)
	for b in [ask_button, show_button, stop_button, close_button]:
		row.add_child(b)
	add_child(row)
	rate_row = HBoxContainer.new()
	rate_row.add_theme_constant_override("separation", int(8 * s))
	var quiet := Label.new()
	quiet.text = L.t("Did this help?")
	quiet.add_theme_color_override("font_color", Color(INK, 0.65))
	quiet.add_theme_font_size_override("font_size", int(14 * s))
	if _font(450):
		quiet.add_theme_font_override("font", _font(450))
	rate_row.add_child(quiet)
	var helped := _quiet_button(L.t("Yes"))
	helped.pressed.connect(func(): _rated(true, ""))
	var not_helped := _quiet_button(L.t("No"))
	not_helped.pressed.connect(func():
		rate_row.visible = false
		note_row.visible = true
		_fit()
		note_field.grab_focus())
	rate_row.add_child(helped)
	rate_row.add_child(not_helped)
	add_child(rate_row)
	note_row = HBoxContainer.new()
	note_field = LineEdit.new()
	note_field.placeholder_text = L.t("What was wrong? (optional)")
	for state in ["normal", "focus", "read_only"]:
		note_field.add_theme_stylebox_override(state, field.get_theme_stylebox(state))
	for color in ["font_color", "font_placeholder_color", "caret_color"]:
		note_field.add_theme_color_override(color, field.get_theme_color(color))
	note_field.add_theme_font_size_override("font_size", field.get_theme_font_size("font_size"))
	if _font(450):
		note_field.add_theme_font_override("font", _font(450))
	note_row.add_theme_constant_override("separation", int(8 * s))
	note_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_field.text_submitted.connect(func(text: String): _rated(false, text))
	note_row.add_child(note_field)
	var send := _button(L.t("Send"), false)
	send.pressed.connect(func(): _rated(false, note_field.text))
	note_row.add_child(send)
	add_child(note_row)
	_hide_rating()
	visible = false


# A small text button for the rating, so it never competes with Show me and Close.
func _quiet_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = L.t("Kept only on this computer")
	for color in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(color, Color(INK, 0.65) if color == "font_color" else OXBLOOD)
	b.add_theme_font_size_override("font_size", int(14 * s))
	if _font(750):
		b.add_theme_font_override("font", _font(750))
	return b


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
	for_course = course
	_show("[b]%s[/b]\n%s" % [L.t("Ask the ghost"), L.t("Anything about Godot.")] + (" " + L.t("Leave it empty if you're stuck on your lesson step.") if course else "") + "\n[color=#1c221d99]%s[/color]" % L.t("Enter to ask, Esc to close."), true, false)
	ask_button.text = L.t("Ask")
	field.text = ""
	field.grab_focus()


## Opens with a question already written about what he right-clicked; typing replaces it.
func ask_about(question: String, note: String) -> void:
	if note != "":
		say("[b]%s[/b]\n%s\n[color=#1c221d99]%s[/color]" % [L.t("Ask the ghost"), note, L.t("Enter to ask, Esc to close.")], 300.0)
	field.text = question
	field.select_all()
	field.grab_focus()


func thinking() -> void:
	_show("", false, false)
	close_button.visible = false
	stop_button.visible = true
	muse()


func saying(so_far: String) -> void:
	_show(_rendered(so_far), false, false)
	close_button.visible = false
	stop_button.visible = true


func _stop() -> void:
	stopped.emit()
	var question := field.text
	open(for_course)
	field.text = question
	field.caret_column = question.length()


func answered(answer: String, can_show: bool) -> void:
	_show(_rendered(answer), false, can_show)
	rate_row.visible = true
	following = true
	field.placeholder_text = L.t("Ask a follow-up…")
	field.text = ""
	field.visible = true
	_fit()


## A quiet line under the answer.
func note(text: String) -> void:
	say(words.text + "\n[color=#1c221d99]%s[/color]" % text.replace("[", "[lb]"), 300.0)
	show_part(1.0)
	_fit()


func _rendered(markdown: String) -> String:
	var shown := Markdown.render(markdown, L.t("Copy"))
	codes = shown["codes"]
	return shown["text"]


# The copy keys go through System before the words' own handler, which would write to the clipboard itself.
func _words_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_copy") and words.get_selected_text() != "":
		_copy(_without_copy_links(words.get_selected_text()))
		words.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		answer_menu.popup(Rect2i(Vector2i(words.get_screen_position() + event.position), Vector2i.ZERO))
		words.accept_event()


func _menu_chose(id: int) -> void:
	if id == SELECT_ALL:
		words.select_all()
	elif id == COPY_ALL:
		_copy(_without_copy_links(words.get_selected_text() if words.get_selected_text() != "" else words.get_parsed_text()))


# The selection holds each code block's Copy link as a line of its own; the copied text shouldn't.
func _without_copy_links(text: String) -> String:
	var lines := Array(text.split("\n"))
	return "\n".join(lines.filter(func(line): return line != L.t("Copy")))


func _link_clicked(meta) -> void:
	var said := str(meta)
	if said.begins_with("copy:"):
		var i := int(said.trim_prefix("copy:"))
		if i < codes.size():
			_copy(codes[i])
	elif said.begins_with("https://") or said.begins_with("http://"):
		System.open(said)
		opened.emit(said)


func _copy(text: String) -> void:
	System.copy(text)
	copied.emit()


func _rated(helped: bool, note: String) -> void:
	_hide_rating()
	say(words.text + "\n[color=#1c221d99]%s[/color]" % L.t("Thanks."), 300.0)
	show_part(1.0)
	rated.emit(helped, note.strip_edges())


func _hide_rating() -> void:
	rate_row.visible = false
	note_row.visible = false
	note_field.text = ""


## The question stays in the field, so Ask again sends it as it was.
func failed(why: String) -> void:
	_show(why, false, false)
	ask_button.text = L.t("Ask again")
	ask_button.visible = field.text.strip_edges() != ""


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _show(text: String, asking: bool, can_show: bool) -> void:
	_hide_rating()
	following = false
	field.placeholder_text = L.t(ASKING_HINT)
	field.visible = asking
	ask_button.visible = asking
	show_button.visible = can_show
	stop_button.visible = false
	close_button.visible = true
	visible = true
	say(text, 300.0)
	show_part(1.0)


func _fit() -> void:
	var pad := Vector2(14, 10) * s
	var gap := 8 * s
	row.reset_size()
	var field_h := field.get_combined_minimum_size().y if field.visible else 0.0
	var rating: Control = rate_row if rate_row.visible else (note_row if note_row.visible else null)
	if rating:
		rating.reset_size()
		if rating == note_row:
			rating.size.x = wide
	under = (field_h + gap if field.visible else 0.0) + row.size.y + gap + (rating.size.y + gap if rating else 0.0)
	tallest = get_parent_area_size().y - position.y - BOTTOM_MARGIN * s
	super()
	var y := pad.y + words.size.y + gap
	if field.visible and not following:
		field.position = Vector2(pad.x, y)
		field.size = Vector2(wide, field_h)
		y += field_h + gap
	row.position = Vector2(pad.x, y)
	y += row.size.y + gap
	if rating:
		rating.position = Vector2(pad.x, y)
		y += rating.size.y + gap
	if field.visible and following:
		field.position = Vector2(pad.x, y)
		field.size = Vector2(wide, field_h)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		accept_event()
