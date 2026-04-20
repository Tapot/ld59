extends Node

const INITIAL_RUNES: int = 3000
const MONSTERS_FIELD_POS_X: float = 65.0
const MONSTERS_FIELD_POS_Y: float = 55.0
const MONSTERS_FIELD_SIZE_X: float = 815.0
const MONSTERS_FIELD_SIZE_Y: float = 525.0
const MONSTERS_FIELD_MIN: Vector2 = Vector2(
	MONSTERS_FIELD_POS_X, MONSTERS_FIELD_POS_Y
)
const MONSTERS_FIELD_MAX: Vector2 = Vector2(
	MONSTERS_FIELD_POS_X + MONSTERS_FIELD_SIZE_X,
	MONSTERS_FIELD_POS_Y + MONSTERS_FIELD_SIZE_Y
)

const BUTTON_CLICK_SOUND: AudioStream = preload("res://audio/ld59_drop1.mp3")
const BUTTON_PITCH_MIN: float = 0.92
const BUTTON_PITCH_MAX: float = 1.08
const MUSIC_STREAM: AudioStream = preload("res://audio/ld59.mp3")

var _button_sfx: AudioStreamPlayer
var _music: AudioStreamPlayer
var _suppress_next_click: bool = false


func _ready() -> void:
	_button_sfx = AudioStreamPlayer.new()
	_button_sfx.stream = BUTTON_CLICK_SOUND
	_button_sfx.volume_db = -6.0
	add_child(_button_sfx)

	_music = AudioStreamPlayer.new()
	_music.stream = MUSIC_STREAM
	_music.autoplay = true
	_music.finished.connect(_music.play)
	add_child(_music)

	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Button:
		node.pressed.connect(_play_button_click)


func suppress_next_button_click() -> void:
	_suppress_next_click = true


func _play_button_click() -> void:
	if _suppress_next_click:
		_suppress_next_click = false
		return

	_button_sfx.pitch_scale = randf_range(BUTTON_PITCH_MIN, BUTTON_PITCH_MAX)
	_button_sfx.play()
