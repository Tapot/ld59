class_name Game
extends Control


const M_SCENE = preload("res://scripts/monster.gd")


@export var monsters: Array[Monster] = []

@onready var monster_spawner: MonsterSpawner = $World/MonsterSpawner
@onready var wave_label: Label = $WaveLabel
@onready var next_wave_timer_label: Label = $NextWaveTimerLabel


func _ready() -> void:
	monster_spawner.monster_spawned.connect(_on_monster_spawned)
	monster_spawner.wave_started.connect(_on_wave_started)
	_update_next_wave_timer_label()


func _process(_delta: float) -> void:
	_update_next_wave_timer_label()


func add_monster(monster: Monster) -> void:
	if monsters.has(monster):
		return

	monsters.append(monster)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)


func _on_monster_spawned(monster: Monster) -> void:
	add_monster(monster)


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_monster_tree_exited(monster: Monster) -> void:
	monsters.erase(monster)


func _update_next_wave_timer_label() -> void:
	if monster_spawner.has_more_waves() and monster_spawner.is_waiting_for_next_wave():
		next_wave_timer_label.text = "Next wave in: %.1f" % monster_spawner.get_time_until_next_wave()
		next_wave_timer_label.visible = true
		return

	next_wave_timer_label.visible = false
