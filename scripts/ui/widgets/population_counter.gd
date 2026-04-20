extends Control


@onready var title_label: Label = $Row/TitleLabel
@onready var value_label: Label = $Row/ValueLabel


func set_population_value(text_value: String) -> void:
	title_label.text = "Population: "
	value_label.text = text_value
