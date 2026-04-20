extends Node


signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal common_volume_changed(value: float)


const SETTINGS_PATH: String = "user://audio_settings.cfg"
const MUTED_VOLUME_DB: float = -80.0
const BUTTON_PITCH_MIN: float = 0.92
const BUTTON_PITCH_MAX: float = 1.08
const BUTTON_VOLUME_BASE: float = -6.0

const BUTTON_CLICK_SOUND: AudioStream = preload("res://audio/ld59_drop1.mp3")
const MUSIC_STREAM: AudioStream = preload("res://audio/ld59.mp3")
const BUBBLE_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_bubble1.mp3"),
	preload("res://audio/ld59_bubble2.mp3"),
	preload("res://audio/ld59_bubble3.mp3"),
	preload("res://audio/ld59_bubble4.mp3"),
]
const HIT_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_hit1.mp3"),
	preload("res://audio/ld59_hit2.mp3"),
]
const POWERUP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_powerup1.mp3"),
	preload("res://audio/ld59_powerup2.mp3"),
]

var _button_sfx: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_volume_linear: float = 1.0
var _sfx_volume_linear: float = 1.0
var _suppress_next_click: bool = false


func _ready() -> void:
	_load_settings()

	_button_sfx = AudioStreamPlayer.new()
	_button_sfx.stream = BUTTON_CLICK_SOUND
	add_child(_button_sfx)

	_music = AudioStreamPlayer.new()
	_music.stream = MUSIC_STREAM
	_music.finished.connect(_on_music_finished)
	add_child(_music)

	_apply_music_volume()
	_music.play()

	get_tree().node_added.connect(_on_node_added)


func get_music_volume_linear() -> float:
	return _music_volume_linear


func get_common_volume_linear() -> float:
	return (_music_volume_linear + _sfx_volume_linear) * 0.5


func set_music_volume_linear(value: float) -> void:
	var sanitized: float = _sanitize_linear_volume(value)
	if is_equal_approx(_music_volume_linear, sanitized):
		return

	_music_volume_linear = sanitized
	_apply_music_volume()
	_save_settings()
	music_volume_changed.emit(_music_volume_linear)
	common_volume_changed.emit(get_common_volume_linear())


func get_sfx_volume_linear() -> float:
	return _sfx_volume_linear


func set_sfx_volume_linear(value: float) -> void:
	var sanitized: float = _sanitize_linear_volume(value)
	if is_equal_approx(_sfx_volume_linear, sanitized):
		return

	_sfx_volume_linear = sanitized
	_save_settings()
	sfx_volume_changed.emit(_sfx_volume_linear)
	common_volume_changed.emit(get_common_volume_linear())


func set_common_volume_linear(value: float) -> void:
	var sanitized: float = _sanitize_linear_volume(value)
	var changed: bool = false

	if not is_equal_approx(_music_volume_linear, sanitized):
		_music_volume_linear = sanitized
		_apply_music_volume()
		music_volume_changed.emit(_music_volume_linear)
		changed = true

	if not is_equal_approx(_sfx_volume_linear, sanitized):
		_sfx_volume_linear = sanitized
		sfx_volume_changed.emit(_sfx_volume_linear)
		changed = true

	if not changed:
		return

	_save_settings()
	common_volume_changed.emit(get_common_volume_linear())


func get_sfx_volume_db(base_volume_db: float = 0.0) -> float:
	return maxf(MUTED_VOLUME_DB, base_volume_db + _linear_volume_to_db(_sfx_volume_linear))


func suppress_next_button_click() -> void:
	_suppress_next_click = true


func _on_node_added(node: Node) -> void:
	if not (node is Button):
		return

	var button: Button = node as Button
	if button == null:
		return

	if not button.pressed.is_connected(_play_button_click):
		button.pressed.connect(_play_button_click)


func _play_button_click() -> void:
	if _suppress_next_click:
		_suppress_next_click = false
		return

	_button_sfx.pitch_scale = randf_range(BUTTON_PITCH_MIN, BUTTON_PITCH_MAX)
	_button_sfx.volume_db = get_sfx_volume_db(BUTTON_VOLUME_BASE)
	_button_sfx.play()


func _on_music_finished() -> void:
	_music.play()


func _apply_music_volume() -> void:
	if _music == null:
		return

	_music.volume_db = _linear_volume_to_db(_music_volume_linear)


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SETTINGS_PATH)
	if error != OK:
		return

	_music_volume_linear = _sanitize_linear_volume(
		float(config.get_value("audio", "music_volume_linear", 1.0))
	)
	_sfx_volume_linear = _sanitize_linear_volume(
		float(config.get_value("audio", "sfx_volume_linear", 1.0))
	)


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_volume_linear", _music_volume_linear)
	config.set_value("audio", "sfx_volume_linear", _sfx_volume_linear)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Audio settings could not be saved to %s" % SETTINGS_PATH)


func _sanitize_linear_volume(value: float) -> float:
	return clampf(value, 0.0, 1.0)


func _linear_volume_to_db(value: float) -> float:
	if value <= 0.0:
		return MUTED_VOLUME_DB

	return linear_to_db(value)
