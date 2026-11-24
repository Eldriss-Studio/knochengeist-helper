@tool
extends AcceptDialog

const L := preload("l10n.gd")

const Brain := preload("brain.gd")
const Updates := preload("updates.gd")
const Menu := preload("menu.gd")
const WIDTH := 440.0
const GAP := 6
const QUIET := Color(1, 1, 1, 0.7)
const CANDLE := Color("e3b44a")
const UNCHECKED_SIGN_IN := "%s is installed. Your first question checks that you're signed in."
const STATUS_WORDS := {"ready": "Signed in to %s", "signed_out": "Not signed in to %s", "checking": "Checking %s…"}
const EFFORT_NAMES := {
	"low": "Low (answers soonest)",
	"medium": "Medium",
	"high": "High (thinks longest, answers slowest)",
}
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
var tool_list: OptionButton
var picked: GDScript               # the tool chosen in the list, saved or not
var brain_ref                      # the brain, for whether the tool in use is ready
var tool_state := ""               # the tool in use's check: ready, signed_out, checking…
var preview: RefCounted            # a check of a picked tool that isn't the one in use
var preview_state := ""
var status_box: VBoxContainer      # whether the picked tool is ready, under the list
var model_hint: Label              # for a tool that picks its own model
var effort_list: OptionButton
var effort_hint: Label             # for a tool that decides how long it thinks
var where_heading: Label
var less_motion: CheckBox
var check_updates: CheckBox
var pick: EditorFileDialog
var s := 1.0
signal sign_in(tool: GDScript)
signal install(tool: GDScript)


func _init(brain = null, claude_state := "", docs = null) -> void:
	title = L.t("Knochengeist settings")
	ok_button_text = L.t("Save")
	var cancel := add_cancel_button(L.t("Cancel"))
	s = EditorInterface.get_editor_scale()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0) * s
	box.add_theme_constant_override("separation", int(GAP * s))
	brain_ref = brain
	tool_state = claude_state
	picked = Brain.adapter()
	box.add_child(_heading(L.t("AI tool")))
	tool_list = OptionButton.new()
	for id in Brain.TOOLS:
		tool_list.add_item(L.t(Brain.TOOLS[id].LABEL))    # each says the plan it runs on
	tool_list.select(Brain.TOOLS.keys().find(Brain.tool()))
	tool_list.item_selected.connect(func(i: int): _pick(Brain.TOOLS.values()[i]))
	tool_list.tooltip_text = L.t("Answers come from the AI tool you pick. You sign in to it with your own plan.")
	tool_list.accessibility_name = L.t("AI tool")
	box.add_child(tool_list)
	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", int(GAP * s))
	box.add_child(status_box)
	if brain:
		brain.checked.connect(func(state: String, _path: String):
			tool_state = state
			if is_instance_valid(status_box):
				_show_status())
	# Model and Effort side by side: two short choices, one row
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", int(GAP * 2 * s))
	model_list = OptionButton.new()
	model_hint = _quiet("")
	effort_list = OptionButton.new()
	effort_hint = _quiet("")
	model_list.accessibility_name = L.t("Model")
	effort_list.accessibility_name = L.t("Effort")
	for column in [[L.t("Model"), model_list, model_hint], [L.t("Effort"), effort_list, effort_hint]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(GAP * s))
		var heading := _heading(column[0])
		heading.custom_minimum_size.x = 0
		col.add_child(heading)
		col.add_child(column[1])
		(column[2] as Label).custom_minimum_size.x = (WIDTH / 2.0 - GAP) * s     # half the window: still a width, so it wraps
		col.add_child(column[2])
		pair.add_child(col)
	box.add_child(pair)
	if docs and docs.state != "off":
		_docs_section(box, docs)
	where_heading = _heading("")
	box.add_child(where_heading)
	var row := HBoxContainer.new()             # the path, then its two buttons, on one line
	where = Label.new()
	where.name = "ToolPath"
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.mouse_filter = Control.MOUSE_FILTER_PASS       # its tooltip has the whole path
	row.add_child(where)
	var change := Button.new()
	change.text = L.t("Choose file…")
	change.pressed.connect(_browse)
	row.add_child(change)
	automatic = Button.new()
	automatic.text = L.t("Find automatically")
	automatic.pressed.connect(func():
		chosen_path = ""
		_show_found())
	row.add_child(automatic)
	box.add_child(row)
	how = _quiet("")
	box.add_child(how)
	less_motion = CheckBox.new()
	less_motion.text = L.t("Reduce motion")
	less_motion.button_pressed = Brain.less_motion()
	less_motion.tooltip_text = L.t("The ghost jumps to where it points instead of flying. It stays still while it thinks.")
	check_updates = CheckBox.new()
	check_updates.text = L.t("Check for updates")
	check_updates.button_pressed = Updates.on()
	check_updates.tooltip_text = L.t("Once a day, Knochengeist checks GitHub for a new version. If there is one, it shows in the ghost's menu. Nothing installs unless you choose it.")
	var options := HBoxContainer.new()          # two self-explaining switches, one line; the details are in their tooltips
	options.add_theme_constant_override("separation", int(GAP * 3 * s))
	options.add_child(less_motion)
	options.add_child(check_updates)
	box.add_child(_heading(L.t("Options")))
	box.add_child(options)
	add_child(box)
	for b in [change, automatic, less_motion, check_updates, get_ok_button(), cancel]:
		_named(b)
	confirmed.connect(_save)
	_pick(picked)


# Who answers: the AI, its plan and sign-in, and how much of its limit is used.
# Everything below the list follows the picked tool at once: its readiness, model and location.
func _pick(tool: GDScript) -> void:
	picked = tool
	_stop_preview()
	if picked != Brain.adapter():             # checked at once: whether it's there and signed in shouldn't wait for Save
		preview = Brain.new()
		preview.checking_tool = picked
		preview_state = "checking"
		preview.checked.connect(func(state: String, _path: String):
			preview_state = state
			if is_instance_valid(status_box):
				_show_status())
		preview.check()
	chosen_path = Brain.saved_setting(picked.PATH_SETTING)
	where_heading.text = L.t("%s location") % picked.NAME
	_show_status()
	_show_model()
	_show_found()
	if visible:
		reset_size.call_deferred()          # it fits the picked tool's sections, with no room left over


func _show_status() -> void:
	for old in status_box.get_children():
		old.queue_free()
	var tool_name: String = picked.NAME
	if brain_ref == null:
		return
	var in_use := picked == Brain.adapter()
	var source = brain_ref if in_use else preview
	var state := tool_state if in_use else preview_state
	var lines: PackedStringArray = source.plan_lines()
	var text: String = L.t(STATUS_WORDS.get(state, ""))
	if state == "ready" and not picked.CHECKS_SIGN_IN:
		text = L.t(UNCHECKED_SIGN_IN)
	text = text % tool_name if text != "" else Menu.state(false, state, tool_name)
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	if state != "checking":
		icon.texture = EditorInterface.get_editor_theme().get_icon("StatusSuccess" if state == "ready" else "StatusWarning", "EditorIcons")
		row.add_child(icon)
	var status := Label.new()
	status.text = text
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	if state == "missing":
		var install_button := Button.new()
		install_button.text = L.t("Install…")
		_named(install_button)
		install_button.pressed.connect(func(): install.emit(picked))
		row.add_child(install_button)
	if state == "signed_out":
		var button := Button.new()
		button.text = L.t("Sign in…")
		_named(button)
		button.pressed.connect(func(): sign_in.emit(picked))
		row.add_child(button)
	if state == "ready" and not lines.is_empty():
		status_box.add_child(_label(lines[0]))      # the plan it runs on
	status_box.add_child(row)
	if state != "ready":
		return
	var usage: String = source.usage_line()
	if usage != "":
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = float(source.limit.get("used", 0.0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6) * s
		var fill := StyleBoxFlat.new()
		fill.bg_color = CANDLE
		fill.set_corner_radius_all(int(3 * s))
		bar.add_theme_stylebox_override("fill", fill)
		status_box.add_child(bar)
	for line in lines.slice(1):
		status_box.add_child(_quiet(line))
	call_deferred("_fit")

func _show_model() -> void:
	model_list.clear()
	var models: Array = picked.MODELS
	model_list.visible = not models.is_empty()
	model_hint.visible = models.is_empty()
	model_hint.text = L.t(picked.MODEL_HINT) if models.is_empty() else ""
	for id in models:
		model_list.add_item(L.t(MODEL_NAMES.get(id, id.capitalize())))     # each says what it's for, in the list itself
	if not models.is_empty():
		model_list.select(maxi(0, models.find(picked.model_from(Brain.saved_setting(picked.MODEL_SETTING)))))
	effort_list.clear()
	effort_list.visible = not picked.EFFORTS.is_empty()
	effort_hint.visible = picked.EFFORTS.is_empty()
	effort_hint.text = L.t(picked.EFFORT_HINT) if picked.EFFORTS.is_empty() else ""
	effort_list.tooltip_text = L.t("Lower effort answers sooner. Higher effort thinks longer before it answers.")
	for level in picked.EFFORTS:
		effort_list.add_item(L.t(EFFORT_NAMES.get(level, level.capitalize())))
	effort_list.select(maxi(0, picked.EFFORTS.find(Brain.saved_setting(picked.EFFORT_SETTING))))
	call_deferred("_fit")

func _named(button: Button) -> void:
	button.accessibility_name = button.text


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


# Says which copy of the picked tool is used and how it was picked, so nothing is an empty box to guess about.
func _show_found() -> void:
	automatic.visible = chosen_path != ""
	if chosen_path != "":
		where.text = Brain._short(chosen_path)
		where.tooltip_text = chosen_path
		how.text = L.t("You chose this file.") if FileAccess.file_exists(chosen_path) else L.t("There's no file at this location. Choose another file, or use Find automatically.")
		return
	var at := Brain.find_for(picked)
	where.text = Brain._short(at) if at != "" else L.t("Not found")
	where.tooltip_text = at
	how.text = L.t("Found automatically.") if at != "" else L.t(picked.INSTALL_HINT)
	call_deferred("_fit")

func _browse() -> void:
	if pick == null:
		pick = EditorFileDialog.new()
		pick.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		pick.access = EditorFileDialog.ACCESS_FILESYSTEM
		pick.title = L.t("Choose the %s file") % picked.NAME
		pick.file_selected.connect(func(path: String):
			chosen_path = path
			_show_found())
		add_child(pick)
	pick.popup_file_dialog()


func _save() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(picked.PATH_SETTING, chosen_path)
	if not picked.MODELS.is_empty():
		settings.set_setting(picked.MODEL_SETTING, picked.MODELS[model_list.selected])
	if not picked.EFFORTS.is_empty():
		settings.set_setting(picked.EFFORT_SETTING, picked.EFFORTS[effort_list.selected])
	settings.set_setting(Brain.TOOL_SETTING, picked.ID)
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
	box.add_child(_heading(L.t("Godot docs")))
	var row := HBoxContainer.new()
	docs_icon = TextureRect.new()
	docs_icon.name = "DocsIcon"
	docs_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(docs_icon)
	docs_line = Label.new()
	docs_line.name = "DocsLine"
	docs_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # a long manual note wraps, not widens the window
	docs_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	docs_line.custom_minimum_size.x = (WIDTH - 40) * s
	row.add_child(docs_line)
	docs_retry = Button.new()
	docs_retry.name = "DocsRetry"
	docs_retry.text = L.t("Try again")
	_named(docs_retry)
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
	docs_line.tooltip_text = L.t("The ghost uses these Godot docs to check its answers. They're saved on this computer.")
	docs_line.mouse_filter = Control.MOUSE_FILTER_PASS
	docs.changed.connect(func(_state): _show_docs())
	if docs.manual:
		docs.manual.changed.connect(func(_state): _show_docs())
	_show_docs()


func _ready() -> void:
	call_deferred("_fit")                       # once shown, at the size of what it shows


# The window fits what it shows now: it shrinks when a picked tool has fewer choices, not only grows.
func _fit() -> void:
	if is_inside_tree():
		size.y = 0
		reset_size()


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


## A check of a tool picked before, still running, ends with it.
	call_deferred("_fit")

func _stop_preview() -> void:
	if preview:
		preview.stop_check()
	preview = null


func _exit_tree() -> void:
	_stop_preview()


func _notification(what: int) -> void:
	# back from installing or signing in to a picked tool in a terminal: look again
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and preview and preview_state not in ["checking", "ready"]:
		preview_state = "checking"
		_show_status()
		preview.check()


func _process(delta: float) -> void:
	_show_docs()
	if preview:
		preview.poll(delta)              # a picked tool being checked before Save

