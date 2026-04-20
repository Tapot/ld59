extends Control


const RUNE_SELECTION_SCENE_PATH: String = "res://scenes/flow/upgrades_screen.tscn"
const TOP_COUNTER_Y: float = 30.0

@onready var intro_text_image: TextureRect = $IntroTextImage
@onready var population_counter: Control = $PopulationCounter

var _phase: int = 0
var _phase_elapsed: float = 0.0
var _phase_duration: float = 1.8
var _population_start: int = 0
var _population_end: int = 0
var _counter_moved_to_top: bool = false


func _ready() -> void:
	_population_start = SessionState.get_population_start()
	_population_end = maxi(0, _population_start - SessionState.get_intro_preview_loss())
	_phase_duration = SessionState.get_intro_counter_duration()
	Audio.play_music_once("population_down", Audio.MUSIC_POPULATION_DOWN, 0.3)
	_update_phase_ui()


func _process(delta: float) -> void:
	_phase_elapsed += delta
	var progress: float = clampf(_phase_elapsed / _phase_duration, 0.0, 1.0)

	if _phase == 0:
		var current_value: int = int(round(lerpf(0.0, float(_population_start), progress)))
		population_counter.set_population_value(SessionState.format_population(current_value))
	elif _phase == 1:
		if not _counter_moved_to_top:
			_counter_moved_to_top = true
			_move_counter_to_top()
		var drain_value: int = int(round(lerpf(float(_population_start), float(_population_end), progress)))
		population_counter.set_population_value(SessionState.format_population(drain_value))
	else:
		_finish_sequence()
		return

	if progress < 1.0:
		return

	_phase += 1
	_phase_elapsed = 0.0
	_update_phase_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_finish_sequence()


func _update_phase_ui() -> void:
	intro_text_image.visible = _phase == 1


func _finish_sequence() -> void:
	if not is_inside_tree():
		return
	SessionState.set_population_current(_population_end)
	get_tree().change_scene_to_file(RUNE_SELECTION_SCENE_PATH)


func _move_counter_to_top() -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(population_counter, "global_position:y", TOP_COUNTER_Y, 0.6)
