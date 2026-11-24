@tool
extends RefCounted
# The computer's clipboard and web browser. Tests stand in for both: headless Godot has no
# clipboard, and a test must never open a real browser.


static func copy(text: String) -> void:
	var stand_in := OS.get_environment("KG_HELPER_CLIPBOARD")
	if stand_in == "":
		DisplayServer.clipboard_set(text)
		return
	var file := FileAccess.open(stand_in, FileAccess.WRITE)
	if file:
		file.store_string(text)


static func open(address: String) -> void:
	var stand_in := OS.get_environment("KG_HELPER_OPEN")
	if stand_in == "":
		OS.shell_open(address)
	else:
		OS.create_process(stand_in, [address])
