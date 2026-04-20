class_name ObjectiveTask
extends PanelContainer


const ICON_SIZE: Vector2 = Vector2(36.0, 36.0)

@onready var task_description_label: Label = $CardMargin/Content/TaskDescriptionLabel
@onready var targets_row: HBoxContainer = $CardMargin/Content/TargetsRow
@onready var progress_bar: ProgressBar = $CardMargin/Content/ProgressBar
@onready var progress_label: Label = $CardMargin/Content/ProgressLabel


func configure(objective: Dictionary, planned_monster_type_ids: Array[String]) -> void:
	task_description_label.text = str(objective.get("task_description", ""))
	_rebuild_target_icons(objective, planned_monster_type_ids)

	var target_value: int = maxi(0, int(objective.get("target", 0)))
	var current_value: int = maxi(0, int(objective.get("current", 0)))
	var clamped_value: int = mini(target_value, current_value)
	progress_bar.max_value = float(maxi(1, target_value))
	progress_bar.value = float(clamped_value)
	progress_bar.show_percentage = false
	progress_label.text = "%d / %d" % [clamped_value, target_value]
	progress_bar.modulate = Color(0.36, 0.88, 0.54, 1.0) if bool(objective.get("complete", false)) else Color(1.0, 1.0, 1.0, 1.0)


func _rebuild_target_icons(objective: Dictionary, planned_monster_type_ids: Array[String]) -> void:
	for child: Node in targets_row.get_children():
		child.queue_free()

	var monster_type_ids: Array[String] = _get_target_monster_type_ids(objective, planned_monster_type_ids)
	for monster_type_id: String in monster_type_ids:
		var icon_rect: TextureRect = TextureRect.new()
		var texture_path: String = SessionState.get_monster_sprite_path(monster_type_id)
		var texture: Texture2D = null
		if not texture_path.is_empty():
			texture = load(texture_path) as Texture2D

		icon_rect.custom_minimum_size = ICON_SIZE
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = texture
		icon_rect.tooltip_text = SessionState.get_monster_title(monster_type_id)
		targets_row.add_child(icon_rect)


func _get_target_monster_type_ids(objective: Dictionary, planned_monster_type_ids: Array[String]) -> Array[String]:
	var objective_type: String = str(objective.get("monster_type", ""))
	if objective_type != "any":
		if objective_type.is_empty():
			return []
		return [objective_type]

	return planned_monster_type_ids.duplicate()
