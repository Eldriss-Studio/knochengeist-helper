@tool
extends RefCounted
# Keyword search over passages (BM25), shared by the class reference and the manual.

const K1 := 1.2
const B := 0.75
# Words that tell a search nothing about Godot ("how do I...").
const STOPWORDS := ["a", "an", "the", "i", "do", "does", "how", "what", "is", "are", "to", "in", "on", "of", "for", "and", "or", "it", "my", "me", "can", "you", "your", "with", "this", "that", "be", "if", "when", "by", "as", "at", "from", "make", "get", "set", "use", "want"]


## Postings, lengths and the average length for these texts.
static func build(texts: Array) -> Dictionary:
	var postings := {}               # term -> PackedInt32Array of [passage, count, passage, count, ...]
	var lengths := PackedInt32Array()
	for i in texts.size():
		var counts := {}
		var words := tokens(str(texts[i]))
		for word in words:
			counts[word] = int(counts.get(word, 0)) + 1
		lengths.append(words.size())
		for word in counts:
			var list: PackedInt32Array = postings.get(word, PackedInt32Array())   # a copy: packed arrays are values
			list.append_array([i, counts[word]])
			postings[word] = list
	return {"postings": postings, "lengths": lengths, "average": average_of(lengths)}


static func average_of(lengths: PackedInt32Array) -> float:
	var total := 0
	for n in lengths:
		total += n
	return max(1.0, float(total) / max(1, lengths.size()))


## The k best matches as [passage, score], best first.
static func rank(query: String, postings: Dictionary, lengths: PackedInt32Array, average: float, k: int) -> Array:
	var scores := {}
	var n := float(lengths.size())
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
	return best.slice(0, k).map(func(i): return [i, scores[i]])


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
