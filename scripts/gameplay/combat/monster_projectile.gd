class_name MonsterProjectile
extends Area2D


@export var speed: float = 360.0
@export var damage: float = 18.0
@export var max_range: float = 240.0
@export var collision_radius: float = 6.0

@onready var trail: Line2D = $Trail
@onready var core: Polygon2D = $Core
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var direction: Vector2 = Vector2.RIGHT
var source_monster_id: int = 0
var remaining_pierces: int = 0
var remaining_bounces: int = 0
var travel_bounds_position: Vector2 = Vector2.ZERO
var travel_bounds_size: Vector2 = Vector2.ZERO
var _distance_travelled: float = 0.0
var _tint: Color = Color(1.0, 0.72, 0.2, 1.0)
var _hit_monster_ids: Dictionary = {}


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	_apply_runtime_configuration()


func _physics_process(delta: float) -> void:
	var distance_step: float = speed * delta
	global_position += direction * distance_step
	_maybe_bounce_from_bounds()
	_distance_travelled += distance_step

	if _distance_travelled >= max_range:
		queue_free()


func setup(
	start_position: Vector2,
	travel_direction: Vector2,
	projectile_damage: float,
	projectile_speed: float,
	projectile_range: float,
	projectile_pierces: int,
	projectile_bounces: int,
	tint: Color,
	source_id: int,
) -> void:
	global_position = start_position
	direction = travel_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	rotation = direction.angle()
	damage = maxf(0.0, projectile_damage)
	speed = maxf(0.0, projectile_speed)
	max_range = maxf(1.0, projectile_range)
	remaining_pierces = maxi(0, projectile_pierces)
	remaining_bounces = maxi(0, projectile_bounces)
	source_monster_id = maxi(0, source_id)
	_tint = tint
	travel_bounds_position = Globals.MONSTERS_FIELD_MIN
	travel_bounds_size = Globals.MONSTERS_FIELD_MAX - Globals.MONSTERS_FIELD_MIN
	_hit_monster_ids.clear()

	if is_node_ready():
		_apply_runtime_configuration()


func _apply_runtime_configuration() -> void:
	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle_shape != null:
		circle_shape.radius = collision_radius

	trail.default_color = _tint
	core.color = _tint.lightened(0.14)


func _on_area_entered(area: Area2D) -> void:
	var monster: Monster = area as Monster
	if monster == null:
		return

	if monster.get_instance_id() == source_monster_id:
		return

	var monster_id: int = monster.get_instance_id()
	if _hit_monster_ids.has(monster_id):
		return

	_hit_monster_ids[monster_id] = true
	monster.take_damage(damage, false, false)
	if remaining_pierces > 0:
		remaining_pierces -= 1
		return

	queue_free()


func _maybe_bounce_from_bounds() -> void:
	if remaining_bounces <= 0:
		return

	if travel_bounds_size.x <= 0.0 or travel_bounds_size.y <= 0.0:
		return

	var min_x: float = travel_bounds_position.x + collision_radius
	var max_x: float = travel_bounds_position.x + travel_bounds_size.x - collision_radius
	var min_y: float = travel_bounds_position.y + collision_radius
	var max_y: float = travel_bounds_position.y + travel_bounds_size.y - collision_radius
	var did_bounce: bool = false

	if global_position.x < min_x or global_position.x > max_x:
		direction.x *= -1.0
		global_position.x = clampf(global_position.x, min_x, max_x)
		did_bounce = true

	if global_position.y < min_y or global_position.y > max_y:
		direction.y *= -1.0
		global_position.y = clampf(global_position.y, min_y, max_y)
		did_bounce = true

	if not did_bounce:
		return

	remaining_bounces -= 1
	rotation = direction.angle()
