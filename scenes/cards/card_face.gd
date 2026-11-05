@tool
extends Control
class_name CardFace
## Procedural card face, drawn in code (no textures needed): crisp at any zoom, themed from
## a style table, with an optional photo overlay for custom decks (e.g. a wedding build).
##
##   var f := CardFace.new()
##   f.size = Vector2(240, 340)
##   f.setup(12, Globals.SUITS.HEARTS, "neon_noir")
##   f.photo = CardFace.load_photo("user://wedding/hearts_12.jpg")   # optional
##   f.photo_mode = CardFace.PhotoMode.FULL
##
## Ranks are 2..14 (Ace high, as in the rules). Suits use Globals.SUITS order.

enum PhotoMode { NONE, FULL, WINDOW }

const HEARTS := 0
const SPADES := 1
const DIAMONDS := 2
const CLUBS := 3

const FONT_RANK := preload("res://assets/fonts/Rajdhani-Bold.ttf")
const FONT_FACE := preload("res://assets/fonts/Monoton-Regular.ttf")

## Candidate looks. Keys: bg_top/bg_bottom (gradient), border, red/black (suit ink),
## glow (halo strength 0..1), outline (suits drawn as outlines), pattern ("", "grid", "sun").
const STYLES := {
	"neon_noir": {
		"title": "Neon Noir",
		"bg_top": Color("1c0740"), "bg_bottom": Color("0d0221"),
		"border": Color("9b4dff"), "border_w": 0.018,
		"red": Color("ff2bd6"), "black": Color("19f0ff"),
		"glow": 1.0, "outline": false, "pattern": "",
	},
	"sunset_chrome": {
		"title": "Sunset Chrome",
		"bg_top": Color("4a1280"), "bg_bottom": Color("12042b"),
		"border": Color("ffd23f"), "border_w": 0.014,
		"red": Color("ff3d7f"), "black": Color("f4e9ff"),
		"glow": 0.6, "outline": false, "pattern": "sun",
	},
	"cream_classic": {
		"title": "Cream Classic",
		"bg_top": Color("fdf9ff"), "bg_bottom": Color("eadcff"),
		"border": Color("9b4dff"), "border_w": 0.012,
		"red": Color("e0115f"), "black": Color("1b0b3a"),
		"glow": 0.0, "outline": false, "pattern": "",
	},
	"wireframe": {
		"title": "Wireframe",
		"bg_top": Color("0d0221"), "bg_bottom": Color("0d0221"),
		"border": Color("19f0ff"), "border_w": 0.010,
		"red": Color("ff2bd6"), "black": Color("19f0ff"),
		"glow": 0.5, "outline": true, "pattern": "grid",
	},
}

@export_range(2, 14) var rank: int = 14:
	set(v):
		rank = v
		queue_redraw()
@export_range(0, 3) var suit: int = SPADES:
	set(v):
		suit = v
		queue_redraw()
@export var style_id: String = "neon_noir":
	set(v):
		style_id = v
		queue_redraw()
## Custom image for this card (a photo for a special deck). Shown according to photo_mode.
@export var photo: Texture2D:
	set(v):
		photo = v
		queue_redraw()
## FULL: photo fills the card, indices sit on small plates. WINDOW: photo in a framed panel,
## the card keeps its border and indices. NONE: ignore the photo.
@export var photo_mode: PhotoMode = PhotoMode.FULL:
	set(v):
		photo_mode = v
		queue_redraw()
## Which part of the photo to keep when it is cropped to fit (0..1). Faces usually sit high.
@export var photo_focus := Vector2(0.5, 0.35):
	set(v):
		photo_focus = v
		queue_redraw()

## Draw a card back instead of a face: `photo` fills the card inside the style's border.
@export var back := false:
	set(v):
		back = v
		queue_redraw()
## Quarter turns (counter-clockwise) applied to the back's photo, so a card lying sideways
## (the deck) still shows its photo upright on screen.
@export var turns := 0:
	set(v):
		turns = v
		queue_redraw()

static var _shapes := {}

func setup(p_rank: int, p_suit: int, p_style: String = "neon_noir") -> void:
	rank = p_rank
	suit = p_suit
	style_id = p_style

## Load an image file at runtime (no Godot import needed), so photos for a custom deck can be
## dropped into a folder. Returns null if the file is missing or unreadable. The format is
## read from the file's bytes, not its extension (photos saved from browsers and chat apps
## are often WebP named ".jpeg").
static func load_photo(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		push_warning("CardFace: could not read photo %s (JPEG, PNG or WebP expected)" % path)
		return null
	return ImageTexture.create_from_image(img)

## Find a photo for one card in a folder using the deck's naming ("hearts_12.jpg", ".png",
## ".webp"). Returns null when that card has no photo, so a deck can mix photo and plain cards.
static func find_photo(dir: String, p_rank: int, p_suit: int) -> Texture2D:
	var base := "%s/%s_%d" % [dir, ["hearts", "spades", "diamonds", "clubs"][p_suit], p_rank]
	for ext in ["jpg", "jpeg", "png", "webp"]:
		var t := load_photo("%s.%s" % [base, ext])
		if t != null:
			return t
	return null

func _style() -> Dictionary:
	return STYLES.get(style_id, STYLES["neon_noir"])

func _ink() -> Color:
	var s := _style()
	return s.red if suit == HEARTS or suit == DIAMONDS else s.black

static func rank_text(r: int) -> String:
	match r:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
	return str(r)

# --- drawing -------------------------------------------------------------------------------

func _draw() -> void:
	if back:
		_draw_back()
		return
	var s := _style()
	var w := size.x
	var radius := w * 0.07
	var card := _rounded_rect(Rect2(Vector2.ZERO, size), radius)
	var show_photo := photo != null and photo_mode != PhotoMode.NONE

	if show_photo and photo_mode == PhotoMode.FULL:
		_draw_photo(Rect2(Vector2.ZERO, size), radius)
		_draw_full_photo_shade()
	else:
		_draw_gradient(card, s.bg_top, s.bg_bottom)
		_draw_pattern(s)
		if show_photo:
			_draw_window_photo(s)
		elif rank == 14:
			_draw_ace()
		elif rank >= 11:
			_draw_court()
		else:
			_draw_pips()

	var bw: float = max(1.0, w * float(s.border_w))
	var inset := _rounded_rect(Rect2(Vector2.ONE * bw * 0.5, size - Vector2.ONE * bw), radius - bw * 0.5)
	inset.append(inset[0])
	draw_polyline(inset, s.border, bw, true)

	_draw_index(Vector2(w * 0.1, w * 0.06), false, show_photo and photo_mode == PhotoMode.FULL)
	_draw_index(size - Vector2(w * 0.1, w * 0.06), true, show_photo and photo_mode == PhotoMode.FULL)

func _draw_gradient(poly: PackedVector2Array, top: Color, bottom: Color) -> void:
	var cols := PackedColorArray()
	for p in poly:
		cols.append(top.lerp(bottom, clampf(p.y / size.y, 0.0, 1.0)))
	draw_polygon(poly, cols)

func _draw_pattern(s: Dictionary) -> void:
	var w := size.x
	match s.pattern:
		"grid":
			var c := Color(s.border, 0.10)
			var step := w / 8.0
			var x := step
			while x < size.x - 1.0:
				draw_line(Vector2(x, w * 0.04), Vector2(x, size.y - w * 0.04), c, 1.0)
				x += step
			var y := step
			while y < size.y - 1.0:
				draw_line(Vector2(w * 0.04, y), Vector2(size.x - w * 0.04, y), c, 1.0)
				y += step
		"sun":
			# Retro sunset bars across the lower third.
			var c := Color(s.border, 0.12)
			var y0 := size.y * 0.62
			for i in 7:
				var t := float(i) / 7.0
				var y := y0 + (size.y * 0.33) * t * t * 1.4
				var h := 1.0 + i * w * 0.006
				if y + h < size.y - w * 0.03:
					draw_rect(Rect2(w * 0.05, y, w * 0.9, h), c)

## Corner index: rank over a small suit. Bottom-right is the same, rotated 180 degrees.
func _draw_index(anchor: Vector2, flipped: bool, plate: bool) -> void:
	var w := size.x
	var txt := rank_text(rank)
	var fs := int(w * (0.17 if txt.length() == 1 else 0.15))
	var col := _ink()
	draw_set_transform(anchor, PI if flipped else 0.0)
	var tw := FONT_RANK.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var col_w: float = max(tw, w * 0.1)
	if plate:
		var pr := Rect2(Vector2(-w * 0.04, -w * 0.015), Vector2(col_w + w * 0.08, w * 0.27))
		var plate_poly := _rounded_rect(pr, w * 0.04)
		draw_colored_polygon(plate_poly, Color(0.05, 0.01, 0.13, 0.78))
	var asc := FONT_RANK.get_ascent(fs)
	var x := (col_w - tw) * 0.5
	_glow_text(FONT_RANK, Vector2(x, asc * 0.92), txt, fs, col)
	_draw_suit(suit, Vector2(col_w * 0.5, asc + w * 0.07), w * 0.085, col, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _glow_text(font: Font, pos: Vector2, txt: String, fs: int, col: Color) -> void:
	var g: float = _style().glow
	if g > 0.0:
		for i in 3:
			draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * (0.12 + 0.1 * i)), Color(col, 0.10 * g))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_pips() -> void:
	var w := size.x
	var area := Rect2(w * 0.32, size.y * 0.19, w * 0.36, size.y * 0.62)
	var pip := w * (0.18 if rank <= 3 else 0.14)
	for p: Vector2 in _pip_layout(rank):
		var at := area.position + area.size * p
		_draw_suit(suit, at, pip, _ink(), p.y > 0.5)

func _draw_ace() -> void:
	var c := size * Vector2(0.5, 0.5)
	var col := _ink()
	var r := size.x * 0.27
	draw_arc(c, r * 1.35, 0.0, TAU, 64, Color(col, 0.35), max(1.0, size.x * 0.008), true)
	_draw_suit(suit, c, size.x * 0.42, col, false)

func _draw_court() -> void:
	var w := size.x
	var col := _ink()
	var frame := Rect2(w * 0.24, size.y * 0.13, w * 0.52, size.y * 0.74)
	var fp := _rounded_rect(frame, w * 0.05)
	fp.append(fp[0])
	draw_polyline(fp, Color(col, 0.55), max(1.0, w * 0.008), true)
	var txt := rank_text(rank)
	var fs := int(w * 0.46)
	var tw := FONT_FACE.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := FONT_FACE.get_ascent(fs)
	var desc := FONT_FACE.get_descent(fs)
	var base := Vector2((w - tw) * 0.5, size.y * 0.5 + (asc - desc) * 0.5 - fs * 0.04)
	_glow_text(FONT_FACE, base, txt, fs, col)
	_draw_suit(suit, Vector2(w * 0.5, frame.position.y + w * 0.12), w * 0.12, col, false)
	_draw_suit(suit, Vector2(w * 0.5, frame.end.y - w * 0.12), w * 0.12, col, true)

## FULL mode: darken the top-left and bottom-right a touch so the index plates sit cleanly.
func _draw_full_photo_shade() -> void:
	var r := _rounded_rect(Rect2(Vector2.ZERO, size), size.x * 0.07)
	var cols := PackedColorArray()
	for p in r:
		var t := absf(p.y / size.y - 0.5) * 2.0
		cols.append(Color(0.05, 0.01, 0.13, 0.35 * t * t))
	draw_polygon(r, cols)

func _draw_window_photo(s: Dictionary) -> void:
	var w := size.x
	var win := Rect2(w * 0.24, size.y * 0.07, w * 0.52, size.y * 0.83)
	var rad := w * 0.05
	_draw_photo(win, rad)
	var col := _ink()
	var frame := _rounded_rect(win, rad)
	frame.append(frame[0])
	if float(s.glow) > 0.0:
		draw_polyline(frame, Color(col, 0.25), w * 0.03, true)
	draw_polyline(frame, col, max(1.5, w * 0.012), true)
	# Suit badge riding the bottom edge of the window.
	var bc := Vector2(w * 0.5, win.end.y)
	draw_circle(bc, w * 0.075, s.bg_bottom)
	draw_arc(bc, w * 0.075, 0.0, TAU, 40, col, max(1.5, w * 0.01), true)
	_draw_suit(suit, bc, w * 0.08, col, false)

## Card back: the photo upright (counter-rotated by `turns`), a soft vignette, a fine inner
## line and the style's border. Without a photo it draws the style's plain gradient.
func _draw_back() -> void:
	var s := _style()
	var w := size.x
	var radius := w * 0.07
	var odd := turns % 2 != 0
	var logical := Vector2(size.y, size.x) if odd else size
	draw_set_transform(size * 0.5, -PI * 0.5 * turns, Vector2.ONE)
	var rect := Rect2(-logical * 0.5, logical)
	if photo != null:
		_draw_photo(rect, radius)
		var poly := _rounded_rect(rect, radius)
		# Edge vignette: a ring between the card edge and an inset copy.
		var inner := _rounded_rect(rect.grow(-w * 0.09), radius)
		for i in poly.size():
			var j := (i + 1) % poly.size()
			var quad := PackedVector2Array([poly[i], poly[j], inner[j], inner[i]])
			draw_polygon(quad, PackedColorArray([Color(0.05, 0.01, 0.13, 0.55), Color(0.05, 0.01, 0.13, 0.55), Color(0.05, 0.01, 0.13, 0.0), Color(0.05, 0.01, 0.13, 0.0)]))
	else:
		var card := _rounded_rect(rect, radius)
		var cols := PackedColorArray()
		for p in card:
			cols.append(Color(s.bg_top).lerp(s.bg_bottom, clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)))
		draw_polygon(card, cols)
	var line := _rounded_rect(rect.grow(-w * 0.05), radius * 0.6)
	line.append(line[0])
	draw_polyline(line, Color(s.border, 0.7), max(1.0, w * 0.006), true)
	var bw: float = max(1.0, w * float(s.border_w))
	var edge := _rounded_rect(rect.grow(-bw * 0.5), radius - bw * 0.5)
	edge.append(edge[0])
	draw_polyline(edge, s.border, bw, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Draw the photo cover-cropped into a rounded rect (UV-mapped polygon, so no shader needed).
func _draw_photo(rect: Rect2, radius: float) -> void:
	var poly := _rounded_rect(rect, radius)
	var ts := photo.get_size()
	var tex_aspect := ts.x / ts.y
	var rect_aspect := rect.size.x / rect.size.y
	var uv_size := Vector2.ONE
	if tex_aspect > rect_aspect:
		uv_size.x = rect_aspect / tex_aspect
	else:
		uv_size.y = tex_aspect / rect_aspect
	var uv_pos := (Vector2.ONE - uv_size) * photo_focus
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(uv_pos + (p - rect.position) / rect.size * uv_size)
	draw_colored_polygon(poly, Color.WHITE, uvs, photo)

# --- suits ---------------------------------------------------------------------------------

## Draw a suit centred at `at`, `h` pixels tall. Glow and outline follow the style.
func _draw_suit(which: int, at: Vector2, h: float, col: Color, flipped: bool) -> void:
	var s := _style()
	var unit: PackedVector2Array = _suit_shape(which)
	var pts := PackedVector2Array()
	var k := h * 0.5
	for p in unit:
		pts.append(at + (-p if flipped else p) * k)
	var g: float = s.glow
	if g > 0.0:
		for i in range(3, 0, -1):
			for halo in Geometry2D.offset_polygon(pts, h * 0.035 * i):
				if not Geometry2D.is_polygon_clockwise(halo):
					draw_colored_polygon(halo, Color(col, 0.09 * g))
	if s.outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, max(1.2, h * 0.06), true)
	else:
		draw_colored_polygon(pts, col)

## Unit-size suit outlines (height 2, centred on 0), built once with Geometry2D unions so
## clubs and spades are a single clean polygon (needed for outlines and glow offsets).
static func _suit_shape(which: int) -> PackedVector2Array:
	if _shapes.has(which):
		return _shapes[which]
	var poly: PackedVector2Array
	match which:
		HEARTS:
			poly = _heart()
		DIAMONDS:
			poly = PackedVector2Array([Vector2(0, -1), Vector2(0.62, 0), Vector2(0, 1), Vector2(-0.62, 0)])
			# Slightly pinched sides read as a playing-card diamond rather than a rhombus.
			poly = _pinch(poly, 0.06)
		SPADES:
			var top := PackedVector2Array()
			for p in _heart():
				top.append(Vector2(p.x, -p.y) * 0.82 + Vector2(0, -0.12))
			poly = _union(top, _stem())
		CLUBS:
			var a := _circle(Vector2(0, -0.48), 0.4)
			var b := _circle(Vector2(-0.44, 0.14), 0.4)
			var c := _circle(Vector2(0.44, 0.14), 0.4)
			poly = _union(_union(_union(a, b), c), _stem())
			poly = _union(poly, PackedVector2Array([Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(0.2, 0.2), Vector2(-0.2, 0.2)]))
	poly = _normalize(poly)
	_shapes[which] = poly
	return poly

static func _heart() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 72:
		var t := TAU * float(i) / 72.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		out.append(Vector2(x, y) / 16.0)
	return out

static func _stem() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.06, 0.1), Vector2(0.06, 0.1), Vector2(0.14, 0.78), Vector2(0.38, 0.98), Vector2(-0.38, 0.98), Vector2(-0.14, 0.78)])

static func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 40:
		out.append(c + Vector2.from_angle(TAU * float(i) / 40.0) * r)
	return out

static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var merged := Geometry2D.merge_polygons(a, b)
	for p in merged:
		if not Geometry2D.is_polygon_clockwise(p):
			return p
	return merged[0] if merged.size() > 0 else a

static func _pinch(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for j in 8:
			var t := float(j) / 8.0
			var p := a.lerp(b, t)
			out.append(p * (1.0 - amount * sin(t * PI)))
	return out

static func _normalize(poly: PackedVector2Array) -> PackedVector2Array:
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var centre := (lo + hi) * 0.5
	var k := 2.0 / (hi.y - lo.y)
	var out := PackedVector2Array()
	for p in poly:
		out.append((p - centre) * k)
	return out

# --- layout helpers ------------------------------------------------------------------------

## Standard pip positions for 2..10, in 0..1 of the pip area.
static func _pip_layout(r: int) -> Array[Vector2]:
	const L := 0.0
	const M := 0.5
	const R := 1.0
	var out: Array[Vector2] = []
	match r:
		2: out = [Vector2(M, 0), Vector2(M, 1)]
		3: out = [Vector2(M, 0), Vector2(M, 0.5), Vector2(M, 1)]
		4: out = [Vector2(L, 0), Vector2(R, 0), Vector2(L, 1), Vector2(R, 1)]
		5: out = [Vector2(L, 0), Vector2(R, 0), Vector2(M, 0.5), Vector2(L, 1), Vector2(R, 1)]
		6: out = [Vector2(L, 0), Vector2(R, 0), Vector2(L, 0.5), Vector2(R, 0.5), Vector2(L, 1), Vector2(R, 1)]
		7: out = [Vector2(L, 0), Vector2(R, 0), Vector2(M, 0.25), Vector2(L, 0.5), Vector2(R, 0.5), Vector2(L, 1), Vector2(R, 1)]
		8: out = [Vector2(L, 0), Vector2(R, 0), Vector2(M, 0.25), Vector2(L, 0.5), Vector2(R, 0.5), Vector2(M, 0.75), Vector2(L, 1), Vector2(R, 1)]
		9: out = [Vector2(L, 0), Vector2(R, 0), Vector2(L, 1.0 / 3.0), Vector2(R, 1.0 / 3.0), Vector2(M, 0.5), Vector2(L, 2.0 / 3.0), Vector2(R, 2.0 / 3.0), Vector2(L, 1), Vector2(R, 1)]
		10: out = [Vector2(L, 0), Vector2(R, 0), Vector2(M, 1.0 / 6.0), Vector2(L, 1.0 / 3.0), Vector2(R, 1.0 / 3.0), Vector2(L, 2.0 / 3.0), Vector2(R, 2.0 / 3.0), Vector2(M, 5.0 / 6.0), Vector2(L, 1), Vector2(R, 1)]
	return out

static func _rounded_rect(r: Rect2, radius: float, seg: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - radius, radius), -PI * 0.5],
		[r.end - Vector2(radius, radius), 0.0],
		[r.position + Vector2(radius, r.size.y - radius), PI * 0.5],
		[r.position + Vector2(radius, radius), PI],
	]
	for c in corners:
		for i in seg + 1:
			out.append(c[0] + Vector2.from_angle(c[1] + PI * 0.5 * float(i) / float(seg)) * radius)
	return out
