@tool
extends RefCounted
# Takes the tags meant for the helper out of an answer, as the course app does (course/src/lib/
# point-tag.ts and planOf in stuck.ts): `[POINT:<id>]`, `[STEP:<id>|<say>]` and `[DONE|<say>]`.
# While the answer streams, text that could still turn into a tag waits for the next piece.

const OPENERS := ["[POINT:", "[STEP:", "[DONE"]
const LONGEST := 200
const MAX_STEPS := 15

var held := ""
var point := ""


func push(piece: String) -> String:
	held += piece
	return _drain(false)


func end() -> String:
	return _drain(true)


func _drain(final: bool) -> String:
	var out := ""
	while true:
		var at := held.find("[")
		if at < 0:
			out += held
			held = ""
			return out
		out += held.substr(0, at)
		held = held.substr(at)
		var close := held.find("]")
		var opener := ""
		for o in OPENERS:
			if held.begins_with(o):
				opener = o
		if opener != "" and close > 0 and close <= LONGEST and not held.substr(0, close).contains("\n"):
			if opener == "[POINT:" and point == "":
				point = held.substr(opener.length(), close - opener.length()).strip_edges()
			held = held.substr(close + 1)
			continue
		var could_be := false
		if opener != "":
			could_be = close < 0 and held.length() <= LONGEST and not held.contains("\n")
		else:
			for o in OPENERS:
				if o.begins_with(held):
					could_be = true
		if could_be and not final:
			return out
		out += held[0]
		held = held.substr(1)
	return out


## The planned clicks and the closing line in a whole answer.
static func plan_of(whole: String) -> Dictionary:
	var steps: Array = []
	for m in RegEx.create_from_string("\\[STEP:([^|\\]\\n]+)\\|([^\\]\\n]+)\\]").search_all(whole):
		if steps.size() < MAX_STEPS:
			steps.append({"id": m.get_string(1).strip_edges(), "say": m.get_string(2).strip_edges()})
	var done := RegEx.create_from_string("\\[DONE\\|([^\\]\\n]+)\\]").search(whole)
	return {"steps": steps, "closing": done.get_string(1).strip_edges() if done else ""}
