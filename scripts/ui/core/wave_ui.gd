class_name WaveUI
extends VBoxContainer


@onready var progress_bar: ProgressBar = $WaveTrackRow/WaveProgressTrack/ProgressBar


func set_progress(value: float, max_value: float) -> void:
	var safe_max_value: float = max(max_value, 0.000001)
	progress_bar.max_value = safe_max_value
	progress_bar.value = clamp(value, 0.0, safe_max_value)
