@tool
extends RefCounted
# Where a command-line tool is installed: its usual places under the home folder, then system places,
# then the PATH. On Windows: places under the profile or AppData, then the PATH (split on ;).


static func find(command: String, home_places: Array, system_places: Array, windows_places: Array) -> String:
	if OS.get_name() == "Windows":
		var places := windows_places.duplicate()
		for dir in OS.get_environment("PATH").split(";", false):
			for name in [command + ".exe", command + ".cmd"]:
				places.append(dir.path_join(name))
		for place in places:
			if FileAccess.file_exists(place):
				return place
		return ""
	var home := OS.get_environment("HOME")
	for place in home_places:
		if FileAccess.file_exists(home + place):
			return home + place
	for place in system_places:
		if FileAccess.file_exists(place):
			return place
	for dir in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join(command)):
			return dir.path_join(command)
	return ""
