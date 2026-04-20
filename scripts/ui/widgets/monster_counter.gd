class_name MonsterCounter
extends Control


@onready var title_label: Label = $Row/TitleLabel
@onready var value_label: Label = $Row/ValueLabel


func set_monster_count(count: int) -> void:
	value_label.text = str(count)
