class_name Game
extends Control


const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const WAVE_PROGRESS_COLORS: Array[Color] = [
	Color(0.2, 0.55, 1.0, 1.0),
	Color(1.0, 0.68, 0.18, 1.0),
	Color(0.34, 0.86, 0.42, 1.0)
]


@export var monsters: Array[Monster] = []

@onready var monster_spawner: MonsterSpawner = $OuterFrame/PlayfieldFrame/World/MonsterSpawner
@onready var wave_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveLabel
@onready var wave1_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave1Label
@onready var wave2_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave2Label
@onready var wave3_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave3Label
@onready var wave_progress_track: Panel = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveProgressTrack
@onready var wave_progress_fill: ColorRect = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveProgressTrack/WaveProgressFill
@onready var kills_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/KillsLabel
@onready var exit_button: Button = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/ExitButton

var _kill_count: int = 0
var _wave_labels: Array[Label] = []


func _ready() -> void:
	_wave_labels = [wave1_label, wave2_label, wave3_label]
	wave_label.visible = false
	monster_spawner.monster_spawned.connect(_on_monster_spawned)
	monster_spawner.wave_started.connect(_on_wave_started)
	monster_spawner.all_waves_completed.connect(_on_all_waves_completed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	_update_wave_waiting_ui()


func _process(_delta: float) -> void:
	_update_wave_waiting_ui()


func add_monster(monster: Monster) -> void:
	if monsters.has(monster):
		return

	monsters.append(monster)
	monster.died.connect(_on_monster_died, CONNECT_ONE_SHOT)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)


func _on_monster_spawned(monster: Monster) -> void:
	add_monster(monster)


func _on_wave_started(wave_number: int) -> void:
	_apply_wave_progress(
		float(wave_number) / float(maxi(1, monster_spawner.get_total_waves())),
		wave_number,
		maxi(1, monster_spawner.get_total_waves())
	)


func _on_all_waves_completed() -> void:
	_update_wave_waiting_ui()


func _on_monster_died(_monster: Monster) -> void:
	_kill_count += 1
	kills_label.text = "Kills: %d" % _kill_count


func _on_monster_tree_exited(monster: Monster) -> void:
	monsters.erase(monster)


func _update_wave_waiting_ui() -> void:
	var total_waves: int = maxi(1, monster_spawner.get_total_waves())
	var current_wave_number: int = monster_spawner.get_current_wave_number()
	var progress_value: float = 0.0

	if monster_spawner.are_waves_completed():
		progress_value = 1.0
	elif current_wave_number > 0:
		progress_value = float(current_wave_number) / float(total_waves)

	_apply_wave_progress(progress_value, current_wave_number, total_waves)


func _apply_wave_progress(progress_value: float, current_wave_number: int, total_waves: int) -> void:
	var clamped_progress: float = clampf(progress_value, 0.0, 1.0)
	var track_height: float = wave_progress_track.size.y - 8.0
	var fill_height: float = track_height * clamped_progress
	wave_progress_fill.position.y = 4.0 + (track_height - fill_height)
	wave_progress_fill.size.y = fill_height
	wave_progress_fill.color = _get_wave_progress_color(current_wave_number)

	for index: int in _wave_labels.size():
		var label: Label = _wave_labels[index]
		if index < total_waves:
			label.visible = true
			if index < current_wave_number:
				label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			else:
				label.modulate = Color(0.7, 0.7, 0.7, 1.0)
			continue

		label.visible = false


func _get_wave_progress_color(current_wave_number: int) -> Color:
	if monster_spawner.are_waves_completed():
		return WAVE_PROGRESS_COLORS[WAVE_PROGRESS_COLORS.size() - 1]

	var safe_index: int = clampi(maxi(0, current_wave_number - 1), 0, WAVE_PROGRESS_COLORS.size() - 1)
	return WAVE_PROGRESS_COLORS[safe_index]


func _on_exit_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
