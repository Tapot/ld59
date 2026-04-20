class_name DrainRateWidget
extends Control


@onready var value_label: Label = $Row/ValueLabel


func set_drain_value(formatted_number: String) -> void:
	value_label.text = "%s/sec" % formatted_number
