class_name ObjectivesScrollWidget
extends ScrollContainer


const OBJECTIVE_TASK_SCENE: PackedScene = preload("res://scenes/ui/widgets/objective_task.tscn")

@onready var objectives_list: VBoxContainer = $ObjectivesList


func set_objectives(objectives: Array[Dictionary], planned_monster_type_ids: Array[String]) -> void:
	for child: Node in objectives_list.get_children():
		child.queue_free()

	for objective: Dictionary in objectives:
		var objective_task: ObjectiveTask = OBJECTIVE_TASK_SCENE.instantiate() as ObjectiveTask
		if objective_task == null:
			continue
		objectives_list.add_child(objective_task)
		objective_task.configure(objective, planned_monster_type_ids)
