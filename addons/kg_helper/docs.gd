@tool
extends Node
# A keyword index of Godot's class reference for the Godot that's running, built from that Godot itself
# (`--doctool`), so it always matches its version and nothing is downloaded.

signal changed(state: String)

const Brain := preload("brain.gd")
const Bm25 := preload("bm25.gd")
const CHECK_EVERY_S := 1.0
const MEMBER_TAGS := ["method", "member", "signal", "theme_item", "constant", "annotation"]

var state := "off"                 # off, building, ready or failed
var reading := 0.0                 # while building: 0 while Godot writes the reference, then how much is read (0 to 1)
var classes := 0
var version := ""
var passages: Array = []           # { id, class, text }
var postings := {}                 # term -> PackedInt32Array of [passage, count, passage, count, ...]
var lengths := PackedInt32Array()
var manual: Node                   # the Godot manual for this version, which Settings reports with it
var known := {}                    # every class and member name in this Godot's reference, setters and parameters too
var class_at := {}                 # class name -> its own passage
var member_at := {}                # member name -> every passage of a member by that name
const PER_MEMBER := 2              # a member many classes share (play, _process) brings at most this many
var average := 1.0
var dump_pid := 0
var dump_dir := ""
var waited := 0.0
var task := -1


static func folder() -> String:
	var given := OS.get_environment("KG_HELPER_DOCS_DIR")
	return given if given != "" else OS.get_user_data_dir().path_join("kg_helper").path_join("docs")


static func running_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d.%s" % [v["major"], v["minor"], v["patch"], v["status"]]


func index_path() -> String:
	return folder().path_join(version).path_join("index-3.bin")   # 3: with every name, @ classes without their @ too, for the name check


## What Settings says about it.
func status_line() -> String:
	var godot := (version if version != "" else running_version()).rsplit(".", true, 1)[0]
	match state:
		"ready":
			return "Ready for Godot %s%s" % [godot, manual.status() if manual else ""]
		"building":
			return "Reading the class reference from Godot %s…" % godot if reading > 0.0 else "Asking Godot %s for its class reference…" % godot
		"failed":
			return "Couldn't build the class reference. Show log has why."
	return "Off"


static func _thousands(n: int) -> String:
	var digits := str(n)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Loads the index for this Godot, or builds it in the background when there's none yet.
func start() -> void:
	if OS.get_environment("KG_HELPER_DOCS") == "off" or state in ["building", "ready"]:
		return
	reading = 0.0
	version = running_version()
	if FileAccess.file_exists(index_path()):
		_set_state("building")
		task = WorkerThreadPool.add_task(_load_saved)
		set_process(true)
		return
	dump_dir = OS.get_cache_dir().path_join("kg_helper_doctool_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dump_dir)
	var godot := OS.get_environment("KG_HELPER_DOCTOOL")
	var program := godot if godot != "" else OS.get_executable_path()
	if OS.get_name() == "Windows" and program.get_extension().to_lower() in ["cmd", "bat"]:
		dump_pid = OS.create_process("cmd.exe", ["/d", "/c", program, "--headless", "--doctool", dump_dir])
	else:
		dump_pid = OS.create_process(program, ["--headless", "--doctool", dump_dir])
	if dump_pid <= 0:
		_fail("Couldn't start Godot to write its class reference.")
		return
	_set_state("building")
	set_process(true)


func _process(delta: float) -> void:
	if dump_pid > 0:
		waited += delta
		if waited < CHECK_EVERY_S:
			return
		waited = 0.0
		if OS.is_process_running(dump_pid):
			return
		dump_pid = 0
		task = WorkerThreadPool.add_task(_build)
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		set_process(false)
		if state == "building":
			_set_state("ready" if passages.size() > 0 else "failed")


func _exit_tree() -> void:
	if dump_pid > 0 and OS.is_process_running(dump_pid):
		OS.kill(dump_pid)
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


# On a worker thread: read every class file the dump wrote, then index and save.
func _build() -> void:
	var files: Array = []
	_collect(dump_dir, files)
	var found: Array = []
	var names := {}
	for k in files.size():
		_read_class(files[k], found, names)
		reading = float(k + 1) / files.size()
	_remove(dump_dir)
	if found.is_empty():
		call_deferred("_fail", "Godot wrote no class reference to read.")
		return
	_index(found)
	DirAccess.make_dir_recursive_absolute(index_path().get_base_dir())
	var file := FileAccess.open(index_path(), FileAccess.WRITE)
	if file:
		file.store_var({"version": version, "classes": classes, "passages": passages, "postings": postings, "lengths": lengths, "known": names})
	known = names
	call_deferred("_logged", "Built the class reference index for Godot %s: %d classes, %d passages." % [version, classes, passages.size()])


func _load_saved() -> void:
	var file := FileAccess.open(index_path(), FileAccess.READ)
	var saved = file.get_var() if file else null
	if not saved is Dictionary or str(saved.get("version", "")) != version:
		call_deferred("_fail", "The saved class reference index couldn't be read.")
		return
	classes = int(saved["classes"])
	passages = saved["passages"]
	postings = saved["postings"]
	lengths = saved["lengths"]
	known = saved.get("known", {})
	_names()
	average = Bm25.average_of(lengths)
	call_deferred("_logged", "Loaded the class reference index for Godot %s." % version)


func _collect(dir: String, into: Array) -> void:
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".xml"):
			into.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)


# One passage for the class (its brief description), and one per member, each starting with the class name.
func _read_class(path: String, into: Array, names: Dictionary) -> void:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		return
	var name := ""
	var member := ""
	var reading := ""
	var text := ""
	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				if tag == "class":
					name = xml.get_named_attribute_value_safe("name")
					names[name] = true
					names[name.trim_prefix("@")] = true       # @GlobalScope is written GlobalScope too
				elif tag == "param":
					names[xml.get_named_attribute_value_safe("name")] = true
				elif tag in MEMBER_TAGS:
					member = xml.get_named_attribute_value_safe("name")
					names[member] = true
					names[member.trim_prefix("@")] = true      # @export_range is written export_range too
					for also in ["setter", "getter"]:       # set_position() is a real call, though only position is listed
						if xml.get_named_attribute_value_safe(also) != "":
							names[xml.get_named_attribute_value_safe(also)] = true
					text = ""
					if tag == "member":
						reading = "member"
				elif tag == "brief_description" and member == "":
					reading = "brief"
					text = ""
				elif tag == "description" and member != "":
					reading = "member"
			XMLParser.NODE_TEXT:
				if reading != "":
					text += xml.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var tag := xml.get_node_name()
				if tag == "brief_description" and reading == "brief":
					into.append({"id": name, "class": name, "text": "%s: %s" % [name, _plain(text)]})
					reading = ""
				elif tag in MEMBER_TAGS and member != "":
					into.append({"id": "%s.%s" % [name, member], "class": name, "text": "%s %s: %s" % [name, member, _plain(text).left(400)]})
					member = ""
					reading = ""


func _plain(text: String) -> String:
	return text.replace("\n", " ").replace("\t", " ").replace("[code]", "").replace("[/code]", "").strip_edges()


func _index(found: Array) -> void:
	passages = found
	var names := {}
	for passage in passages:
		names[passage["class"]] = true
	var built := Bm25.build(passages.map(func(passage): return passage["text"]))
	postings = built["postings"]
	lengths = built["lengths"]
	average = built["average"]
	classes = names.size()
	_names()


## Lowercased words, with CamelCase and snake_case names split into their parts and kept whole too.
static func tokens(text: String) -> PackedStringArray:
	return Bm25.tokens(text)


## Whether this Godot's reference has a class or member by this name.
func knows(name: String) -> bool:
	return known.has(name)


func _names() -> void:
	class_at = {}
	member_at = {}
	for i in passages.size():
		var id := str(passages[i]["id"])
		if not id.contains("."):
			class_at[id] = i
		else:
			var member := id.get_slice(".", 1)
			if not member_at.has(member):
				member_at[member] = []
			member_at[member].append(i)


## The Godot names the text really uses: classes by their exact name, and members whose names have an
## underscore (move_and_slide, _process). A plain word like "play" or "timer" names nothing.
func named_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for found in RegEx.create_from_string("\\b[A-Z][A-Za-z0-9]*\\b").search_all(text):
		if class_at.has(found.get_string()) and not out.has(found.get_string()):
			out.append(found.get_string())
	for found in RegEx.create_from_string("\\b_?[a-z][a-z0-9]*(?:_[a-z0-9]+)+\\b|\\b_[a-z][a-z0-9]*\\b").search_all(text):
		if member_at.has(found.get_string()) and not out.has(found.get_string()):
			out.append(found.get_string())
	return out


## The passages a question needs, or none when it names nothing in Godot: the members it names first
## (in the classes it names, if any), then the classes themselves, then the best keyword matches
## from those classes, k at most.
func passages_for(text: String, k := 5) -> Array:
	if state != "ready":
		return []
	var names := named_in(text)
	if names.is_empty():
		return []
	var in_classes := Array(names).filter(func(n): return class_at.has(n))
	var picked: Array = []
	for name in names:
		if member_at.has(name):
			var hits: Array = member_at[name].filter(func(i): return in_classes.is_empty() or in_classes.has(passages[i]["class"]))
			hits.sort_custom(func(a, b): return str(passages[a]["class"]).length() < str(passages[b]["class"]).length())   # base classes (Node, Object) first
			for i in hits.slice(0, PER_MEMBER):
				if not picked.has(i):
					picked.append(i)
	for name in in_classes:
		if not picked.has(class_at[name]):
			picked.append(class_at[name])
	if picked.size() < k and not in_classes.is_empty():
		for hit in search(text, 20):
			var i: int = class_at.get(hit["id"], -1) if not str(hit["id"]).contains(".") else _index_of(str(hit["id"]))
			if i >= 0 and in_classes.has(passages[i]["class"]) and not picked.has(i):
				picked.append(i)
			if picked.size() >= k:
				break
	var out: Array = []
	for i in picked.slice(0, k):
		out.append({"id": passages[i]["id"], "class": passages[i]["class"], "text": passages[i]["text"]})
	return out


func _index_of(id: String) -> int:
	for i in member_at.get(id.get_slice(".", 1), []):
		if passages[i]["id"] == id:
			return i
	return -1


## The k passages that best match the words, best first (BM25).
func search(query: String, k := 5) -> Array:
	if state != "ready":
		return []
	var out: Array = []
	for hit in Bm25.rank(query, postings, lengths, average, k):
		var i: int = hit[0]
		out.append({"id": passages[i]["id"], "class": passages[i]["class"], "text": passages[i]["text"], "score": hit[1]})
	return out


func _set_state(to: String) -> void:
	state = to
	changed.emit(state)


func _fail(why: String) -> void:
	Brain.log_line(why)
	passages = []
	_set_state("failed")


func _logged(line: String) -> void:
	Brain.log_line(line)


static func _remove(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove(path.path_join(dir))
	DirAccess.remove_absolute(path)
