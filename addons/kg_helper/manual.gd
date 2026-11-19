@tool
extends Node

const L := preload("l10n.gd")
# Godot's manual (the how-to pages, not the class reference) for the Godot that's running: built
# nightly from godot-docs into the public repo's releases, downloaded once per minor version, checked
# against the release's digest, then kept. By Juan Linietsky, Ariel Manzur and the Godot community,
# CC BY 3.0.

signal changed(state: String)

const Brain := preload("brain.gd")
const Bm25 := preload("bm25.gd")
const Docs := preload("docs.gd")
const RELEASE := "https://api.github.com/repos/Eldriss-Studio/knochengeist-helper/releases/tags/manual-%s"
const TIMEOUT_S := 30.0
const RETRY_S := 86400.0           # not out yet, or couldn't fetch: try again the next day

var state := "off"                 # off, fetching, loading, ready, not out (no release yet) or failed
var minor := ""
var passages: Array = []           # { title, text, url }
var postings := {}
var lengths := PackedInt32Array()
var average := 1.0
var asking: HTTPRequest
var fetching: HTTPRequest
var digest := ""
var task := -1
var retry_in := 0.0


func _ready() -> void:
	asking = HTTPRequest.new()
	asking.timeout = TIMEOUT_S
	asking.request_completed.connect(_released)
	add_child(asking)
	fetching = HTTPRequest.new()
	fetching.timeout = TIMEOUT_S
	fetching.request_completed.connect(_downloaded)
	add_child(fetching)
	set_process(false)


func path() -> String:
	return Docs.folder().path_join("manual-%s.json.gz" % minor)


## Loads the saved manual for this Godot, or asks GitHub for it.
func start() -> void:
	if OS.get_environment("KG_HELPER_DOCS") == "off" or state in ["fetching", "loading", "ready"]:
		return
	var v := Engine.get_version_info()
	minor = "%d.%d" % [v["major"], v["minor"]]
	if FileAccess.file_exists(path()):
		_load()
		return
	_set_state("fetching")
	var given := OS.get_environment("KG_HELPER_MANUAL_URL")
	if asking.request((given if given != "" else RELEASE) % minor, ["User-Agent: knochengeist-helper", "Accept: application/vnd.github+json"]) != OK:
		_fail("failed", "Manual for Godot %s: couldn't ask GitHub." % minor)


func _released(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 404:
		_fail("not out", "Manual for Godot %s: no release yet." % minor)
		return
	var release = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	var asset := {}
	if release is Dictionary and release.get("assets") is Array:
		for found in release["assets"]:
			if found is Dictionary and str(found.get("name", "")) == "manual-%s.json.gz" % minor:
				asset = found
	if asset.is_empty():
		_fail("failed", "Manual for Godot %s: GitHub's answer had no manual (result %d, code %d)." % [minor, result, code])
		return
	digest = str(asset.get("digest", ""))
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	fetching.download_file = path() + ".part"
	if fetching.request(str(asset.get("browser_download_url", "")), ["User-Agent: knochengeist-helper"]) != OK:
		_fail("failed", "Manual for Godot %s: couldn't start the download." % minor)


func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := path() + ".part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_fail("failed", "Manual for Godot %s: the download failed (result %d, code %d)." % [minor, result, code])
		return
	var got := "sha256:" + FileAccess.get_sha256(part)
	if got != digest:
		DirAccess.remove_absolute(part)
		_fail("failed", "Manual for Godot %s: the download's digest %s isn't the release's %s." % [minor, got, digest])
		return
	DirAccess.rename_absolute(part, path())
	Brain.log_line("Manual for Godot %s: fetched and checked." % minor)
	_load()


func _load() -> void:
	_set_state("loading")
	task = WorkerThreadPool.add_task(_read)
	set_process(true)


# On a worker thread.
func _read() -> void:
	var packed := FileAccess.get_file_as_bytes(path())
	var whole = JSON.parse_string(packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()) if packed.size() > 0 else null
	if not whole is Dictionary or not whole.get("passages") is Array:
		return
	passages = whole["passages"]
	var built := Bm25.build(passages.map(func(passage): return "%s\n%s" % [passage.get("title", ""), passage.get("text", "")]))
	postings = built["postings"]
	lengths = built["lengths"]
	average = built["average"]


func _process(delta: float) -> void:
	if task >= 0 and WorkerThreadPool.is_task_completed(task):
		WorkerThreadPool.wait_for_task_completion(task)
		task = -1
		if passages.is_empty():
			DirAccess.remove_absolute(path())
			_fail("failed", "Manual for Godot %s: the saved file couldn't be read, so it was removed." % minor)
		else:
			_set_state("ready")
	if state in ["not out", "failed"]:
		retry_in -= delta
		if retry_in <= 0.0:
			state = "off"
			start()
	elif task < 0:
		set_process(false)


func _exit_tree() -> void:
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


## The pages that answer the question: up to k, each matching at least two of its words (or its only one).
func search(question: String, k := 3) -> Array:
	if state != "ready":
		return []
	var asked := Array(Bm25.tokens(question))
	var needed := mini(2, asked.size())
	var out: Array = []
	for hit in Bm25.rank(question, postings, lengths, average, k * 3):
		var passage: Dictionary = passages[hit[0]]
		var has := Array(Bm25.tokens("%s\n%s" % [passage.get("title", ""), passage.get("text", "")]))
		var shared := 0
		for word in asked:
			if has.has(word):
				shared += 1
		if needed > 0 and shared >= needed:
			out.append(passage)
		if out.size() >= k:
			break
	return out


## What Settings adds about the manual after the class reference's line.
func status() -> String:
	match state:
		"ready":
			return L.t(", with its manual")
		"not out":
			return L.t(". The manual for Godot %s isn't out yet, so answers use the class reference alone.") % minor
		"failed":
			return L.t(". Couldn't fetch the manual for Godot %s, so answers use the class reference alone.") % minor
		"fetching", "loading":
			return ". Getting the manual for Godot %s…" % minor
	return ""


func _fail(to: String, why: String) -> void:
	Brain.log_line(why)
	retry_in = RETRY_S
	set_process(true)
	_set_state(to)


func _set_state(to: String) -> void:
	state = to
	changed.emit(state)
