class_name Game
extends Control


const RUN_END_CHOICE_SCENE_PATH: String = "res://scenes/flow/run_end_choice.tscn"
const UPGRADES_SCENE_PATH: String = "res://scenes/flow/upgrades_screen.tscn"
const MONSTER_PROJECTILE_SCENE: PackedScene = preload("res://scenes/gameplay/combat/monster_projectile.tscn")
const WAVE_PROGRESS_COLORS: Array[Color] = [
	Color(0.2, 0.55, 1.0, 1.0),
	Color(1.0, 0.68, 0.18, 1.0),
	Color(0.34, 0.86, 0.42, 1.0)
]

enum BurstTrigger {
	SPAWN,
	EXPIRE,
	KILL
}

const BUBBLE_SOUNDS: Array[AudioStream] = [
	preload("res://audio/ld59_bubble1.mp3"),
	preload("res://audio/ld59_bubble2.mp3"),
	preload("res://audio/ld59_bubble3.mp3"),
	preload("res://audio/ld59_bubble4.mp3"),
]
const BUBBLE_PITCH_MIN: float = 0.85
const BUBBLE_PITCH_MAX: float = 1.15
const BUBBLE_VOLUME_BASE: float = -6.0
const BUBBLE_VOLUME_RANGE: float = 1.5


@onready var monster_spawner: MonsterSpawner = $OuterFrame/PlayfieldFrame/World/MonsterSpawner
@onready var projectile_container: Node2D = $OuterFrame/PlayfieldFrame/World/Projectiles
@onready var player_attack: PlayerAttack = $OuterFrame/PlayfieldFrame/World/PlayerAttack
@onready var wave1_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave1Label
@onready var wave2_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave2Label
@onready var wave3_label: Label = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveNames/Wave3Label
@onready var wave_progress_track: Panel = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi/WaveTrackRow/WaveProgressTrack
@onready var wave_progress_ui: WaveUI = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/WaveUi
@onready var exit_button: Button = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/ExitButton
@onready var _bubble_sfx_pool: Array[AudioStreamPlayer] = [$BubbleSfx1, $BubbleSfx2, $BubbleSfx3]

var _kill_count: int = 0
var _monsters: Array[Monster] = []
var _wave_labels: Array[Label] = []
var _all_waves_completed: bool = false
var _run_transition_started: bool = false


func _ready() -> void:
	_wave_labels = [wave1_label, wave2_label, wave3_label]
	_apply_meta_to_run()
	monster_spawner.monster_spawned.connect(_on_monster_spawned)
	monster_spawner.wave_started.connect(_on_wave_started)
	monster_spawner.all_waves_completed.connect(_on_all_waves_completed)
	wave_progress_track.resized.connect(_refresh_wave_ui)
	exit_button.pressed.connect(_on_exit_button_pressed)
	call_deferred("_refresh_wave_ui")
	monster_spawner.begin_run()


func add_monster(monster: Monster) -> void:
	if _monsters.has(monster):
		return

	_monsters.append(monster)
	monster.killed.connect(_on_monster_killed, CONNECT_ONE_SHOT)
	monster.expired.connect(_on_monster_expired, CONNECT_ONE_SHOT)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)


func _on_monster_spawned(monster: Monster) -> void:
	add_monster(monster)
	_refresh_wave_ui()
	_spawn_monster_burst(monster, BurstTrigger.SPAWN)


func _on_wave_started(_wave_number: int) -> void:
	_refresh_wave_ui()


func _on_all_waves_completed() -> void:
	_all_waves_completed = true
	_refresh_wave_ui()
	_maybe_finish_run_naturally()


func _on_monster_killed(monster: Monster) -> void:
	_kill_count += 1
	SessionState.add_runes(SessionState.get_runes_for_monster_kill(player_attack.is_targeting_monster(monster)))
	_spawn_monster_burst(monster, BurstTrigger.KILL)
	_play_bubble_sfx()


func _on_monster_expired(monster: Monster) -> void:
	_spawn_monster_burst(monster, BurstTrigger.EXPIRE)


func _on_monster_tree_exited(monster: Monster) -> void:
	_monsters.erase(monster)
	_refresh_wave_ui()
	_maybe_finish_run_naturally()


func _refresh_wave_ui() -> void:
	var total_waves: int = maxi(1, monster_spawner.get_total_waves())
	var current_wave_number: int = monster_spawner.get_current_wave_number()
	var progress_value: float = monster_spawner.get_current_wave_remaining_progress()

	if monster_spawner.are_waves_completed():
		progress_value = 0.0

	_apply_wave_progress(progress_value, current_wave_number, total_waves)


func _apply_wave_progress(progress_value: float, current_wave_number: int, total_waves: int) -> void:
	var clamped_progress: float = clampf(progress_value, 0.0, 1.0)
	wave_progress_ui.set_progress(clamped_progress, 1.0)

	for index: int in _wave_labels.size():
		var label: Label = _wave_labels[index]
		if index < total_waves:
			label.visible = true
			if monster_spawner.are_waves_completed():
				label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			elif index == current_wave_number - 1:
				label.modulate = _get_wave_progress_color(current_wave_number)
			elif index < current_wave_number - 1:
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


func _apply_meta_to_run() -> void:
	player_attack.attack_radius = SessionState.get_attack_radius(player_attack.attack_radius)
	player_attack.damage_per_second = SessionState.get_damage_per_second(player_attack.damage_per_second)
	player_attack.lifetime_slow_scale = SessionState.get_lifetime_slow_scale(player_attack.lifetime_slow_scale)
	player_attack.stasis_field_enabled = SessionState.is_stasis_field_enabled()
	player_attack.refresh_runtime_configuration()

	monster_spawner.waves = SessionState.get_waves(monster_spawner.waves)
	monster_spawner.time_between_groups = SessionState.get_time_between_groups(monster_spawner.time_between_groups)
	monster_spawner.monster_lifetime_bonus_seconds = SessionState.get_monster_lifetime_bonus_seconds()
	monster_spawner.monster_move_speed_multiplier = SessionState.get_monster_move_speed_multiplier()


func _maybe_finish_run_naturally() -> void:
	if _run_transition_started:
		return

	if not _all_waves_completed:
		return

	if not _monsters.is_empty():
		return

	_run_transition_started = true
	SessionState.finish_current_run(_kill_count, true)
	get_tree().change_scene_to_file(RUN_END_CHOICE_SCENE_PATH)


func _on_exit_button_pressed() -> void:
	if _run_transition_started:
		return

	_run_transition_started = true
	SessionState.finish_current_run(_kill_count, false)
	get_tree().change_scene_to_file(UPGRADES_SCENE_PATH)


func _play_bubble_sfx() -> void:
	for player: AudioStreamPlayer in _bubble_sfx_pool:
		if not player.playing:
			player.stream = BUBBLE_SOUNDS[randi() % BUBBLE_SOUNDS.size()]
			player.pitch_scale = randf_range(BUBBLE_PITCH_MIN, BUBBLE_PITCH_MAX)
			player.volume_db = BUBBLE_VOLUME_BASE + randf_range(-BUBBLE_VOLUME_RANGE, BUBBLE_VOLUME_RANGE)
			player.play()
			return


func _spawn_monster_burst(monster: Monster, trigger: int) -> void:
	if projectile_container == null or not is_instance_valid(projectile_container):
		return

	var projectile_count: int = 0
	var projectile_pierces: int = SessionState.get_monster_burst_pierce_count()
	var projectile_bounces: int = SessionState.get_monster_burst_bounce_count()
	var projectile_damage: float = 0.0
	var projectile_speed: float = 0.0
	var projectile_range: float = 0.0
	var projectile_tint: Color = Color.WHITE

	match trigger:
		BurstTrigger.SPAWN:
			if not SessionState.is_monster_spawn_burst_enabled():
				return

			projectile_count = SessionState.get_monster_burst_projectile_count()
			projectile_damage = 18.0
			projectile_speed = 330.0
			projectile_range = 185.0
			projectile_tint = Color(0.22, 0.82, 1.0, 1.0)
		BurstTrigger.EXPIRE:
			if not SessionState.is_monster_expire_burst_enabled():
				return

			projectile_count = SessionState.get_monster_burst_projectile_count()
			projectile_damage = 22.0
			projectile_speed = 360.0
			projectile_range = 200.0
			projectile_tint = Color(0.34, 0.9, 0.42, 1.0)
		BurstTrigger.KILL:
			if not SessionState.is_monster_kill_burst_enabled():
				return

			projectile_count = SessionState.get_monster_burst_projectile_count()
			projectile_damage = 28.0
			projectile_speed = 390.0
			projectile_range = 220.0
			projectile_tint = Color(1.0, 0.68, 0.18, 1.0)

	projectile_range += SessionState.get_monster_burst_range_bonus()
	_spawn_projectile_burst(
		monster,
		projectile_count,
		projectile_damage,
		projectile_speed,
		projectile_range,
		projectile_pierces,
		projectile_bounces,
		projectile_tint
	)


func _spawn_projectile_burst(
	source_monster: Monster,
	projectile_count: int,
	projectile_damage: float,
	projectile_speed: float,
	projectile_range: float,
	projectile_pierces: int,
	projectile_bounces: int,
	projectile_tint: Color
) -> void:
	if projectile_count <= 0:
		return

	var origin: Vector2 = projectile_container.to_local(source_monster.global_position)
	var preferred_direction: Vector2 = _get_burst_target_direction(source_monster)
	if projectile_count == 1:
		if preferred_direction == Vector2.ZERO:
			preferred_direction = Vector2.from_angle(randf_range(0.0, TAU))

		_spawn_burst_projectile(
			source_monster,
			origin,
			preferred_direction,
			projectile_damage,
			projectile_speed,
			projectile_range,
			projectile_pierces,
			projectile_bounces,
			projectile_tint
		)
		return

	var angle_step: float = TAU / float(projectile_count)
	var angle_offset: float = randf_range(0.0, angle_step)
	if preferred_direction != Vector2.ZERO:
		angle_offset = preferred_direction.angle()

	for index: int in projectile_count:
		var angle: float = angle_offset + (float(index) * angle_step)
		var direction: Vector2 = Vector2.RIGHT.rotated(angle)
		_spawn_burst_projectile(
			source_monster,
			origin,
			direction,
			projectile_damage,
			projectile_speed,
			projectile_range,
			projectile_pierces,
			projectile_bounces,
			projectile_tint
		)


func _spawn_burst_projectile(
	source_monster: Monster,
	origin: Vector2,
	direction: Vector2,
	projectile_damage: float,
	projectile_speed: float,
	projectile_range: float,
	projectile_pierces: int,
	projectile_bounces: int,
	projectile_tint: Color
) -> void:
	var projectile: MonsterProjectile = MONSTER_PROJECTILE_SCENE.instantiate() as MonsterProjectile
	if projectile == null:
		return

	var start_position: Vector2 = origin + direction * 24.0
	var speed_variation: float = randf_range(0.92, 1.08)
	projectile.setup(
		start_position,
		direction,
		projectile_damage,
		projectile_speed * speed_variation,
		projectile_range,
		projectile_pierces,
		projectile_bounces,
		projectile_tint,
		source_monster,
	)
	Callable(self, "_add_burst_projectile_to_container").call_deferred(projectile)


func _add_burst_projectile_to_container(projectile: MonsterProjectile) -> void:
	if projectile == null:
		return

	if projectile_container == null or not is_instance_valid(projectile_container):
		if is_instance_valid(projectile):
			projectile.queue_free()
		return

	projectile_container.add_child(projectile)


func _get_burst_target_direction(source_monster: Monster) -> Vector2:
	if not is_instance_valid(source_monster):
		return Vector2.ZERO

	var source_position: Vector2 = source_monster.global_position
	var closest_distance_squared: float = INF
	var closest_direction: Vector2 = Vector2.ZERO

	for monster: Monster in _monsters:
		if monster == source_monster:
			continue

		if not is_instance_valid(monster):
			continue

		if not monster.monitorable:
			continue

		var offset: Vector2 = monster.global_position - source_position
		var distance_squared: float = offset.length_squared()
		if distance_squared <= 1.0:
			continue

		if distance_squared >= closest_distance_squared:
			continue

		closest_distance_squared = distance_squared
		closest_direction = offset.normalized()

	return closest_direction
