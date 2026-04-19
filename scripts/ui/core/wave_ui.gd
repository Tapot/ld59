class_name WaveUI
extends VBoxContainer


@onready var progress_bar: ProgressBar = $WaveTrackRow/WaveProgressTrack/ProgressBar


func set_progress(value: float, max_value: float) -> void:
	progress_bar.value = value * progress_bar.max_value / max_value
