@tool
extends Node
# A keyword index of Godot's class reference for the Godot that's running, built from that Godot itself
# (`--doctool`), so it always matches its version and nothing is downloaded.

signal changed(state: String)

const Brain := preload("brain.gd")
const CHECK_EVERY_S := 1.0
const K1 := 1.2
const B := 0.75
const MEMBER_TAGS := ["method", "member", "signal", "theme_item", "constant"]
# Words that tell a search nothing about Godot ("how do I...").
const STOPWORDS := ["a", "an", "the", "i", "do", "does", "how", "what", "is", "are", "to", "in", "on", "of", "for", "and", "or", "it", "my", "me", "can", "you", "your", "with", "this", "that", "be", "if", "when", "by", "as", "at", "from", "make", "get", "set", "use", "want"]

var state := "off"                 # off, building, ready or failed
var reading := 0.0                 # while building: 0 while Godot writes the reference, then how much is read (0 to 1)
var classes := 0
var version := ""
var passages: Array = []           # { id, class, text }
var postings := {}                 # term -> PackedInt32Array of [passage, count, passage, count, ...]
var lengths := PackedInt32Array()
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
	return folder().path_join(version).path_join("index.bin")


## What Settings says about it.
func status_line() -> String:
	var godot := (version if version != "" else running_version()).rsplit(".", true, 1)[0]
	match state:
		"ready":
			return "Ready: %s classes from Godot %s" % [_thousands(classes), godot]
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
	dump_pid = OS.create_process(godot if godot != "" else OS.get_executable_path(), ["--headless", "--doctool", dump_dir])
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
	for k in files.size():
		_read_class(files[k], found)
		reading = float(k + 1) / files.size()
	_remove(dump_dir)
	if found.is_empty():
		call_deferred("_fail", "Godot wrote no class reference to read.")
		return
	_index(found)
	DirAccess.make_dir_recursive_absolute(index_path().get_base_dir())
	var file := FileAccess.open(index_path(), FileAccess.WRITE)
	if file:
		file.store_var({"version": version, "classes": classes, "passages": passages, "postings": postings, "lengths": lengths})
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
	var total := 0
	for n in lengths:
		total += n
	average = max(1.0, float(total) / max(1, lengths.size()))
	call_deferred("_logged", "Loaded the class reference index for Godot %s." % version)


func _collect(dir: String, into: Array) -> void:
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".xml"):
			into.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)


# One passage for the class (its brief description), and one per member, each starting with the class name.
func _read_class(path: String, into: Array) -> void:
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
				elif tag in MEMBER_TAGS:
					member = xml.get_named_attribute_value_safe("name")
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
	postings = {}
	lengths = PackedInt32Array()
	var names := {}
	for i in passages.size():
		names[passages[i]["class"]] = true
		var counts := {}
		var words := tokens(str(passages[i]["text"]))
		for word in words:
			counts[word] = int(counts.get(word, 0)) + 1
		lengths.append(words.size())
		for word in counts:
			var list: PackedInt32Array = postings.get(word, PackedInt32Array())   # a copy: packed arrays are values
			list.append_array([i, counts[word]])
			postings[word] = list
	classes = names.size()
	var total := 0
	for n in lengths:
		total += n
	average = max(1.0, float(total) / max(1, lengths.size()))


## Lowercased words, with CamelCase and snake_case names split into their parts and kept whole too.
static func tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var word := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*|[0-9]+")
	var part := RegEx.create_from_string("[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+[A-Za-z]?")
	for found in word.search_all(text):
		var whole := found.get_string()
		if whole.to_lower() in STOPWORDS:
			continue
		out.append(whole.to_lower())
		for piece in whole.split("_", false):
			var pieces := part.search_all(piece)
			if pieces.size() > 1 or piece != whole:
				for p in pieces:
					if not p.get_string().to_lower() in STOPWORDS:
						out.append(p.get_string().to_lower())
	return out


## The k passages that best match the words, best first (BM25).
func search(query: String, k := 5) -> Array:
	if state != "ready":
		return []
	var scores := {}
	var n := float(passages.size())
	for word in tokens(query):
		if not postings.has(word):
			continue
		var list: PackedInt32Array = postings[word]
		var df := float(list.size() / 2)
		var idf := log(1.0 + (n - df + 0.5) / (df + 0.5))
		for j in range(0, list.size(), 2):
			var i := list[j]
			var tf := float(list[j + 1])
			var norm := tf * (K1 + 1.0) / (tf + K1 * (1.0 - B + B * lengths[i] / average))
			scores[i] = float(scores.get(i, 0.0)) + idf * norm
	var best := scores.keys()
	best.sort_custom(func(a, b): return scores[a] > scores[b])
	var out: Array = []
	for i in best.slice(0, k):
		out.append({"id": passages[i]["id"], "class": passages[i]["class"], "text": passages[i]["text"], "score": scores[i]})
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
