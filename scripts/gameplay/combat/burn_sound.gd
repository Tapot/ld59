class_name BurnSound
extends Node


const SHORT_POLYPHONY: int = 2
const LONG_TARGET_THRESHOLD: int = 3
const END_SILENCE_SEC: float = 0.15
const SHORT_PITCH_MIN: float = 0.9
const SHORT_PITCH_MAX: float = 1.15
const SHORT_VOLUME_DB: float = -10.0
const LONG_VOLUME_DB: float = -8.0
const END_VOLUME_DB: float = -10.0
const SHORT_GAP_MIN: float = 0.05
const SHORT_GAP_MAX: float = 0.10

var _short_players: Array[AudioStreamPlayer] = []
var _long_player: AudioStreamPlayer
var _end_player: AudioStreamPlayer
var _was_burning: bool = false
var _silence_elapsed: float = 0.0
var _last_short_index: int = -1
var _short_gap_remaining: float = 0.0


func _ready() -> void:
	for i: int in SHORT_POLYPHONY:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_short_players.append(p)
	_long_player = AudioStreamPlayer.new()
	_long_player.bus = "Master"
	add_child(_long_player)
	_end_player = AudioStreamPlayer.new()
	_end_player.bus = "Master"
	add_child(_end_player)


func report_tick(target_count: int, delta: float) -> void:
	if _short_gap_remaining > 0.0:
		_short_gap_remaining -= delta

	if target_count >= LONG_TARGET_THRESHOLD:
		_ensure_long_playing()
		_silence_elapsed = 0.0
		_was_burning = true
		return

	_stop_long()

	if target_count > 0:
		_silence_elapsed = 0.0
		_was_burning = true
		if _short_gap_remaining <= 0.0:
			_maybe_play_short()
		return

	# target_count == 0: no damage this tick
	if _was_burning:
		_silence_elapsed += delta
		if _silence_elapsed >= END_SILENCE_SEC:
			_play_end()
			_was_burning = false
			_silence_elapsed = 0.0


func _maybe_play_short() -> void:
	var sounds: Array[AudioStream] = Audio.BURN_SHORT_SOUNDS
	if sounds.is_empty():
		return
	var free_player: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _short_players:
		if not p.playing:
			free_player = p
			break
	if free_player == null:
		return
	var idx: int = randi() % sounds.size()
	if sounds.size() > 1 and idx == _last_short_index:
		idx = (idx + 1) % sounds.size()
	_last_short_index = idx
	free_player.stream = sounds[idx]
	free_player.pitch_scale = randf_range(SHORT_PITCH_MIN, SHORT_PITCH_MAX)
	free_player.volume_db = Audio.get_sfx_volume_db(SHORT_VOLUME_DB)
	free_player.play()
	_short_gap_remaining = randf_range(SHORT_GAP_MIN, SHORT_GAP_MAX)


func _ensure_long_playing() -> void:
	if _long_player.playing:
		_long_player.volume_db = Audio.get_sfx_volume_db(LONG_VOLUME_DB)
		return
	_long_player.stream = Audio.BURN_LONG_SOUND
	_long_player.volume_db = Audio.get_sfx_volume_db(LONG_VOLUME_DB)
	_long_player.pitch_scale = 1.0
	_long_player.play()


func _stop_long() -> void:
	if _long_player.playing:
		_long_player.stop()


func _play_end() -> void:
	_end_player.stream = Audio.BURN_END_SOUND
	_end_player.volume_db = Audio.get_sfx_volume_db(END_VOLUME_DB)
	_end_player.pitch_scale = 1.0
	_end_player.play()


func stop_all() -> void:
	_stop_long()
	for p: AudioStreamPlayer in _short_players:
		if p.playing:
			p.stop()
	_was_burning = false
	_silence_elapsed = 0.0
