@tool
extends RefCounted
# The answers the ghost gave in this project, with whether he said it helped and how each walk ended.
# Kept only in the project's user data folder, never sent: he can choose to include the ones that
# didn't help when he copies debug info for a report.

const KEPT := 200


static func path() -> String:
	return OS.get_user_data_dir().path_join("kg_helper").path_join("answers.jsonl")


## Starts a record for an answer and returns its id.
func added(question: String, answer: String, steps: PackedStringArray, model: String, version: String) -> String:
	var id := "%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	var all := _read()
	all.append({"id": id, "time": Time.get_datetime_string_from_system(), "question": question, "answer": answer, "steps": Array(steps), "model": model, "version": version, "helped": null, "note": "", "walk": ""})
	_write(all.slice(max(0, all.size() - KEPT)))
	return id


func stopped(question: String, model: String, version: String) -> void:
	_update(added(question, "", PackedStringArray(), model, version), func(record: Dictionary): record["stopped"] = true)


func rated(id: String, helped: bool, note: String) -> void:
	_update(id, func(record: Dictionary): record["helped"] = helped; record["note"] = note)


func walk_ended(id: String, how: String) -> void:
	_update(id, func(record: Dictionary): record["walk"] = how)


## The last n answers, newest first.
func recent(n: int) -> Array:
	var all := _read().filter(func(record): return not record.get("stopped", false))
	all.reverse()
	return all.slice(0, n)


## The last n answers he marked as not helpful, newest first.
func recent_unhelpful(n: int) -> Array:
	var out: Array = []
	var all := _read()
	all.reverse()
	for record in all:
		if record.get("helped") == false:
			out.append(record)
		if out.size() >= n:
			break
	return out


func _update(id: String, change: Callable) -> void:
	if id == "":
		return
	var all := _read()
	for record in all:
		if record.get("id") == id:
			change.call(record)
	_write(all)


func _read() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path()):
		return out
	for line in FileAccess.get_file_as_string(path()).split("\n", false):
		var record = JSON.parse_string(line)
		if record is Dictionary:
			out.append(record)
	return out


func _write(all: Array) -> void:
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file:
		file.store_string("\n".join(all.map(func(record): return JSON.stringify(record))) + ("\n" if not all.is_empty() else ""))
