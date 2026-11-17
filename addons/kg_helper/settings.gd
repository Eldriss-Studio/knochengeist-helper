@tool
extends AcceptDialog

const Brain := preload("brain.gd")
const Updates := preload("updates.gd")
const WIDTH := 440.0
const GAP := 6
const QUIET := Color(1, 1, 1, 0.7)
const CANDLE := Color("e3b44a")
const MODEL_NAMES := {
	"sonnet": "Sonnet (suits most questions)",
	"fable": "Fable (answers best, uses your limit fastest)",
	"opus": "Opus (strong, uses your limit fast)",
	"haiku": "Haiku (lightest)",
}

var chosen_path := ""              # empty: found automatically
var where: Label
var how: Label
var automatic: Button
var model_list: OptionButton
var less_motion: CheckBox
var check_updates: CheckBox
var pick: EditorFileDialog
var s := 1.0
signal sign_in


func _init(brain = null, claude_state := "", docs = null) -> void:
	title = "Knochengeist settings"
	ok_button_text = "Save"
	add_cancel_button("Cancel")
	s = EditorInterface.get_editor_scale()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0) * s
	box.add_theme_constant_override("separation", int(GAP * s))
	if brain:
		_your_ai(box, brain, claude_state)
	box.add_child(_heading("Model"))
	model_list = OptionButton.new()
	for id in Brain.MODELS:
		model_list.add_item(MODEL_NAMES.get(id, id.capitalize()))     # each says what it's for, in the list itself
	model_list.select(Brain.MODELS.find(Brain.model()))
	box.add_child(model_list)
	if docs and docs.state != "off":
		_docs_section(box, docs)
	box.add_child(_heading("Claude Code location"))
	chosen_path = Brain.saved_setting(Brain.CLAUDE_PATH_SETTING)
	where = _label("")
	where.name = "ClaudePath"
	box.add_child(where)
	how = _quiet("")
	box.add_child(how)
	var row := HBoxContainer.new()
	var change := Button.new()
	change.text = "Change…"
	change.pressed.connect(_browse)
	row.add_child(change)
	automatic = Button.new()
	automatic.text = "Find automatically"
	automatic.pressed.connect(func():
		chosen_path = ""
		_show_found())
	row.add_child(automatic)
	box.add_child(row)
	less_motion = CheckBox.new()
	less_motion.text = "Reduce motion"
	less_motion.button_pressed = Brain.less_motion()
	box.add_child(_heading("Motion"))
	box.add_child(less_motion)
	box.add_child(_quiet("The ghost appears where it points instead of flying there, and stays still while it thinks."))
	check_updates = CheckBox.new()
	check_updates.text = "Check for updates"
	check_updates.button_pressed = Updates.on()
	box.add_child(_heading("Updates"))
	box.add_child(check_updates)
	box.add_child(_quiet("Once a day, it checks GitHub for a newer helper and offers it in its menu. It never updates on its own."))
	add_child(box)
	confirmed.connect(_save)
	_show_found()


# Who answers: the AI, its plan and sign-in, and how much of its limit is used.
func _your_ai(box: VBoxContainer, brain, claude_state: String) -> void:
	box.add_child(_heading("Account"))
	var lines: PackedStringArray = brain.plan_lines()
	box.add_child(_label(lines[0] if not lines.is_empty() else "Claude Code"))
	var signed_in := claude_state == "ready"
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess" if signed_in else "StatusWarning", "EditorIcons")
	row.add_child(icon)
	var status := Label.new()
	status.text = "Signed in to Claude Code" if signed_in else ("Not signed in" if claude_state == "signed_out" else "Not ready yet")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	if claude_state == "signed_out":
		var button := Button.new()
		button.text = "Sign in…"
		button.pressed.connect(func(): sign_in.emit())
		row.add_child(button)
	box.add_child(row)
	var usage: String = brain.usage_line()
	if usage != "":
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = float(brain.limit.get("used", 0.0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6) * s
		var fill := StyleBoxFlat.new()
		fill.bg_color = CANDLE
		fill.set_corner_radius_all(int(3 * s))
		bar.add_theme_stylebox_override("fill", fill)
		box.add_child(bar)
	for line in lines.slice(1):
		box.add_child(_quiet(line))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH, 0) * s        # a wrapped label needs a width, or it grows one word per line
	return label


# Every section starts the same way: a little room above its bold heading (no dividers).
func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_constant_override("line_spacing", 0)
	label.custom_minimum_size.y = 28 * s
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM      # the room goes above it
	label.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("bold", "EditorFonts"))
	return label


func _quiet(text: String) -> Label:
	var label := _label(text)
	label.modulate = QUIET
	return label


# Says which Claude Code is used and how it was picked, so nothing is an empty box to guess about.
func _show_found() -> void:
	automatic.visible = chosen_path != ""
	if chosen_path != "":
		where.text = Brain._short(chosen_path)
		how.text = "Set by you." if FileAccess.file_exists(chosen_path) else "There's no file at this path. Change it, or find it automatically."
		return
	var at := Brain.find_claude()
	where.text = Brain._short(at) if at != "" else "Not found"
	how.text = "Found automatically." if at != "" else "Install Claude Code from claude.com/claude-code, or choose where it is."


func _browse() -> void:
	if pick == null:
		pick = EditorFileDialog.new()
		pick.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		pick.access = EditorFileDialog.ACCESS_FILESYSTEM
		pick.title = "Where is Claude Code?"
		pick.file_selected.connect(func(path: String):
			chosen_path = path
			_show_found())
		add_child(pick)
	pick.popup_file_dialog()


func _save() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(Brain.CLAUDE_PATH_SETTING, chosen_path)
	settings.set_setting(Brain.MODEL_SETTING, Brain.MODELS[model_list.selected])
	settings.set_setting(Brain.LESS_MOTION_SETTING, less_motion.button_pressed)
	settings.set_setting(Updates.SETTING, check_updates.button_pressed)


# The class reference index: what it's doing now, a bar while it builds, and Try again if it failed.
var docs_node: Node
var docs_icon: TextureRect
var docs_line: Label
var docs_bar: ProgressBar
var docs_retry: Button


func _docs_section(box: VBoxContainer, docs: Node) -> void:
	docs_node = docs
	box.add_child(_heading("Godot docs"))
	var row := HBoxContainer.new()
	docs_icon = TextureRect.new()
	docs_icon.name = "DocsIcon"
	docs_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(docs_icon)
	docs_line = Label.new()
	docs_line.name = "DocsLine"
	row.add_child(docs_line)
	docs_retry = Button.new()
	docs_retry.name = "DocsRetry"
	docs_retry.text = "Try again"
	docs_retry.pressed.connect(func(): docs_node.start())
	row.add_child(docs_retry)
	box.add_child(row)
	docs_bar = ProgressBar.new()
	docs_bar.name = "DocsBar"
	docs_bar.max_value = 1.0
	docs_bar.show_percentage = false
	docs_bar.custom_minimum_size = Vector2(0, 6) * s
	var fill := StyleBoxFlat.new()
	fill.bg_color = CANDLE
	fill.set_corner_radius_all(int(3 * s))
	docs_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(docs_bar)
	box.add_child(_quiet("Made from your own Godot, so it always matches your version. It stays on this computer."))
	docs.changed.connect(func(_state): _show_docs())
	_show_docs()


func _show_docs() -> void:
	if not is_instance_valid(docs_node) or docs_line == null:
		return
	var state: String = docs_node.state
	docs_line.text = docs_node.status_line()
	var icons := {"ready": "StatusSuccess", "failed": "StatusError"}
	docs_icon.texture = EditorInterface.get_editor_theme().get_icon(icons[state], "EditorIcons") if icons.has(state) else null
	docs_icon.visible = icons.has(state)
	docs_retry.visible = state == "failed"
	docs_bar.visible = state == "building"
	docs_bar.indeterminate = state == "building" and docs_node.reading == 0.0
	docs_bar.value = docs_node.reading
	set_process(state == "building")


func _process(_delta: float) -> void:
	_show_docs()

