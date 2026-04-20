extends Control


@onready var value_label: Label = $Row/ValueLabel
@onready var progress_fill: Panel = $BgPanel/ProgressFill

var _progress_ratio: float = 1.0


func _ready() -> void:
	_apply_progress()


func set_population_value(text_value: String) -> void:
	value_label.text = text_value


func set_progress(ratio: float) -> void:
	_progress_ratio = clampf(ratio, 0.0, 1.0)
	_apply_progress()


func _apply_progress() -> void:
	if progress_fill == null:
		return
	progress_fill.anchor_right = _progress_ratio
