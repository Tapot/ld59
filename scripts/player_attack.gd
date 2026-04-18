class_name PlayerAttack
extends Area2D


@export var damage_per_second: float = 100.0

var _targeted_monsters: Array[Monster] = []


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()


func _physics_process(delta: float) -> void:
	var damage_amount: float = damage_per_second * delta
	var monsters_to_damage: Array[Monster] = _targeted_monsters.duplicate()
	for monster: Monster in monsters_to_damage:
		if not is_instance_valid(monster):
			continue

		monster.take_damage(damage_amount)


func _on_area_entered(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	if _targeted_monsters.has(monster):
		return

	_targeted_monsters.append(monster)
	monster.push_lifetime_pause()
	var tree_exited_callable: Callable = _on_monster_tree_exited.bind(monster)
	if not monster.tree_exited.is_connected(tree_exited_callable):
		monster.tree_exited.connect(tree_exited_callable, CONNECT_ONE_SHOT)


func _on_area_exited(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	_release_monster(monster)


func _on_monster_tree_exited(monster: Monster) -> void:
	_targeted_monsters.erase(monster)


func _release_monster(monster: Monster) -> void:
	if not _targeted_monsters.has(monster):
		return

	_targeted_monsters.erase(monster)
	if is_instance_valid(monster):
		monster.pop_lifetime_pause()
