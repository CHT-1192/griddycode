class_name TMHighlighter
extends SyntaxHighlighter

## Godot facing part of the engine: answers `_get_line_syntax_highlighting`
## with a {column: {"color": Color}} map produced by TMTokenizer.
##
## Lines are tokenized forward from the last valid state and cached, so asking
## for line N only costs the work between the last cached line and N.  Edits are
## picked up from TextEdit's `lines_edited_from` signal.

var _grammar: TMGrammar = null
var _tokenizer := TMTokenizer.new()
var _fallback := TMFallback.new()

var _states: Array = []
var _tokens: Array = []
var _hashes := PackedInt64Array()
var _valid := 0
var _line_count := -1
var _connected := false

## Long files are tokenized in the background: on the first paint Godot asks
## for every line of the control, and a C++ file costs a few milliseconds per
## line.  Small jumps stay synchronous so editing feels instant.
const SYNC_LINES := 120
const WARM_BUDGET_MS := 16
const WARM_REFRESH_EVERY := 400

var _warm_scheduled := false
var _last_refresh_valid := 0
var _frame := -1
var _frame_ms := 0
var _warm_gen := 0


func set_grammar(grammar: TMGrammar) -> void:
	if _grammar == grammar:
		return
	_grammar = grammar
	if _grammar != null:
		_tokenizer.setup(_grammar, _tokenizer.theme)
	else:
		_tokenizer.reset()

	_reset_all()
	clear_highlighting_cache()
	emit_changed()


func set_theme(theme: TMTheme) -> void:
	_tokenizer.setup(_grammar, theme)
	_reset_all()
	clear_highlighting_cache()
	emit_changed()


func configure_fallback(categories: Dictionary, keyword_to_category: Dictionary, regions: Array, default_color: Color) -> void:
	_fallback.setup(categories, keyword_to_category, regions, default_color)


func invalidate_from(line: int) -> void:
	line = maxi(line, 0)
	if line >= _valid:
		return
	_valid = line
	_truncate_to(line)


# --------------------------------------------------------------------------
# SyntaxHighlighter
# --------------------------------------------------------------------------

## Called by Godot whenever its own per-line cache is dropped.  Our data stays
## valid across those, so this must not reset anything: `_reset_all()` is used
## explicitly when the grammar, theme or document changes.
func _clear_highlighting_cache() -> void:
	pass


func _reset_all() -> void:
	_valid = 0
	_line_count = -1
	_last_refresh_valid = 0
	_warm_scheduled = false
	_warm_gen += 1
	_states.clear()
	_tokens.clear()
	_hashes = PackedInt64Array()
	_frame = -1
	_frame_ms = 0


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var text_edit := get_text_edit()
	if text_edit == null:
		return {}

	_ensure_connected(text_edit)

	if line < 0 or line >= text_edit.get_line_count():
		return {}

	if _grammar == null:
		return _unpack(_fallback.tokenize(text_edit.get_line(line)))

	if text_edit.get_line_count() != _line_count:
		# Lines were inserted or removed: everything before the caret is still
		# valid, so only drop the cache from there instead of starting over.
		_line_count = text_edit.get_line_count()
		invalidate_from(mini(line, text_edit.get_caret_line()))
		if _valid > _line_count:
			_valid = _line_count
			_truncate_to(_valid)

	var text := _line_text(text_edit, line)
	if line < _valid and line < _hashes.size() and _hashes[line] == text.hash():
		return _unpack(_tokens[line])

	# The first paint asks for every line of the document, which is far too
	# much work for one frame; once the per-frame budget is spent the rest of
	# the file is filled in by the deferred warmup pass.
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_frame_ms = 0

	if _warm_scheduled or line - _valid > SYNC_LINES:
		_schedule_warmup()
		return {}

	if _frame_ms > WARM_BUDGET_MS:
		_schedule_warmup()
		return {}

	var started := Time.get_ticks_msec()
	_ensure_line(text_edit, line)
	_frame_ms += Time.get_ticks_msec() - started

	if line < _tokens.size():
		return _unpack(_tokens[line])
	return {}


# --------------------------------------------------------------------------
# Incremental tokenization
# --------------------------------------------------------------------------

func _ensure_connected(text_edit: TextEdit) -> void:
	if _connected:
		return
	_connected = true
	# Signals are dropped automatically when the highlighter is freed, so no
	# explicit disconnect is needed (and doing it in NOTIFICATION_PREDELETE is
	# not legal: creating the Callable touches the dying object).
	if text_edit.has_signal("lines_edited_from"):
		text_edit.lines_edited_from.connect(_on_lines_edited)


func _on_lines_edited(from_line: int, to_line: int) -> void:
	invalidate_from(mini(from_line, to_line))


func _schedule_warmup() -> void:
	if _warm_scheduled or _grammar == null:
		return
	_warm_scheduled = true
	_last_refresh_valid = _valid
	_warm_loop(_warm_gen)


## Drops the per-line dictionaries cached inside Godot's SyntaxHighlighter and
## asks TextEdit to rebuild its own cache, so lines that were painted plain
## while warming up get recomputed.
func _refresh_lines() -> void:
	clear_highlighting_cache()
	emit_changed()


## Fills the rest of the document a few milliseconds at a time.  The loop is
## async on purpose: `call_deferred` chains are flushed inside a single frame,
## which would reintroduce the freeze this is meant to avoid.
func _warm_loop(generation: int) -> void:
	while generation == _warm_gen:
		var text_edit := get_text_edit()
		if text_edit == null or _grammar == null:
			return

		var line_count := text_edit.get_line_count()
		if _valid >= line_count:
			break

		var state: TMState = _states[_valid - 1].clone() if _valid > 0 and _valid <= _states.size() else TMState.new()
		var started := Time.get_ticks_msec()

		while _valid < line_count:
			var text := _line_text(text_edit, _valid)
			_tokenizer.tokenize(text + "\n", state, _valid == 0)
			_states.append(state.clone())
			_tokens.append(_trim_trailing_newline(_tokenizer.tokens(), text.length()))
			_hashes.append(text.hash())
			_valid += 1

			if Time.get_ticks_msec() - started > WARM_BUDGET_MS:
				break

		if _valid - _last_refresh_valid >= WARM_REFRESH_EVERY:
			_last_refresh_valid = _valid
			_refresh_lines()

		var tree := text_edit.get_tree()
		if tree == null:
			return
		await tree.process_frame

	if generation != _warm_gen:
		return

	_warm_scheduled = false
	_refresh_lines()


func _ensure_line(text_edit: TextEdit, line: int) -> void:
	var base := mini(_valid, line)
	if base < _valid:
		_valid = base
		_truncate_to(base)

	var state: TMState
	if _valid > 0 and _valid <= _states.size():
		state = _states[_valid - 1].clone()
	else:
		state = TMState.new()

	var index := _valid
	while index <= line:
		var text := _line_text(text_edit, index)
		# TextMate tokenizes a line together with its trailing newline; several
		# grammars end their line rules with `\n` or `(?=\n)` and would leave a
		# frame open forever without it.
		_tokenizer.tokenize(text + "\n", state, index == 0)
		_states.append(state.clone())
		_tokens.append(_trim_trailing_newline(_tokenizer.tokens(), text.length()))
		_hashes.append(text.hash())
		index += 1

	_valid = index


func _truncate_to(count: int) -> void:
	if _states.size() > count:
		_states.resize(count)
	if _tokens.size() > count:
		_tokens.resize(count)
	if _hashes.size() > count:
		_hashes.resize(count)


## Tokens for the virtual newline are dropped: Godot columns stop at the end
## of the line.
func _trim_trailing_newline(packed: PackedInt32Array, line_length: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var index := 0
	while index + 1 < packed.size():
		if packed[index] >= line_length:
			break
		out.append(packed[index])
		out.append(packed[index + 1])
		index += 2
	return out


func _line_text(text_edit: TextEdit, line: int) -> String:
	var text := text_edit.get_line(line)
	if text.ends_with("\r"):
		text = text.substr(0, text.length() - 1)
	return text


func _unpack(packed: PackedInt32Array) -> Dictionary:
	var result := {}
	var index := 0
	while index + 1 < packed.size():
		var column := packed[index]
		var value := packed[index + 1]
		result[column] = {
			"color": Color8((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF),
		}
		index += 2
	return result
