extends SceneTree
## Dev tool (needs a window, not --headless): renders a contact sheet of the procedural
## CardFace styles, plus photo-overlay examples, and saves it as a PNG.
##   godot --path . --script res://tools/card_style_preview.gd -- <out_dir> [photo_path]
## Without photo_path a generated stand-in "couple photo" is used.

const CardFaceScript := preload("res://scenes/cards/card_face.gd")
const CARD := Vector2(240, 340)
const GAP := 24.0
const LABEL_H := 52.0
const SAMPLES := [[2, 0], [7, 1], [10, 2], [14, 3], [12, 0], [13, 1]]   # [rank, suit]

var _out := "user://card_styles"
var _frames := 0
var _vp: SubViewport

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var photo: Texture2D = CardFaceScript.load_photo(args[1]) if args.size() > 1 else null
	if photo == null:
		photo = _stand_in_photo()

	var styles := CardFaceScript.STYLES.keys()
	var rows := styles.size() + 2
	var sheet := Vector2(GAP + SAMPLES.size() * (CARD.x + GAP), GAP + rows * (LABEL_H + CARD.y + GAP))
	_vp = SubViewport.new()
	_vp.size = Vector2i(sheet)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color("08011a")
	bg.size = sheet
	_vp.add_child(bg)

	var y := GAP
	for i in styles.size():
		var sid: String = styles[i]
		_label("%s.  %s   (style_id \"%s\")" % [char(65 + i), CardFaceScript.STYLES[sid].title, sid], y)
		for j in SAMPLES.size():
			_card(j, y + LABEL_H, SAMPLES[j][0], SAMPLES[j][1], sid, null, CardFaceScript.PhotoMode.NONE)
		y += LABEL_H + CARD.y + GAP

	# Photo overlays: FULL bleed and WINDOW, across a few styles.
	var full := CardFaceScript.PhotoMode.FULL
	var win := CardFaceScript.PhotoMode.WINDOW
	_label("Photo overlay, FULL mode (photo fills the card)", y)
	var full_set := [[12, 0, "neon_noir"], [13, 1, "neon_noir"], [14, 0, "sunset_chrome"], [11, 2, "cream_classic"], [12, 2, "wireframe"], [7, 0, "neon_noir"]]
	for j in full_set.size():
		_card(j, y + LABEL_H, full_set[j][0], full_set[j][1], full_set[j][2], photo, full)
	y += LABEL_H + CARD.y + GAP
	_label("Photo overlay, WINDOW mode (photo in a framed panel)", y)
	var win_set := [[12, 0, "neon_noir"], [13, 3, "neon_noir"], [14, 0, "sunset_chrome"], [11, 2, "cream_classic"], [12, 0, "cream_classic"], [13, 1, "wireframe"]]
	for j in win_set.size():
		_card(j, y + LABEL_H, win_set[j][0], win_set[j][1], win_set[j][2], photo, win)

func _label(text: String, y: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(GAP, y + 8)
	l.add_theme_font_override("font", NeonTheme.FONT_HEAD)
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", NeonTheme.TEXT)
	_vp.add_child(l)

func _card(col: int, y: float, rank: int, suit: int, style: String, photo: Texture2D, mode: int) -> void:
	var f: Control = CardFaceScript.new()
	f.position = Vector2(GAP + col * (CARD.x + GAP), y)
	f.size = CARD
	f.setup(rank, suit, style)
	f.photo = photo
	f.photo_mode = mode
	_vp.add_child(f)

## A soft sunset with two figures, standing in for a real photo.
func _stand_in_photo() -> Texture2D:
	var w := 480
	var h := 640
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for yy in h:
		var t := float(yy) / h
		var sky := Color("ffb37a").lerp(Color("c2508f"), t).lerp(Color("3b1d5c"), clampf((t - 0.55) * 2.0, 0.0, 1.0))
		for xx in w:
			img.set_pixel(xx, yy, sky)
	var sun := Vector2(w * 0.5, h * 0.42)
	_disc(img, sun, 120, Color(1.0, 0.92, 0.7, 0.55))
	var ink := Color("2a1236")
	for cx in [w * 0.38, w * 0.62]:
		_disc(img, Vector2(cx, h * 0.40), 44, ink)                        # head
		for yy in range(int(h * 0.47), h):                                  # shoulders + body
			var half := 60.0 + (yy - h * 0.47) * 0.35
			for xx in range(int(cx - half), int(cx + half)):
				if xx >= 0 and xx < w:
					img.set_pixel(xx, yy, ink)
	return ImageTexture.create_from_image(img)

func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for yy in range(int(c.y - r), int(c.y + r)):
		for xx in range(int(c.x - r), int(c.x + r)):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height() and Vector2(xx, yy).distance_to(c) <= r:
				img.set_pixel(xx, yy, img.get_pixel(xx, yy).blend(col))

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		var path := "%s/card_styles.png" % _out
		_vp.get_texture().get_image().save_png(path)
		print("saved ", path)
		quit()
	return false
