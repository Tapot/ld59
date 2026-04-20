class_name Game
extends Control


const MONSTER_PROJECTILE_SCENE: PackedScene = preload("res://scenes/gameplay/combat/monster_projectile.tscn")
const RUN_END_MONSTER_DISAPPEAR_DURATION: float = 0.7
const RUN_END_FADE_DURATION: float = 0.35

const BUBBLE_PITCH_MIN: float = 0.85
const BUBBLE_PITCH_MAX: float = 1.15
const BUBBLE_VOLUME_BASE: float = -6.0
const BUBBLE_VOLUME_RANGE: float = 1.5

@onready var monster_spawner: MonsterSpawner = $OuterFrame/PlayfieldFrame/World/MonsterSpawner
@onready var projectile_container: Node2D = $OuterFrame/PlayfieldFrame/World/Projectiles
@onready var player_attack: PlayerAttack = $OuterFrame/PlayfieldFrame/World/PlayerAttack
@onready var drain_label: Label = $OuterFrame/TopBar/TopBarMargin/TopBarContent/DrainLabel
@onready var tier_label: Label = $OuterFrame/TopBar/TopBarMargin/TopBarContent/TierLabel
@onready var objectives_scroll: ObjectivesScrollWidget = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/ObjectivesScroll
@onready var exit_button: Button = $OuterFrame/SidePanel/SidePanelMargin/SidePanelContent/ExitButton
@onready var population_counter = $PopulationCounter
@onready var _bubble_sfx_pool: Array[AudioStreamPlayer] = [$BubbleSfx1, $BubbleSfx2, $BubbleSfx3]
@onready var _fade_overlay: ColorRect = $RunEndFadeOverlay

var _kill_count: int = 0
var _kill_counts_by_type: Dictionary = {}
var _monsters: Array[Monster] = []
var _all_waves_completed: bool = false
var _run_transition_started: bool = false


func _ready() -> void:
	if not SessionState.is_run_active():
		SessionState.start_run()

	Audio.play_music("battle", Audio.MUSIC_BATTLE)
	_fade_overlay.modulate.a = 0.0
	_apply_rune_effects()
	_refresh_population_ui(SessionState.get_population_current(), SessionState.get_current_drain_per_second())

	monster_spawner.monster_spawned.connect(_on_monster_spawned)
	monster_spawner.all_waves_completed.connect(_on_all_waves_completed)
	SessionState.population_changed.connect(_refresh_population_ui)
	SessionState.objectives_changed.connect(_refresh_objectives_ui)
	exit_button.disabled = not SessionState.is_manual_exit_enabled()
	exit_button.pressed.connect(_on_exit_button_pressed)
	monster_spawner.begin_run()
	_refresh_objectives_ui()
	# DEBUG: draw monster field bounds — uncomment to visualize
	#_add_debug_bounds_rect()


func _physics_process(delta: float) -> void:
	if _run_transition_started:
		return

	var active_monster_drain_units: float = _get_active_monster_drain_units()
	if SessionState.update_population(delta, active_monster_drain_units):
		_finish_run("loss")


func add_monster(monster: Monster) -> void:
	if _monsters.has(monster):
		return

	_monsters.append(monster)
	monster.killed.connect(_on_monster_killed, CONNECT_ONE_SHOT)
	monster.expired.connect(_on_monster_expired, CONNECT_ONE_SHOT)
	monster.tree_exited.connect(_on_monster_tree_exited.bind(monster), CONNECT_ONE_SHOT)


func _apply_rune_effects() -> void:
	player_attack.attack_radius = SessionState.get_attack_radius(player_attack.attack_radius)
	player_attack.damage_per_second = SessionState.get_damage_per_second(player_attack.damage_per_second)
	player_attack.lifetime_slow_scale = SessionState.get_lifetime_slow_scale(player_attack.lifetime_slow_scale)
	player_attack.stasis_field_enabled = SessionState.is_stasis_field_enabled()
	player_attack.refresh_runtime_configuration()
	tier_label.text = "Tier %d" % SessionState.get_current_tier()


func _on_monster_spawned(monster: Monster) -> void:
	add_monster(monster)



func _on_all_waves_completed() -> void:
	_all_waves_completed = true
	_maybe_finish_run_naturally()


func _on_monster_killed(monster: Monster) -> void:
	_kill_count += 1
	_kill_counts_by_type[monster.monster_type_id] = int(_kill_counts_by_type.get(monster.monster_type_id, 0)) + 1
	SessionState.register_monster_kill(monster.monster_type_id)
	_spawn_monster_burst(monster)
	_play_bubble_sfx()
	if SessionState.are_selected_rune_objectives_complete():
		_finish_run("completed")


func _on_monster_expired(monster: Monster) -> void:
	SessionState.add_lingering_monster(monster.to_lingering_data())



func _on_monster_tree_exited(monster: Monster) -> void:
	_monsters.erase(monster)
	_maybe_finish_run_naturally()


func _maybe_finish_run_naturally() -> void:
	if _run_transition_started:
		return
	if not _all_waves_completed:
		return
	if not _monsters.is_empty():
		return

	_finish_run("natural")


func _on_exit_button_pressed() -> void:
	_finish_run("manual_exit")


func _finish_run(outcome: String) -> void:
	if _run_transition_started:
		return

	_run_transition_started = true
	player_attack.visible = false
	player_attack.set_process(false)
	player_attack.set_physics_process(false)
	exit_button.disabled = true
	if outcome == "manual_exit" or outcome == "loss":
		_capture_surviving_monsters()

	var result: Dictionary = SessionState.finish_run(outcome, _kill_count, _kill_counts_by_type)
	_play_run_end_transition()
	await get_tree().create_timer(RUN_END_MONSTER_DISAPPEAR_DURATION + RUN_END_FADE_DURATION).timeout
	get_tree().change_scene_to_file(str(result.get("next_scene_path", "res://scenes/flow/upgrades_screen.tscn")))


func _play_run_end_transition() -> void:
	for monster: Monster in _monsters:
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		monster.play_run_end_disappear(RUN_END_MONSTER_DISAPPEAR_DURATION)

	for projectile: Node in projectile_container.get_children():
		var canvas_item: CanvasItem = projectile as CanvasItem
		if canvas_item == null:
			continue
		var projectile_tween: Tween = canvas_item.create_tween()
		projectile_tween.tween_property(canvas_item, "modulate:a", 0.0, RUN_END_MONSTER_DISAPPEAR_DURATION)

	var fade_tween: Tween = create_tween()
	fade_tween.tween_interval(RUN_END_MONSTER_DISAPPEAR_DURATION)
	fade_tween.tween_property(_fade_overlay, "modulate:a", 1.0, RUN_END_FADE_DURATION)


func _capture_surviving_monsters() -> void:
	for monster: Monster in _monsters:
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		if not monster.is_alive_for_carry_over():
			continue
		SessionState.add_lingering_monster(monster.to_lingering_data())


func _refresh_population_ui(current_population: int, drain_per_second: int) -> void:
	population_counter.set_population_value(SessionState.format_population(current_population))
	drain_label.text = "Drain / sec: %s" % SessionState.format_population(drain_per_second)


func _refresh_objectives_ui() -> void:
	var objectives: Array[Dictionary] = SessionState.get_selected_objectives()
	var planned_monster_type_ids: Array[String] = monster_spawner.get_planned_monster_type_ids()
	if objectives.is_empty():
		objectives_scroll.set_objectives([], planned_monster_type_ids)
		return

	objectives_scroll.set_objectives(objectives, planned_monster_type_ids)





func _count_alive_monsters() -> int:
	var alive_count: int = 0
	for monster: Monster in _monsters:
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		if not monster.is_alive_for_carry_over():
			continue
		alive_count += 1
	return alive_count


func _get_active_monster_drain_units() -> float:
	var total_units: float = 0.0
	for monster: Monster in _monsters:
		if monster == null:
			continue
		if not is_instance_valid(monster):
			continue
		total_units += monster.get_population_drain_units()
	return total_units


func _play_bubble_sfx() -> void:
	var bubble_sounds: Array[AudioStream] = Audio.BUBBLE_SOUNDS
	for player: AudioStreamPlayer in _bubble_sfx_pool:
		if not player.playing:
			player.stream = bubble_sounds[randi() % bubble_sounds.size()]
			player.pitch_scale = randf_range(BUBBLE_PITCH_MIN, BUBBLE_PITCH_MAX)
			var base_volume_db: float = BUBBLE_VOLUME_BASE + randf_range(-BUBBLE_VOLUME_RANGE, BUBBLE_VOLUME_RANGE)
			player.volume_db = Audio.get_sfx_volume_db(base_volume_db)
			player.play()
			return


func _spawn_monster_burst(monster: Monster) -> void:
	if projectile_container == null or not is_instance_valid(projectile_container):
		return

	var projectile_count: int = SessionState.get_monster_burst_projectile_count()
	var projectile_pierces: int = SessionState.get_monster_burst_pierce_count()
	var projectile_bounces: int = SessionState.get_monster_burst_bounce_count()
	var projectile_damage: float = 28.0
	var projectile_speed: float = 390.0
	var projectile_range: float = 220.0
	var projectile_tint: Color = Color(1.0, 0.68, 0.18, 1.0)

	projectile_damage += SessionState.get_monster_burst_damage_bonus()
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

	var origin: Vector2 = source_monster.global_position
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
	if projectile_container == null or not is_instance_valid(projectile_container):
		return

	var start_position: Vector2 = origin + direction * 24.0
	var speed_variation: float = randf_range(0.92, 1.08)
	_spawn_burst_projectile_deferred.call_deferred(
		source_monster,
		start_position,
		direction,
		projectile_damage,
		projectile_speed * speed_variation,
		projectile_range,
		projectile_pierces,
		projectile_bounces,
		projectile_tint
	)


func _spawn_burst_projectile_deferred(
	source_monster: Monster,
	start_position: Vector2,
	direction: Vector2,
	projectile_damage: float,
	projectile_speed: float,
	projectile_range: float,
	projectile_pierces: int,
	projectile_bounces: int,
	projectile_tint: Color
) -> void:
	if projectile_container == null or not is_instance_valid(projectile_container):
		return

	var projectile: MonsterProjectile = MONSTER_PROJECTILE_SCENE.instantiate() as MonsterProjectile
	if projectile == null:
		return

	projectile_container.add_child(projectile)
	projectile.setup(
		start_position,
		direction,
		projectile_damage,
		projectile_speed,
		projectile_range,
		projectile_pierces,
		projectile_bounces,
		projectile_tint,
		source_monster
	)


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
		if not monster.is_alive_for_carry_over():
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


# DEBUG: visualize monster field bounds — remove before commit
func _add_debug_bounds_rect() -> void:
	var world: Node2D = $OuterFrame/PlayfieldFrame/World
	var debug_draw: Node2D = Node2D.new()
	debug_draw.name = "DebugBounds"
	debug_draw.z_index = 100
	debug_draw.set_script(preload("res://scripts/debug/debug_bounds_draw.gd"))
	world.add_child(debug_draw)
