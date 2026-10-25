# Info:
# "Caret" refers to the "cursor" of where text is being inserted/deleted in the CodeEdit node.
#
# The camera is a damped follower.  Pages never animate the camera directly:
# they only set a target (caret + zoom for the editor, a framed position for
# overlays) and the same smoothing runs for both, so switching between the
# editor and the file picker keeps one consistent motion.
class_name Camera
extends Camera2D

## Time constant of the follow, in seconds.  Derived from follow_amount.
var transition_speed := 0.3

## 0 = floaty, 1 = snaps to the caret.
var follow_amount := 0.7:
	set(value):
		follow_amount = clampf(value, 0.0, 1.0)
		transition_speed = lerpf(0.9, 0.02, follow_amount)

## Master switch: framing still happens, but without easing or breathing.
var motion_enabled := true
## Music beats bump the zoom.
var music_pulse_enabled := true

@onready var code = %Code

var max_zoom = Vector2(10.0, 10.0);
var min_zoom = Vector2(1.0, 1.0);

## An overlay (file picker, settings, comments...) owns the target.
var manual = false;
## Kept for compatibility with older call sites.
var busy = false;
var boundaries_exceeded = null;

var shake_strength: float = 15.0;

var d := 0.0;
var sway_radius := 4.0;
var sway_speed := 2.0;

var target_position := Vector2.ZERO;
var target_zoom := Vector2.ONE;

var _pulse := 0.0;
var _longest_chars := 0;

const SCALE = 7.0;


func _ready() -> void:
	limit_right = code.size.x
	target_position = global_position
	target_zoom = zoom
	_longest_chars = code.get_longest_line().length()
	code.text_changed.connect(_on_code_text_changed)
	code.text_set.connect(_on_code_text_changed)


func _on_code_text_changed() -> void:
	_longest_chars = code.get_longest_line().length()


func get_font_metrics() -> Vector2:
	var font: Font = code.get_theme_default_font()
	var font_size: int = code.get_theme_font_size("font", "CodeEdit")
	# NOTE: imo this is a good approximation of the average character size for a non
	# monospaced font.
	return font.get_char_size(0x30, font_size)


func _process(delta: float) -> void:
	d += delta;

	if motion_enabled:
		offset = Vector2(
			sin(d * sway_speed) * sway_radius,
			cos(d * sway_speed) * sway_radius
		)
		_pulse = lerpf(_pulse, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	else:
		offset = Vector2.ZERO
		_pulse = 0.0

	if not manual:
		var zoom_level: float = max_zoom.x - (float(_longest_chars) + 1.0) / SCALE
		zoom_level = clampf(zoom_level, min_zoom.x, max_zoom.x)
		target_zoom = Vector2(zoom_level, zoom_level)

		var char_size: Vector2 = get_font_metrics()
		var caret: Vector2 = code.get_caret_draw_pos()
		caret.x -= 2.0 * char_size.x
		target_position = caret

	if not motion_enabled:
		global_position = target_position
		zoom = target_zoom
		return

	var t := 1.0 - exp(-delta / maxf(transition_speed, 0.01))
	global_position = global_position.lerp(target_position, t)
	zoom = zoom.lerp(target_zoom + Vector2(_pulse, _pulse), t).clamp(min_zoom, max_zoom)


## Frame `pos` at `_zoom`; used by overlays and by the file picker while scrolling.
func focus_on(pos: Vector2, _zoom: Vector2) -> void:
	manual = true
	busy = true
	target_position = pos
	target_zoom = _zoom


## Hand the camera back to the caret.
func focus_die() -> void:
	manual = false
	busy = false


## Music beat bump; works on every page now, not only in the editor.
func focus_temp(intensity: float) -> void:
	if not motion_enabled or not music_pulse_enabled:
		return
	_pulse += intensity


func shake_camera(_shake_strength):
	return Vector2(randf_range(-_shake_strength, _shake_strength), randf_range(-_shake_strength, _shake_strength))


func to_zoom(num: float) -> Vector2:
	if num > 40:
		num += 120;

	num /= 100 # 44 -> 0.44

	num = 4 - num;

	return Vector2(num, num)
