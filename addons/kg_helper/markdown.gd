@tool
extends RefCounted
# Claude's answers are Markdown; the card shows BBCode. Every "[" in the answer is escaped, so
# nothing it says can become the card's own markup. Code blocks get a Copy link above them, and only
# web addresses become links: a file: or javascript: link stays plain text.

const SHADE := "#1c221d14"
const INLINE := "`([^`]+)`|\\[([^\\]\\n]+)\\]\\(((?:[^()\\s]|\\([^()\\s]*\\))+)\\)|(https?://[^\\s<>()\\[\\]]+)|\\*\\*(.+?)\\*\\*"
const TRAILING := ".,;:!?'\""


## The answer as card text, and each code block's own text (for "copy:N" links).
static func render(markdown: String, copy_label: String) -> Dictionary:
	var out := PackedStringArray()
	var codes := PackedStringArray()
	var code := PackedStringArray()
	var in_code := false
	for line in markdown.strip_edges().split("\n"):
		if line.strip_edges().begins_with("```"):
			if in_code:
				out.append(_block(code, codes, copy_label))
				code.clear()
			in_code = not in_code
		elif in_code:
			code.append(line)
		else:
			out.append(_inline(line))
	if in_code:                          # still streaming in: the rest is code
		out.append(_block(code, codes, copy_label))
	return {"text": "\n".join(out), "codes": codes}


static func _block(code: PackedStringArray, codes: PackedStringArray, copy_label: String) -> String:
	codes.append("\n".join(code))
	return "[url=copy:%d]%s[/url]\n[bgcolor=%s][code]%s[/code][/bgcolor]" % [codes.size() - 1, copy_label, SHADE, _escaped("\n".join(code))]


static func _inline(line: String) -> String:
	var found := RegEx.create_from_string(INLINE)
	var out := ""
	var at := 0
	for m in found.search_all(line):
		out += _escaped(line.substr(at, m.get_start() - at))
		at = m.get_end()
		if m.get_string(1) != "":
			out += "[code]%s[/code]" % _escaped(m.get_string(1))
		elif m.get_string(2) != "":
			out += _link(m.get_string(3), _inline(m.get_string(2)))
		elif m.get_string(4) != "":
			var address := m.get_string(4)
			var cut := address.length()
			while cut > 0 and TRAILING.contains(address[cut - 1]):
				cut -= 1
			out += _link(address.left(cut), _escaped(address.left(cut))) + _escaped(address.substr(cut))
		else:
			out += "[b]%s[/b]" % _inline(m.get_string(5))
	return out + _escaped(line.substr(at))


static func _link(address: String, shown: String) -> String:
	if not (address.begins_with("https://") or address.begins_with("http://")) or address.contains("[") or address.contains("]"):
		return shown
	return "[url=%s]%s[/url]" % [address, shown]


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")
