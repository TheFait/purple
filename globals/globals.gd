extends Node

enum SUITS {HEARTS, SPADES, DIAMONDS, CLUBS}
enum TURN_PHASE {GAME_START, TURN_START, GUESS, REVEAL, RESULT}
signal change_phase()
signal update_ui()

## The PURPLE logo is shown once per app launch: during the first game, until the first guess.
var logo_seen: bool = false

var cards_in_deck: int:
	set(value):
		cards_in_deck = value
		update_ui.emit()
		
var cards_in_stack: int:
	set(value):
		cards_in_stack = value
		update_ui.emit()

func progress_game():
	change_phase.emit()

# --- card look -----------------------------------------------------------------
## Which face the cards use: "classic" is the original PNG art, the rest are CardFace styles.
## Switched while playing (F2 / the CARDS button) and remembered between launches.
signal card_style_changed()
const CardFaceScript := preload("res://scenes/cards/card_face.gd")
const CARD_STYLES: Array[String] = ["classic", "neon_noir", "sunset_chrome", "cream_classic", "wireframe"]
const PHOTO_MODES: Array[String] = ["on", "off"]
## Card-back photos. Not committed (see .gitignore): every image in the folder is part of
## the collection, and each card picks one at random.
const PHOTO_DIR := "res://custom_deck"
const CARD_SETTINGS_PATH := "user://card_look.cfg"

var card_style: String = "sunset_chrome"   # the default look; CARDS / F2 cycles it and the choice is saved
var card_photos: String = "on"   # the photo card back, when custom_deck/ has a photo
var _back_photos: Array[Texture2D] = []
var _backs_loaded := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CARD_SETTINGS_PATH) == OK:
		var s := String(cfg.get_value("cards", "style", card_style))
		var p := String(cfg.get_value("cards", "photos", card_photos))
		card_style = s if CARD_STYLES.has(s) else card_style
		card_photos = p if PHOTO_MODES.has(p) else card_photos

func cycle_card_style() -> void:
	card_style = CARD_STYLES[(CARD_STYLES.find(card_style) + 1) % CARD_STYLES.size()]
	_save_card_look()
	card_style_changed.emit()

func cycle_card_photos() -> void:
	card_photos = PHOTO_MODES[(PHOTO_MODES.find(card_photos) + 1) % PHOTO_MODES.size()]
	_save_card_look()
	card_style_changed.emit()

func card_style_title() -> String:
	if card_style == "classic":
		return "Classic"
	return String(CardFaceScript.STYLES[card_style].title)

func _save_card_look() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cards", "style", card_style)
	cfg.set_value("cards", "photos", card_photos)
	cfg.save(CARD_SETTINGS_PATH)

## The card-back collection: every JPEG / PNG / WebP in custom_deck/ (extension optional), loaded once.
func back_photos() -> Array[Texture2D]:
	if _backs_loaded:
		return _back_photos
	_backs_loaded = true
	if not DirAccess.dir_exists_absolute(PHOTO_DIR):
		return _back_photos
	var files := DirAccess.get_files_at(PHOTO_DIR)
	files.sort()
	for f in files:
		# Any file counts, extension or not (the format is read from the bytes); hidden
		# files like .gdignore and .DS_Store are skipped.
		if f.begins_with("."):
			continue
		var t: Texture2D = CardFaceScript.load_photo("%s/%s" % [PHOTO_DIR, f])
		if t != null:
			_back_photos.append(t)
	return _back_photos

func back_photo_count() -> int:
	return back_photos().size()

## The back image at `index` in the collection (wraps), or null when there are none.
func back_photo(index: int) -> Texture2D:
	var all := back_photos()
	return all[posmod(index, all.size())] if all.size() > 0 else null

## A random index into the collection, different from `avoid` when there is a choice.
func random_back_index(avoid: int = -1) -> int:
	var n := back_photo_count()
	if n <= 1:
		return 0
	var i := randi() % n
	while i == avoid:
		i = randi() % n
	return i
