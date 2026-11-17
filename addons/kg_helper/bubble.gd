@tool
extends Control
# The ghost's speech: a bone-colored card with a thin, slightly uneven carved frame and a soft
# oxblood shadow, set in Alegreya, as in identity/README.md. It draws itself (Godot's flat style
# boxes can't do the uneven frame) and never takes a click.

const INK := Color("1c221d")
const BONE := Color("f1ead6")
const FRAME := Color("4a5446")
const OXBLOOD := Color("8a2f28")
# What the ghost mutters while it works something out, one after another.
const MUSINGS := [
	"Rattling my bones...",
	"Asking the other side...",
	"Drifting through the manual...",
	"Peering through the walls...",
	"Haunting the docs...",
	"Counting my ribs...",
	"Almost have it...",
]

var s := 1.0
var fonts := {}
var words: RichTextLabel
var wide := 250.0
var frame := PackedVector2Array()
var framed_for := Vector2.ZERO
var mascot: Texture2D             # the ghost, bobbing beside the words while it muses
var musing := false
var mused := 0.0
var muse_from := 0
var under := 0.0                 # room kept under the words (ask.gd puts its field and buttons there)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	s = EditorInterface.get_editor_scale()
	words = RichTextLabel.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.bbcode_enabled = true
	words.scroll_active = false
	words.fit_content = true
	var regular := _font(450)
	if regular:
		words.add_theme_font_override("normal_font", regular)
		words.add_theme_font_override("bold_font", _font(750))
	words.add_theme_color_override("default_color", INK)
	words.add_theme_stylebox_override("normal", StyleBoxEmpty.new())     # no editor panel behind the words
	words.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	words.add_theme_font_size_override("normal_font_size", int(17 * s))
	words.add_theme_font_size_override("bold_font_size", int(17 * s))
	words.add_theme_constant_override("line_separation", int(3 * s))
	add_child(words)


# Alegreya comes with the helper (Alegreya.ttf, OFL), one file for every weight.
func _font(weight: int) -> Font:
	if fonts.has(weight):
		return fonts[weight]
	fonts[weight] = _load_font(weight)
	return fonts[weight]


func _load_font(weight: int) -> Font:
	var path: String = (get_script() as Script).resource_path.get_base_dir().path_join("Alegreya.ttf")
	if not FileAccess.file_exists(path):
		return null
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		return null
	var cut := FontVariation.new()
	cut.base_font = file
	cut.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return cut


## Says `text` (bold in [b]...[/b]) in a card about `width` wide.
func say(text: String, width := 250.0) -> void:
	musing = false
	wide = width * s
	words.text = text
	_fit()


## Mutters to itself, a new line every couple of seconds, until it has something to say.
func muse() -> void:
	musing = true
	mused = 0.0
	muse_from = randi() % MUSINGS.size()
	say(MUSINGS[muse_from], wide / s)
	musing = true


## How much of the text shows, 0 to 1: the pointer types it out.
func show_part(ratio: float) -> void:
	words.visible_ratio = ratio


func _fit() -> void:
	var pad := Vector2(14, 10) * s
	words.position = pad + (Vector2(40 * s, 0) if musing and mascot else Vector2.ZERO)
	words.size = Vector2(wide, 0)
	words.size.y = words.get_content_height()
	size = words.size + pad * 2.0 + Vector2(40 * s if musing and mascot else 0.0, under)
	if musing:
		size.y = maxf(size.y, 52 * s + under)
	if size != framed_for:
		framed_for = size
		frame = _carve(size)
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if musing:
		var before := int(mused / 2.2)
		mused += delta
		if int(mused / 2.2) != before:
			words.text = MUSINGS[(muse_from + int(mused / 2.2)) % MUSINGS.size()]
	_fit()


# The frame as a hand would cut it: the card's outline, each point nudged a little.
func _carve(around: Vector2) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var corners := [Vector2.ZERO, Vector2(around.x, 0), around, Vector2(0, around.y)]
	var pts := PackedVector2Array()
	for i in 4:
		var from: Vector2 = corners[i]
		var to: Vector2 = corners[(i + 1) % 4]
		var steps := maxi(2, int(from.distance_to(to) / (16.0 * s)))
		for k in steps:
			pts.append(from.lerp(to, float(k) / steps) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8 * s)
	pts.append(pts[0])
	return pts


func _draw() -> void:
	draw_rect(Rect2(Vector2(5, 5) * s, size), Color(OXBLOOD, 0.5))
	draw_colored_polygon(frame, BONE)
	draw_polyline(frame, FRAME, 2.0 * s, true)
	if musing and mascot:
		var big := 34.0 * s
		var still := preload("brain.gd").less_motion()
		draw_set_transform(Vector2(12 * s + big * 0.5, 10 * s + big * 0.5 + (0.0 if still else sin(mused * 3.0) * 3.0 * s)), 0.0 if still else sin(mused * 1.5) * 0.18, Vector2.ONE)
		draw_texture_rect(mascot, Rect2(-Vector2(big, big) * 0.5, Vector2(big, big)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
