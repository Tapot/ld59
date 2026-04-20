extends PanelContainer


@onready var volume_slider: HSlider = $Margin/Content/VolumeSlider
@onready var volume_value_label: Label = $Margin/Content/ValueLabel

var _syncing_from_audio: bool = false


func _ready() -> void:
	volume_slider.value_changed.connect(_on_volume_slider_value_changed)
	Audio.common_volume_changed.connect(_on_common_volume_changed)
	_refresh_from_audio()


func _refresh_from_audio() -> void:
	_syncing_from_audio = true
	volume_slider.value = roundi(Audio.get_common_volume_linear() * 100.0)
	_syncing_from_audio = false
	volume_value_label.text = _format_percentage_label(volume_slider.value)


func _format_percentage_label(value: float) -> String:
	if value <= 0.0:
		return "Mute"

	return "%d%%" % int(round(value))


func _on_volume_slider_value_changed(value: float) -> void:
	if _syncing_from_audio:
		return

	Audio.set_common_volume_linear(value / 100.0)
	volume_value_label.text = _format_percentage_label(value)


func _on_common_volume_changed(_value: float) -> void:
	_refresh_from_audio()
