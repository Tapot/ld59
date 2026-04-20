class_name BurnGround
extends Node2D


const MERGE_RADIUS: float = 12.0
const INTENSITY_PER_DAMAGE: float = 0.008
const SEED_INTENSITY: float = 0.18
const INTENSITY_MAX: float = 1.2
const INTENSITY_DECAY_PER_SEC: float = 0.28
const MIN_VISIBLE_INTENSITY: float = 0.04
const MAX_SCORCH_COUNT: int = 220
const BASE_RADIUS: float = 4.0
const RADIUS_PER_INTENSITY: float = 8.0
const SCORCH_COLOR: Color = Color(0.08, 0.04, 0.02, 1.0)
const EDGE_COLOR: Color = Color(0.35, 0.12, 0.02, 1.0)
const EMBER_HOT: Color = Color(1.0, 0.55, 0.15, 1.0)
const EMBER_BRIGHT: Color = Color(1.0, 0.9, 0.4, 1.0)
# Ember glow fades out faster than the dark scorch, so spots "cool" over time.
const EMBER_ALPHA_THRESHOLD: float = 0.35


class Scorch:
	var position: Vector2
	var intensity: float = 0.0

	func _init(p: Vector2, i: float) -> void:
		position = p
		intensity = i


var _scorches: Array[Scorch] = []


func _ready() -> void:
	z_as_relative = true
	z_index = 0


func _process(delta: float) -> void:
	var dirty: bool = false
	var i: int = _scorches.size() - 1
	while i >= 0:
		var s: Scorch = _scorches[i]
		s.intensity -= INTENSITY_DECAY_PER_SEC * delta
		if s.intensity <= MIN_VISIBLE_INTENSITY:
			_scorches.remove_at(i)
			dirty = true
		else:
			dirty = true
		i -= 1
	if dirty:
		queue_redraw()


func record_damage(world_position: Vector2, damage_amount: float) -> void:
	if damage_amount <= 0.0:
		return
	var local_pos: Vector2 = to_local(world_position)
	var add_intensity: float = damage_amount * INTENSITY_PER_DAMAGE
	for s: Scorch in _scorches:
		if s.position.distance_squared_to(local_pos) <= MERGE_RADIUS * MERGE_RADIUS:
			s.intensity = minf(INTENSITY_MAX, s.intensity + add_intensity)
			s.position = s.position.lerp(local_pos, 0.15)
			queue_redraw()
			return
	if _scorches.size() >= MAX_SCORCH_COUNT:
		var weakest_index: int = 0
		var weakest_intensity: float = _scorches[0].intensity
		for j: int in range(1, _scorches.size()):
			if _scorches[j].intensity < weakest_intensity:
				weakest_intensity = _scorches[j].intensity
				weakest_index = j
		_scorches.remove_at(weakest_index)
	_scorches.append(Scorch.new(local_pos, maxf(add_intensity, SEED_INTENSITY)))
	queue_redraw()


func clear() -> void:
	_scorches.clear()
	queue_redraw()


func _draw() -> void:
	for s: Scorch in _scorches:
		var t: float = clampf(s.intensity / INTENSITY_MAX, 0.0, 1.0)
		var radius: float = BASE_RADIUS + RADIUS_PER_INTENSITY * t
		var alpha: float = clampf(s.intensity, 0.0, 1.0)
		var edge: Color = Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, 0.28 * alpha)
		draw_circle(s.position, radius * 1.15, edge)
		var core: Color = Color(SCORCH_COLOR.r, SCORCH_COLOR.g, SCORCH_COLOR.b, 0.65 * alpha)
		draw_circle(s.position, radius, core)
		if s.intensity > EMBER_ALPHA_THRESHOLD:
			var ember_t: float = clampf((s.intensity - EMBER_ALPHA_THRESHOLD) / (INTENSITY_MAX - EMBER_ALPHA_THRESHOLD), 0.0, 1.0)
			var ember_outer: Color = Color(EMBER_HOT.r, EMBER_HOT.g, EMBER_HOT.b, 0.4 * ember_t)
			draw_circle(s.position, radius * 0.85, ember_outer)
			var ember_inner: Color = Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, 0.65 * ember_t)
			draw_circle(s.position, radius * 0.45, ember_inner)
