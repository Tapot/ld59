extends Node


signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal common_volume_changed(value: float)


const SETTINGS_PATH: String = "user://audio_settings.cfg"
const MUTED_VOLUME_DB: float = -80.0
const BUTTON_PITCH_MIN: float = 0.92
const BUTTON_PITCH_MAX: float = 1.08
const BUTTON_VOLUME_BASE: float = -6.0

const BUTTON_CLICK_SOUND: AudioStream = preload("res://assets/audio/ld59_drop1.mp3")
const MUSIC_MAIN_MENU: Array[AudioStream] = [
	preload("res://assets/audio/ld59_main_menu.mp3"),
]
const MUSIC_BATTLE: Array[AudioStream] = [
	preload("res://assets/audio/ld59_battle_1.mp3"),
	preload("res://assets/audio/ld59_battle_2.mp3"),
	preload("res://assets/audio/ld59_battle_3.mp3"),
]
const MUSIC_RUNE_ROOM: Array[AudioStream] = [
	preload("res://assets/audio/ld59_rune-room.mp3"),
]
const MUSIC_POPULATION_DOWN: AudioStream = preload("res://assets/audio/ld59_population_goes_down.mp3")
const CROSSFADE_DURATION: float = 1.5
const BUBBLE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/ld59_bubble1.mp3"),
	preload("res://assets/audio/ld59_bubble2.mp3"),
	preload("res://assets/audio/ld59_bubble3.mp3"),
	preload("res://assets/audio/ld59_bubble4.mp3"),
]
const HIT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/ld59_hit1.mp3"),
	preload("res://assets/audio/ld59_hit2.mp3"),
]
const POWERUP_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/ld59_powerup1.mp3"),
	preload("res://assets/audio/ld59_powerup2.mp3"),
]

var _button_sfx: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _inactive_music: AudioStreamPlayer
var _crossfade_tween: Tween
var _current_music_key: String = ""
var _current_music_loops: bool = true
var _music_volume_linear: float = 1.0
var _sfx_volume_linear: float = 1.0
var _suppress_next_click: bool = false


func _ready() -> void:
	_load_settings()

	_button_sfx = AudioStreamPlayer.new()
	_button_sfx.stream = BUTTON_CLICK_SOUND
	add_child(_button_sfx)

	_music_a = AudioStreamPlayer.new()
	_music_a.volume_db = MUTED_VOLUME_DB
	_music_a.finished.connect(_on_music_finished.bind(_music_a))
	add_child(_music_a)

	_music_b = AudioStreamPlayer.new()
	_music_b.volume_db = MUTED_VOLUME_DB
	_music_b.finished.connect(_on_music_finished.bind(_music_b))
	add_child(_music_b)

	_active_music = _music_a
	_inactive_music = _music_b

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


func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player != _active_music:
		return
	if _current_music_loops:
		player.play()


func _apply_music_volume() -> void:
	var target_db: float = _linear_volume_to_db(_music_volume_linear)
	if _active_music and _active_music.playing:
		if _crossfade_tween == null or not _crossfade_tween.is_valid():
			_active_music.volume_db = target_db


func play_music(key: String, tracks: Array[AudioStream], loop: bool = true, fade_duration: float = CROSSFADE_DURATION) -> void:
	if key == _current_music_key:
		return

	_current_music_key = key
	_current_music_loops = loop
	var track: AudioStream = tracks[randi() % tracks.size()]

	var temp: AudioStreamPlayer = _active_music
	_active_music = _inactive_music
	_inactive_music = temp

	_active_music.stream = track
	_active_music.play()
	_crossfade(_active_music, _inactive_music, fade_duration)


func play_music_once(key: String, stream: AudioStream, fade_duration: float = CROSSFADE_DURATION) -> void:
	play_music(key, [stream] as Array[AudioStream], false, fade_duration)


func stop_music(fade: bool = true) -> void:
	_current_music_key = ""
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	if not fade:
		_active_music.stop()
		_inactive_music.stop()
		return

	var tw: Tween = create_tween()
	tw.tween_property(_active_music, "volume_db", MUTED_VOLUME_DB, CROSSFADE_DURATION)
	tw.tween_callback(_active_music.stop)


func _crossfade(fade_in: AudioStreamPlayer, fade_out: AudioStreamPlayer, duration: float = CROSSFADE_DURATION) -> void:
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	var target_db: float = _linear_volume_to_db(_music_volume_linear)
	fade_in.volume_db = MUTED_VOLUME_DB
	_crossfade_tween = create_tween().set_parallel(true)
	_crossfade_tween.tween_property(fade_in, "volume_db", target_db, duration)
	_crossfade_tween.tween_property(fade_out, "volume_db", MUTED_VOLUME_DB, duration)
	_crossfade_tween.chain().tween_callback(fade_out.stop)


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
