@tool
extends RefCounted

const L := preload("l10n.gd")
# The walk-through: the ghost points at one thing on screen, waits for him to click it or type in it,
# then goes on to the next step, from a plan made ahead or by asking as it goes, to the end of what he
# wanted, like a tutor pointing over his shoulder. It can point inside dialogs too (Create New Node):
# each window gets its own ghost. What's on screen comes from screen.gd, through the plugin.

const Pointer := preload("pointer.gd")
const Hidden := preload("hidden.gd")
const Tags := preload("tags.gd")
const Menu := preload("menu.gd")
const ALONE := -1                # a walk the helper runs itself, with no course app
const SETTLE_S := 0.25
const LOOK_AGAIN_S := 0.15
const LOOKS_BEFORE_SKIPPING_AHEAD := 6
const LOOKS_BEFORE_ASKING := 20
const WALK_MAX := 15             # clicks in one walk-through, at most
const ALREADY_TYPED_S := 2.5     # a field pointed at again, left alone this long, counts as already typed

var h: Node                      # the plugin: the screen, the notes, the brain and the app link
var pointers := {}               # a window's id -> the ghost overlay in it
var walk_ask := 0                # the ask a walk-through started from; 0 when there's none
var walk_clicked: Array = []     # what he has clicked so far in it
var walk_plan: Array = []        # the clicks planned ahead, each { id, say }; empty when it asks as it goes
var walk_i := 0                  # which planned click he's on
var walk_closing := ""
var walk_tries := 0
var walk_target := ""
var walk_typed := ""             # a field he's typing in: its text when last looked at
var typed_for := 0.0
var typed_changed := false       # he changed the text since the ghost pointed at the field
var prefilled_for := 0.0         # how long a field the ghost points at has held its old text, untouched
var typed_in := {}               # field id -> what he typed there earlier in this walk
var next_in := -1.0              # counting down to asking for the next click
var switching := false
var leading := false             # the ring is on the way in (a menu, a tab, a section), not the step
var led := false                 # the step was reached through a way in
var menu_wait: PopupMenu         # a menu whose item is the step: picking it does the step
var menu_item := -1


func _init(plugin: Node) -> void:
	h = plugin


# The ghost overlay for a window (the editor itself, or a dialog), made the first time it's needed.
func _pointer_in(win: Window) -> Control:
	var key := win.get_instance_id()
	if pointers.has(key) and is_instance_valid(pointers[key]):
		return pointers[key]
	var p: Control = Pointer.new()
	p.ghost = h.ghost
	var base := EditorInterface.get_base_control()
	if win == base.get_window():
		base.add_child(p)
	else:
		win.add_child(p, false, Node.INTERNAL_MODE_BACK)      # not part of the dialog's own layout
	p.finished.connect(_pointed)
	pointers[key] = p
	return p


func point(id: String, text: String) -> void:
	stop_pointing()
	_clear_lead()
	if h.note and is_instance_valid(h.note):
		h.note.queue_free()
	walk_target = id
	var field_now = (h.fields[id] as WeakRef).get_ref() if h.fields.has(id) else null
	walk_typed = (field_now as LineEdit).text if field_now else ""      # what's already there isn't new typing
	typed_changed = false
	prefilled_for = 0.0
	typed_for = 0.0
	var win: Window = h.wins.get(id, EditorInterface.get_base_control().get_window())
	var p := _pointer_in(win)
	p.stays = h.fields.has(id)
	var thing = (h.nodes[id] as WeakRef).get_ref() if h.nodes.has(id) else null
	if thing is Control:
		Hidden.into_view(thing)
	p.point(h.places[id], text, thing as Control, _row_of(id))


# Rings the way to a step's thing that isn't on screen, or the menu item or tab that is the step.
func _lead(way: Dictionary, step: String) -> void:
	stop_pointing()
	_clear_lead()
	walk_target = ""
	if way.has("menu"):
		_wait_for_menu(way["menu"], way["item"])
	if way.get("native", false):
		led = true
		var menu := way["menu"] as PopupMenu
		h._note(L.t("Choose %s > %s in the menu bar at the top of the screen.") % [way["name"], menu.get_item_text(way["index"])], 60.0)
		return
	var kind: String = way["kind"]
	var is_step := kind == Hidden.ITEM or (kind == Hidden.TAB and step.begins_with("tab:"))
	leading = not is_step
	led = led or leading
	Hidden.show(way)
	var p := _pointer_in(EditorInterface.get_base_control().get_window())
	p.stays = kind == Hidden.ITEM               # only picking the item does the step, not any click on the menu
	p.point(way["place"], _step_label() if is_step else _way_in_label(way))


func _step_label() -> String:
	return "[b]%s[/b] " % (L.t("Step %d of %d:") % [walk_i + 1, walk_plan.size()]) + str(walk_plan[walk_i].get("say", "")).replace("[", "[lb]")


func _way_in_label(way: Dictionary) -> String:
	var named := str(way["name"]).replace("[", "[lb]")
	var first := "[b]%s[/b] " % L.t("First:")
	match way["kind"]:
		Hidden.MENU: return first + L.t("Open the %s menu.") % named
		Hidden.TAB: return first + L.t("Open the %s tab.") % named
	return first + (L.t("Open the %s section.") % named if named != "" else L.t("Open this section."))


func _wait_for_menu(menu: PopupMenu, item: int) -> void:
	menu_wait = menu
	menu_item = item
	menu_wait.id_pressed.connect(_menu_picked)


func _menu_picked(id: int) -> void:
	if id != menu_item:
		return                                # another item: not the step
	if walk_ask == 0:
		_clear_lead()                         # the walk ended while the menu waited
		return
	stop_pointing()
	_clear_lead()
	_step_done(str(walk_plan[walk_i].get("id", "")) if walk_i < walk_plan.size() else "")


# He did the step: it's added to what he clicked, and the walk looks for the next one.
func _step_done(called: String) -> void:
	walk_clicked.append(called)
	walk_i += 1
	_count_hidden()
	walk_tries = 0
	next_in = SETTLE_S


func _clear_lead() -> void:
	leading = false
	_stop_menu_wait()


func _stop_menu_wait() -> void:
	if is_instance_valid(menu_wait) and menu_wait.id_pressed.is_connected(_menu_picked):
		menu_wait.id_pressed.disconnect(_menu_picked)
	menu_wait = null
	menu_item = -1


func _count_hidden() -> void:
	if led:
		led = false
		h.answers.used(h.answer_record, "hidden")


# The row a list target names ("item:MeshInstance3D", "row:Player"), or "" for anything else.
static func _row_of(id: String) -> String:
	return _name_of(id) if id.begins_with("item:") or id.begins_with("row:") else ""


# Takes every ghost down without ending the walk-through.
func stop_pointing() -> void:
	switching = true
	for p in pointers.values():
		if is_instance_valid(p):
			p.stop()
	switching = false


func _pointed(clicked: bool, cancelled: bool, gave_up: bool, by_key: bool) -> void:
	if switching:
		return
	if walk_ask == 0 or cancelled:
		walk_ask = 0
		_clear_lead()
		return
	if gave_up:
		walk_ask = 0
		_clear_lead()
		h.answers.walk_ended(h.answer_record, "stopped")
		h._note(L.t("I'll stop here. Ask me again anytime."), 8.0)
		return
	if clicked and leading:
		leading = false                       # he opened the way in: look again for the step itself
		walk_tries = 0
		next_in = SETTLE_S
		return
	if clicked and menu_wait:
		return                                # the menu item's own signal does the step
	if clicked:
		_step_done(str(h.labels.get(walk_target, walk_target)))
		if by_key:
			h.answers.used(h.answer_record, "keys")
		return
	walk_tries = 0
	next_in = SETTLE_S


## Each frame: watches a field he was pointed at, and asks for the next click when it is time.
func tick(delta: float) -> void:
	# a text field he was pointed at: once he has typed and paused, go on
	if walk_ask != 0 and h.fields.has(walk_target) and next_in < 0.0:
		var field = (h.fields[walk_target] as WeakRef).get_ref()
		if field and (field as LineEdit).text != walk_typed:
			walk_typed = (field as LineEdit).text
			typed_changed = true
			typed_for = 0.0
		elif field and not typed_changed and walk_typed != "" and typed_in.get(walk_target, "") == walk_typed:
			# pointed back at a box that already holds text: if he leaves it, it was typed already
			prefilled_for += delta
			if prefilled_for > ALREADY_TYPED_S:
				prefilled_for = -INF
				stop_pointing()
				walk_i += 1
				walk_tries = 0
				next_in = 0.0
		elif field and typed_changed and walk_typed != "":
			typed_for += delta
			if typed_for > 1.2:
				walk_clicked.append("typed \"%s\" in %s" % [walk_typed, str(h.labels.get(walk_target, "the field"))])
				typed_in[walk_target] = walk_typed
				typed_changed = false             # counted once; waiting for the next click mustn't count it again
				stop_pointing()
				walk_i += 1
				walk_tries = 0
				next_in = 0.0
	if next_in >= 0.0:
		next_in -= delta
		if next_in < 0.0:
			_ask_next()


# Whether a plan step already done pointed at this same thing.
func _used_before(id: String) -> bool:
	for i in walk_i:
		if str(walk_plan[i].get("id", "")) == id:
			return true
	return false


func _ask_next() -> void:
	if walk_ask == 0 or (walk_ask != ALONE and not h.app_up):
		return
	var missing := ""
	# the clicks were planned ahead: go straight to the next one when it's where the plan said
	if walk_plan.size() > 0:
		if walk_i >= walk_plan.size():
			walk_ask = 0
			h.answers.walk_ended(h.answer_record, "finished")
			h._note(walk_closing.replace("[", "[lb]") if walk_closing != "" else L.t("That's it."), 7.0)
			return
		h._state()
		var step := str(walk_plan[walk_i].get("id", ""))
		var found: String = h._find(step)
		var at := walk_i
		if found == "" and (walk_tries >= LOOKS_BEFORE_SKIPPING_AHEAD or led or walk_clicked.is_empty()):
			var way := Hidden.way_in(step)
			if not way.is_empty():
				_lead(way, step)
				return
		# Not at once: right after a click the old screen is still up, and a later step may be on it.
		if found == "" and walk_tries >= LOOKS_BEFORE_SKIPPING_AHEAD:
			for j in range(walk_i + 1, walk_plan.size()):
				if h._changes_what_is_made(str(walk_plan[j - 1].get("id", ""))):
					break              # skipping a box to type in or an item to pick would make the wrong thing
				if _used_before(str(walk_plan[j].get("id", ""))):
					break              # the same box or button as a done step: the screen hasn't moved on, so it's not that step yet
				found = h._find(str(walk_plan[j].get("id", "")))
				if found != "":
					at = j
					break
		if found != "":
			walk_i = at
			point(found, "[b]%s[/b] " % (L.t("Step %d of %d:") % [at + 1, walk_plan.size()]) + str(walk_plan[at].get("say", "")).replace("[", "[lb]"))
			return
		walk_tries += 1
		if walk_tries < LOOKS_BEFORE_ASKING:
			next_in = LOOK_AGAIN_S
			return
		missing = _name_of(step)
		walk_plan = []                 # the plan and the screen disagree: ask as it goes from here
	if walk_clicked.size() >= WALK_MAX:
		walk_ask = 0
		h.answers.walk_ended(h.answer_record, "stopped")
		h._note(L.t("That was a long one. Ask me again if there's more to do."), 6.0)
		return
	var body: Dictionary = h._state()
	if walk_ask == ALONE:
		h.brain_for = "next"
		h.tags = Tags.new()
		h._run_claude(h._prompt("guide"), h._fill(h._prompt("turn"), {
			"wanted": h.walk_said.strip_edges() if h.walk_said.strip_edges() != "" else "help with what they are building",
			"answer": h.walk_answer,
			"clicked": "(nothing yet)" if walk_clicked.is_empty() else "".join(walk_clicked.map(func(c): return "\n- " + str(c))),
			"screen": h._screen(body, "point"),
		}))
		h._note(_cant_find(missing), 60.0, true)
		return
	body["ask"] = walk_ask
	body["clicked"] = walk_clicked
	if h.app.ask_next(body):
		h._note(_cant_find(missing), 60.0, true)
	else:
		walk_ask = 0


func next_came(result: int, code: int, reply) -> void:
	if walk_ask == 0:
		return
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		walk_ask = 0
		h.app.refuse()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not (reply is Dictionary):
		walk_ask = 0
		h._note(L.t("I lost track of where we were. Ask me again with %s.") % Menu.ask_keys(), 6.0)
		return
	next_reply(reply)


# What he'd call a step's thing: the id without its kind ("Scene > New Scene" for a menu item).
static func _name_of(id: String) -> String:
	return id.substr(id.find(":") + 1).trim_suffix(".")


# The note while the next click is worked out: "" (the ghost's own working line), or why it's asking.
func _cant_find(missing: String) -> String:
	return L.t("I can't find %s on your screen. I'll look for another way.") % missing.replace("[", "[lb]") if missing != "" else ""


# A plan whose first step isn't on screen yet: the walk looks for it (and the way to it) at once.
func begin(plan: Array, closing: String) -> void:
	walk_plan = plan
	walk_closing = closing
	walk_i = 0
	walk_tries = 0
	_clear_lead()
	led = false
	next_in = 0.0


# Points at a plan's first click and goes through the rest without asking: from an answer in Godot,
# from Show me in Godot on the course page, or from asking what's next once a walk went off plan.
# One click and no closing line isn't a plan (an "I'm stuck on my step" answer): it asks as it goes.
# Whether a plan's first click is the thing on screen with that id.
func starts_at(plan: Array, target: String) -> bool:
	return plan.size() > 0 and h._find(str(plan[0].get("id", ""))) == target


func follow(target: String, plan: Array, closing: String) -> void:
	if not starts_at(plan, target):
		plan = []                      # a plan that starts elsewhere would label this click with another's words
		closing = ""
	walk_plan = plan if plan.size() > 1 or closing != "" else []
	walk_closing = closing
	walk_i = 0
	walk_tries = 0
	var first := str(plan[0].get("say", "")) if plan.size() > 0 else ""
	var label := ("[b]%s[/b] " % (L.t("Step %d of %d:") % [1, walk_plan.size()])) if walk_plan.size() > 1 else "[b]%s[/b] " % L.t("First:")
	point(target, (label + first.replace("[", "[lb]")) if first != "" else h._say(target))


func next_reply(reply: Dictionary) -> void:
	var say := str(reply.get("say", "")).replace("[", "[lb]")
	h._state()                                  # where things are now
	var plan: Array = reply["steps"] if reply.get("steps") is Array else []
	var closing: String = reply["closing"] if reply.get("closing") is String else ""
	var on_screen: bool = reply.get("target") is String and h.places.has(reply["target"]) and walk_clicked.count(str(h.labels.get(reply["target"], ""))) < 2
	if on_screen and starts_at(plan, reply["target"]) and (plan.size() > 1 or closing != ""):
		follow(reply["target"], plan, closing)     # every click left came with it: no more questions
		return
	if on_screen:
		point(reply["target"], "[b]%s[/b] " % L.t("Next:") + say)
	elif plan.size() > 0 and not Hidden.way_in(str(plan[0].get("id", ""))).is_empty():
		begin(plan, closing)                   # its first click is in a menu, a tab or a folded section
	else:
		walk_ask = 0
		h._note(say if say != "" else L.t("That's it."), 7.0)
