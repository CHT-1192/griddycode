extends VBoxContainer

## The settings page lives in world space like the editor and the file picker:
## one setting per "line", the selected line is highlighted and the camera flies
## to it.  No scroll container, no clipping.

const SETTING = preload("res://Scenes/setting.tscn")
const UPDATE = preload("res://Scenes/update.tscn")

## World units between two lines; matches the VBox separation.
const ROW_SPACING := 30.0
## How far the camera zooms in while settings are open.
const CAMERA_ZOOM := Vector2(2.2, 2.2)
## Horizontal offset from the list origin to the middle of a row.
const CAMERA_X_OFFSET := 230.0
## How many lines PageUp/PageDown jump.
const PAGE := 8

var selected_index := 0
var rows: Array = []
var active := false


func _ready():
	await LuaSingleton.on_theme_load

	setup_settings()

	LuaSingleton.on_settings_change.connect(setup_settings)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	active = is_visible_in_tree()
	if active:
		select(selected_index)


func setup_settings() -> void:
	rows.clear()

	for child in get_children():
		child.queue_free()

	for setting in LuaSingleton.settings:
		var unit = setting.unit if setting.has("unit") else "";
		var _min = setting.min if setting.has("min") else 0;
		var _max = setting.max if setting.has("max") else 0;
		var precision = setting.precision if setting.has("precision") else false;
		var step = setting.step if setting.has("step") else 0.0;

		var row := create_setting(setting.display, setting.icon, setting.value, setting.options, setting.property, unit, _min, _max, precision, step)
		rows.append(row)

	var child = UPDATE.instantiate()

	add_child(child)

	selected_index = clampi(selected_index, 0, maxi(rows.size() - 1, 0))
	_apply_highlight()

	if active:
		select(selected_index)


func create_setting(text: String, icon: String, value: Variant, options: Array, property: String, unit: String, _min: float, _max: float, precision: bool, step: float = 0.0) -> Node:
	var node = SETTING.instantiate()

	add_child(node)

	var label: RichTextLabel = node.get_node("Control/RichTextLabel");

	var slider: HSlider = node.get_node("Control2/HSlider")
	var checkbutton: CheckButton = node.get_node("Control2/CheckButton");
	var value_label: RichTextLabel = node.get_node("Control4/Value");
	var dropdown: OptionButton = node.get_node("Control5/OptionButton");

	label.add_theme_color_override("default_color", LuaSingleton.gui.font_color);
	value_label.add_theme_color_override("default_color", LuaSingleton.gui.font_color);

	label.clear()

	label.push_color(LuaSingleton.keywords.values().pick_random())
	label.add_text(icon)
	label.pop()

	label.add_text("  %s" % text)

	if !precision:
		slider.step = 1
	elif step > 0.0:
		slider.step = step

	slider.max_value = _max
	slider.min_value = _min

	checkbutton.hide()
	slider.hide()
	dropdown.hide()
	value_label.hide()

	if typeof(value) == Variant.Type.TYPE_BOOL:
		checkbutton.show()

		checkbutton.button_pressed = value;
	elif options.size() != 0:
		dropdown.show()

		for option in options:
			dropdown.add_item(option.display)

		dropdown.selected = value;
	else:
		value_label.show()

		set_label(value_label, unit, value)

		slider.show()
		slider.value = value

	slider.value_changed.connect(_slider_value_change.bind(property, value_label, unit))
	checkbutton.toggled.connect(_check_button_change.bind(property))
	dropdown.item_selected.connect(_dropdown_change.bind(property))

	return node


# --------------------------------------------------------------------------
# Selection / camera
# --------------------------------------------------------------------------

func select(index: int) -> void:
	if rows.is_empty():
		return

	selected_index = clampi(index, 0, rows.size() - 1)
	_apply_highlight()

	if not is_visible_in_tree():
		return

	var camera := get_node_or_null("/root/Editor/Misc/Cam")
	if camera == null:
		return

	var first_y := global_position.y
	var last_y := global_position.y + maxi(rows.size() - 1, 0) * ROW_SPACING
	var row_y := global_position.y + selected_index * ROW_SPACING

	# Keep the list framed: near the ends the camera stops instead of showing
	# empty space above the first line / below the last one.
	var half_view := 0.5 * float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)) / CAMERA_ZOOM.y
	var target_y := row_y
	if last_y - first_y > half_view * 2.0:
		target_y = clampf(row_y, first_y + half_view - ROW_SPACING, last_y - half_view + ROW_SPACING)
	else:
		target_y = (first_y + last_y) * 0.5

	camera.focus_on(Vector2(global_position.x + CAMERA_X_OFFSET, target_y), CAMERA_ZOOM)


func _apply_highlight() -> void:
	for i in rows.size():
		var row: Control = rows[i]
		row.modulate = Color(1, 1, 1, 1) if i == selected_index else Color(0.55, 0.55, 0.6, 1)


func _input(event: InputEvent) -> void:
	if not active:
		return

	var handled := true

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				select(selected_index - 1)
			KEY_DOWN:
				select(selected_index + 1)
			KEY_PAGEUP:
				select(selected_index - PAGE)
			KEY_PAGEDOWN:
				select(selected_index + PAGE)
			_:
				handled = false
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				select(selected_index - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				select(selected_index + 1)
			MOUSE_BUTTON_LEFT:
				# Select the clicked line but let the click reach the slider or
				# toggle under the cursor.
				var local := get_global_mouse_position() - global_position
				select(int(local.y / ROW_SPACING))
				handled = false
			_:
				handled = false
	else:
		handled = false

	if handled:
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Row callbacks
# --------------------------------------------------------------------------

func set_label(value_label: RichTextLabel, unit: String, value: float) -> void:
	value_label.clear()

	value_label.add_text(str(value) + " ")

	value_label.push_color(LuaSingleton.gui.selection_color)
	value_label.add_text(unit)
	value_label.pop()


func _slider_value_change(value: float, property: String, value_label: RichTextLabel, unit: String) -> void:
	LuaSingleton.change_setting(property, value)

	set_label(value_label, unit, value)


func _check_button_change(toggled_on: bool, property: String) -> void:
	LuaSingleton.change_setting(property, toggled_on)


func _dropdown_change(index: int, property: String):
	LuaSingleton.change_setting(property, index)
