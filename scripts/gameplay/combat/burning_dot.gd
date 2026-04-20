class_name BurningDot
extends Node2D


const CORE_COLOR: Color = Color(1.0, 0.95, 0.55, 0.75)
const MID_COLOR: Color = Color(1.0, 0.65, 0.15, 0.55)
const OUTER_COLOR: Color = Color(1.0, 0.35, 0.05, 0.32)
const HALO_COLOR: Color = Color(1.0, 0.25, 0.05, 0.14)

const CORE_RADIUS: float = 2.0
const MID_RADIUS: float = 4.0
const OUTER_RADIUS: float = 7.0
const HALO_RADIUS: float = 12.0

const INTENSITY_DECAY_PER_SEC: float = 2.8
const INTENSITY_PER_HIT: float = 0.08
const INTENSITY_PER_EXTRA_TARGET: float = 0.4
const INTENSITY_MAX: float = 3.5
const IDLE_INTENSITY: float = 0.35
const IDLE_ALPHA_MULT: float = 0.45

var _intensity: float = IDLE_INTENSITY
var _target_count: int = 0
var _embers: CPUParticles2D
var _sparks: CPUParticles2D
var _flicker_seed: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 5
	_flicker_seed = randf() * 1000.0
	_embers = _make_embers()
	add_child(_embers)
	_sparks = _make_sparks()
	add_child(_sparks)


func _process(delta: float) -> void:
	_intensity = maxf(IDLE_INTENSITY, _intensity - INTENSITY_DECAY_PER_SEC * delta)
	var rate_mult: float = clampf(_intensity / IDLE_INTENSITY, 0.5, 6.0)
	_embers.emitting = true
	_embers.amount = clampi(int(round(6.0 * rate_mult)), 3, 64)
	var ember_speed_mult: float = 1.0 + 0.6 * float(_target_count)
	_embers.initial_velocity_min = 10.0 * ember_speed_mult
	_embers.initial_velocity_max = 26.0 * ember_speed_mult
	queue_redraw()


func pulse_from_hit(target_count: int = 1) -> void:
	_target_count = max(_target_count, target_count)
	var bonus: float = INTENSITY_PER_HIT + INTENSITY_PER_EXTRA_TARGET * float(max(0, target_count - 1))
	_intensity = minf(INTENSITY_MAX, _intensity + bonus)
	if _sparks != null:
		_sparks.amount = clampi(8 + target_count * 6, 8, 80)
		_sparks.initial_velocity_min = 80.0 + 25.0 * float(target_count)
		_sparks.initial_velocity_max = 150.0 + 40.0 * float(target_count)
		_sparks.restart()
		_sparks.emitting = true


func clear_targets() -> void:
	_target_count = 0


func _draw() -> void:
	var t: float = float(Time.get_ticks_msec()) * 0.001 + _flicker_seed
	var flicker: float = 0.85 + 0.15 * sin(t * 18.0) + 0.05 * sin(t * 33.0 + 1.3)
	var first_target_bonus: float = 0.15 if _target_count >= 1 else 0.0
	var extra_target_bonus: float = 0.4 * float(max(0, _target_count - 1))
	var size_bonus: float = 1.0 + first_target_bonus + extra_target_bonus
	var scale_f: float = clampf(_intensity, 0.4, 3.0) * flicker * size_bonus
	var alpha_mult: float = clampf(_intensity * 0.6, IDLE_ALPHA_MULT, 1.0)

	_draw_soft_circle(HALO_RADIUS * scale_f, HALO_COLOR, alpha_mult, 5)
	_draw_soft_circle(OUTER_RADIUS * scale_f, OUTER_COLOR, alpha_mult, 4)
	_draw_soft_circle(MID_RADIUS * scale_f, MID_COLOR, alpha_mult, 3)
	draw_circle(Vector2.ZERO, CORE_RADIUS * scale_f, Color(CORE_COLOR.r, CORE_COLOR.g, CORE_COLOR.b, CORE_COLOR.a * alpha_mult))


func _draw_soft_circle(radius: float, base: Color, alpha_mult: float, steps: int) -> void:
	for i: int in steps:
		var k: float = float(i) / float(steps - 1) if steps > 1 else 0.0
		var r: float = lerpf(radius * 0.35, radius, k)
		var a: float = base.a * alpha_mult * (1.0 - k) * 0.9 + 0.05
		draw_circle(Vector2.ZERO, r, Color(base.r, base.g, base.b, a))


func _make_embers() -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 0.55
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = Vector2(0, -1)
	p.spread = 35.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 28.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = Color(1.0, 0.7, 0.2, 1.0)
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.45, 0.1, 0.7), Color(0.3, 0.05, 0.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = grad
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.z_index = 4
	return p


func _make_sparks() -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 14
	p.lifetime = 0.35
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.damping_min = 120.0
	p.damping_max = 180.0
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 0.7, 1.0), Color(1.0, 0.55, 0.1, 0.9), Color(0.8, 0.15, 0.05, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	p.color_ramp = grad
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.z_index = 6
	return p
