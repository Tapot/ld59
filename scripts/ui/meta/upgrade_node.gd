extends Button


signal purchase_requested(upgrade_id: String)


const NORMAL_PROGRESS_COLOR: Color = Color(0.24, 0.62, 1.0, 1.0)
const MAXED_PROGRESS_COLOR: Color = Color(0.28, 0.86, 0.42, 1.0)

@onready var icon_rect: TextureRect = $ContentMargin/Content/TopRow/IconRect
@onready var title_label: Label = $ContentMargin/Content/TopRow/TitleLabel
@onready var afford_dot: ColorRect = $ContentMargin/Content/TopRow/AffordDot
@onready var progress_bar: ProgressBar = $ContentMargin/Content/ProgressBar
@onready var level_price_label: Label = $ContentMargin/Content/LevelPriceLabel

var _upgrade_id: String = ""
var _is_actionable: bool = false


func _ready() -> void:
	pressed.connect(_on_pressed)


func configure(definition: Dictionary, current_level: int) -> void:
	_upgrade_id = str(definition.get("id", ""))
	var max_level: int = maxi(1, int(definition.get("max_level", 1)))
	var is_maxed: bool = current_level >= max_level
	var can_purchase: bool = SessionState.can_purchase_upgrade(_upgrade_id)
	var next_cost: int = SessionState.get_upgrade_next_cost(_upgrade_id)
	var icon_path: String = str(definition.get("icon", ""))
	var icon_texture: Texture2D = load(icon_path) as Texture2D

	text = ""
	tooltip_text = str(definition.get("description", ""))
	title_label.text = str(definition.get("title", _upgrade_id))
	icon_rect.texture = icon_texture
	progress_bar.max_value = float(max_level)
	progress_bar.value = float(current_level)
	progress_bar.modulate = MAXED_PROGRESS_COLOR if is_maxed else NORMAL_PROGRESS_COLOR

	if is_maxed:
		level_price_label.text = "%d/%d" % [current_level, max_level]
	else:
		level_price_label.text = "%d/%d - %d" % [current_level, max_level, next_cost]

	_is_actionable = can_purchase and not is_maxed
	afford_dot.visible = _is_actionable
	disabled = not _is_actionable


func _on_pressed() -> void:
	if not _is_actionable:
		return

	purchase_requested.emit(_upgrade_id)
