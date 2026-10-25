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


func set_grammar(grammar: TMGrammar) -> void:
	if _grammar == grammar:
		return
	_grammar = grammar
	if _grammar != null:
		_tokenizer.setup(_grammar, _tokenizer.theme)
	else:
		_tokenizer.reset()

	_clear_highlighting_cache()
	clear_highlighting_cache()
	emit_changed()


func set_theme(theme: TMTheme) -> void:
	_tokenizer.setup(_grammar, theme)
	_clear_highlighting_cache()
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

func _clear_highlighting_cache() -> void:
	_valid = 0
	_line_count = -1
	_states.clear()
	_tokens.clear()
	_hashes = PackedInt64Array()


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

	_ensure_line(text_edit, line)
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
		_tokenizer.tokenize(text, state, index == 0)
		_states.append(state.clone())
		_tokens.append(_tokenizer.tokens())
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
