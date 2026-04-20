extends Control


@onready var value_label: Label = $Row/ValueLabel


func set_population_value(text_value: String) -> void:
	value_label.text = text_value
