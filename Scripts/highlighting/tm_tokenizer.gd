class_name TMTokenizer
extends RefCounted

## Turns one line of text into colored ranges using the TextMate state stack.
##
## The tokenizer is the only class that knows about grammar semantics; regular
## expression work is delegated to a TMScannerBackend.

const MAX_ALTERNATIVES := 400
const MAX_STACK_DEPTH := 200

var grammar: TMGrammar = null
var theme: TMTheme = null
var debug := false

var _pcre2 := TMScannerPCRE2.new()
var _sequential := TMScannerSequential.new()

var _compiled: Dictionary = {}
var _single_regex: Dictionary = {}
var _scope_cache: Dictionary = {}
var _next_scope_id := 0
var _root_scope: TMState.ScopeNode = null

var _line := ""
var _out := PackedInt32Array()
var _has_last := false
var _last_color := Color.WHITE


class Compiled:
	var backend: TMScannerBackend = null
	var handle: Variant = null
	## Aligned with the alternatives: {"rule": TMRule, "end": bool}
	var entries: Array = []


func setup(p_grammar: TMGrammar, p_theme: TMTheme) -> void:
	grammar = p_grammar
	theme = p_theme
	debug = OS.get_environment("TM_DEBUG") == "1"
	reset()


func reset() -> void:
	_compiled.clear()
	_single_regex.clear()
	_scope_cache.clear()
	_next_scope_id = 0
	_root_scope = null


## Tokenizes `line`, mutating `state` in place.  Read the result with tokens().
func tokenize(line: String, state: TMState, is_first_line: bool = false) -> void:
	_line = line
	_out = PackedInt32Array()
	_has_last = false

	if grammar == null or not grammar.is_valid():
		return

	if _root_scope == null:
		_root_scope = _scope_node(null, grammar.scope_name)

	var length := line.length()
	var pos := 0
	var zero_width := 0
	var anchor := state.anchor

	while pos < length:
		var frame := state.top()

		if pos == 0 and frame != null and frame.rule != null and frame.rule.is_while():
			if not _matches_while(frame.rule.while_pattern, line):
				state.pop()
				anchor = frame.prev_anchor
				continue

		if frame == null and not state.is_empty():
			state.frames.clear()
			frame = null

		var allow_g := pos == anchor
		var compiled := _compiled_for(state, allow_g, is_first_line)
		if compiled == null:
			_emit(pos, length, _current_scope(state))
			break

		var hit := compiled.backend.search(compiled.handle, line, pos)
		if hit == null:
			_emit(pos, length, _current_scope(state))
			break

		var old_pos := pos
		var depth_before := state.depth()
		if hit.start > pos:
			_emit(pos, hit.start, _current_scope(state))
			pos = hit.start

		var entry: Dictionary = compiled.entries[hit.alt]
		var rule: TMRule = entry["rule"]
		if debug:
			print("  hit pos=%d alt=%d %d..%d end=%s kind=%d depth=%d rule=%s" % [
				pos, hit.alt, hit.start, hit.end, str(entry["end"]), rule.kind, state.depth(),
				rule.pattern.substr(0, 40).replace("\n", " "),
			])

		if entry["end"]:
			var base := frame.scope if frame != null else _root_scope
			_emit_captures(hit.start, hit.end, base, rule.end_captures, hit)
			state.pop()
			anchor = frame.prev_anchor if frame != null else -1
		elif rule.kind == TMRule.KIND_MATCH:
			var base := _current_scope(state)
			if rule.name != "":
				base = _scope_node(base, rule.name)
			_emit_captures(hit.start, hit.end, base, rule.captures, hit)
		else:
			var base := _current_scope(state)
			var scoped := base
			if rule.name != "":
				scoped = _scope_node(base, rule.name)
			_emit_captures(hit.start, hit.end, scoped, rule.begin_captures, hit)

			if state.depth() < MAX_STACK_DEPTH:
				var frame_new := TMState.Frame.new()
				frame_new.rule = rule
				frame_new.scope = scoped
				frame_new.content_scope = scoped
				frame_new.end_pattern = _resolve_end_pattern(rule.end_pattern, hit)
				frame_new.prev_anchor = anchor
				anchor = hit.end
				if rule.content_name != "":
					frame_new.content_scope = _scope_node(scoped, rule.content_name)
				state.push(frame_new)

		# Zero width matches (end patterns such as `$`, lookahead asserts) are
		# legal and often change the state.  Only force progress when nothing
		# moved, and bail out of pathological begin/end ping-pong.
		pos = hit.end
		if pos > old_pos:
			zero_width = 0
		elif state.depth() != depth_before and zero_width < 8:
			zero_width += 1
		else:
			pos = old_pos + 1
			zero_width = 0

	state.anchor = anchor

	if pos < length:
		_emit(pos, length, _current_scope(state))


func tokens() -> PackedInt32Array:
	return _out


# --------------------------------------------------------------------------
# Scopes
# --------------------------------------------------------------------------

func _current_scope(state: TMState) -> TMState.ScopeNode:
	var node := state.current_scope()
	return node if node != null else _root_scope


func _scope_node(parent: TMState.ScopeNode, names_text: String) -> TMState.ScopeNode:
	if names_text == "":
		return parent

	var parent_id := parent.id if parent != null else -1
	var key := "%d|%s" % [parent_id, names_text]
	var cached = _scope_cache.get(key)
	if cached != null:
		return cached

	var node := TMState.ScopeNode.new()
	node.parent = parent
	node.names = names_text.split(" ", false)
	node.id = _next_scope_id
	_next_scope_id += 1
	node.full_key = names_text if parent == null else parent.full_key + " " + names_text
	node.color = theme.color_for(node.full_key) if theme != null else Color.WHITE

	_scope_cache[key] = node
	return node


# --------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------

func _emit(from: int, to: int, node: TMState.ScopeNode) -> void:
	if to <= from:
		return

	var color: Color = node.color if node != null else Color.WHITE
	if debug:
		print("    emit %d..%d scope=%s color=#%s" % [from, to, node.full_key if node != null else "<none>", color.to_html(false)])
	if not _has_last or _last_color != color:
		_out.append(from)
		_out.append(_pack(color))
		_has_last = true
		_last_color = color


func _emit_captures(from: int, to: int, base: TMState.ScopeNode, captures: Dictionary, hit: TMScannerBackend.TMMatch) -> void:
	if captures.is_empty() or hit.groups.is_empty():
		_emit(from, to, base)
		return

	var regions: Array = []
	for group in captures:
		var index := int(group)
		if index <= 0:
			continue
		var offset := (index - 1) * 2
		if offset + 1 >= hit.groups.size():
			continue
		var start := hit.groups[offset]
		var end := hit.groups[offset + 1]
		if start < 0 or end <= start:
			continue
		start = maxi(start, from)
		end = mini(end, to)
		if end <= start:
			continue
		regions.append([start, end, _scope_node(base, String(captures[group]))])

	if regions.is_empty():
		_emit(from, to, base)
		return

	var bounds: Array = [from, to]
	for region in regions:
		bounds.append(region[0])
		bounds.append(region[1])
	bounds.sort()

	for i in range(bounds.size() - 1):
		var start: int = bounds[i]
		var end: int = bounds[i + 1]
		if end <= start:
			continue
		var node := base
		var best := -1
		for region in regions:
			if region[0] <= start and region[1] >= end and region[0] > best:
				best = region[0]
				node = region[2]
		_emit(start, end, node)


func _pack(color: Color) -> int:
	return (color.r8 << 24) | (color.g8 << 16) | (color.b8 << 8) | color.a8


# --------------------------------------------------------------------------
# Scanner compilation
# --------------------------------------------------------------------------

func _compiled_for(state: TMState, allow_g: bool, allow_a: bool) -> Compiled:
	var key := "%s|g%d|a%d" % [_scanner_key(state), 1 if allow_g else 0, 1 if allow_a else 0]
	var cached = _compiled.get(key)
	if cached != null:
		return cached

	var frame := state.top()
	var entries: Array = []
	var alternatives := PackedStringArray()
	var counts := PackedInt32Array()

	if frame == null:
		_add_rules(grammar, grammar.root_container, entries, alternatives, counts, allow_g, allow_a)
	else:
		var rule: TMRule = frame.rule
		var owner: TMGrammar = rule.grammar if rule.grammar != null else grammar
		var end_entry := {"rule": rule, "end": true}
		var end_pattern := frame.end_pattern if frame.end_pattern != "" else rule.end_pattern
		var has_end := rule.kind == TMRule.KIND_BEGIN_END and end_pattern != ""

		if has_end and not rule.apply_end_pattern_last:
			_add_alt(entries, alternatives, counts, end_entry, end_pattern, allow_g, allow_a)

		_add_rules(owner, rule.container_id, entries, alternatives, counts, allow_g, allow_a)

		if has_end and rule.apply_end_pattern_last:
			_add_alt(entries, alternatives, counts, end_entry, end_pattern, allow_g, allow_a)

	if alternatives.is_empty():
		_compiled[key] = null
		return null

	var compiled := Compiled.new()
	compiled.entries = entries

	if alternatives.size() <= MAX_ALTERNATIVES and not _has_back_reference(alternatives):
		compiled.handle = _pcre2.compile(alternatives, counts)
		compiled.backend = _pcre2

	if compiled.handle == null:
		compiled.handle = _sequential.compile(alternatives, counts)
		compiled.backend = _sequential

	_compiled[key] = compiled
	return compiled


func _add_rules(owner: TMGrammar, container_id: int, entries: Array, alternatives: PackedStringArray, counts: PackedInt32Array, allow_g: bool, allow_a: bool) -> void:
	if owner == null or container_id < 0:
		return
	for rule in owner.rule_set(container_id):
		_add_alt(entries, alternatives, counts, {"rule": rule, "end": false}, rule.opening_pattern(), allow_g, allow_a)


func _add_alt(entries: Array, alternatives: PackedStringArray, counts: PackedInt32Array, entry: Dictionary, pattern: String, allow_g: bool, allow_a: bool) -> void:
	var normalized := _normalize(pattern)
	# \G only matches at TextMate's anchor position, \A only on the first line.
	if not allow_g:
		normalized = normalized.replace("\\G", "(?!)")
	if not allow_a:
		normalized = normalized.replace("\\A", "(?!)")
	entries.append(entry)
	alternatives.append(normalized)
	counts.append(_count_groups(normalized))


func _scanner_key(state: TMState) -> String:
	var frame := state.top()
	if frame == null or frame.rule == null:
		return "root|%s" % grammar.path
	var rule: TMRule = frame.rule
	var owner_path := rule.grammar.path if rule.grammar != null else grammar.path
	var end_pattern := frame.end_pattern if frame.end_pattern != "" else rule.end_pattern
	return "%s|%d|%d|%s" % [owner_path, rule.container_id, rule.kind, end_pattern]


func _matches_while(pattern: String, line: String) -> bool:
	if pattern == "":
		return true
	var regex: RegEx = _single_regex.get(pattern)
	if regex == null:
		regex = RegEx.new()
		if regex.compile(_normalize(pattern), false) != OK:
			_single_regex[pattern] = RegEx.new()
			return false
		_single_regex[pattern] = regex
	if not regex.is_valid():
		return false
	var hit := regex.search(line, 0)
	return hit != null and hit.get_start(0) == 0


# --------------------------------------------------------------------------
# Pattern helpers
# --------------------------------------------------------------------------

## TextMate end patterns may back reference groups captured by the begin
## pattern (MagicPython: end "(\\3)" for the opening quote).  Substitute the
## literal text that was matched so the end pattern compiles on its own.
func _resolve_end_pattern(pattern: String, hit: TMScannerBackend.TMMatch) -> String:
	if pattern.find("\\") == -1:
		return pattern

	var out := ""
	var i := 0
	var length := pattern.length()
	while i < length:
		var ch := pattern[i]
		if ch == "\\" and i + 1 < length:
			var next := pattern[i + 1]
			if next >= "1" and next <= "9":
				var group := int(next)
				var offset := (group - 1) * 2
				if offset + 1 < hit.groups.size():
					var start := hit.groups[offset]
					var end := hit.groups[offset + 1]
					if start >= 0 and end > start:
						out += _escape_regex(_line.substr(start, end - start))
						i += 2
						continue
			out += pattern.substr(i, 2)
			i += 2
			continue
		out += ch
		i += 1
	return out


func _escape_regex(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text[i]
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out


func _has_back_reference(alternatives: PackedStringArray) -> bool:
	for pattern in alternatives:
		var i := 0
		while i < pattern.length() - 1:
			if pattern[i] == "\\":
				var next := pattern[i + 1]
				if next >= "1" and next <= "9":
					return true
				i += 2
				continue
			i += 1
	return false


## Godot uses PCRE2: drop the group *names* (numbers are kept) so dozens of
## patterns can be merged into one alternation without duplicate name errors.
func _normalize(pattern: String) -> String:
	var out := ""
	var i := 0
	var length := pattern.length()

	while i < length:
		var ch := pattern[i]
		if ch == "\\" and i + 1 < length:
			out += pattern.substr(i, 2)
			i += 2
			continue

		if ch == "(" and i + 1 < length and pattern[i + 1] == "?":
			var j := i + 2
			if j < length and pattern[j] == "<" and j + 1 < length and pattern[j + 1] != "=" and pattern[j + 1] != "!":
				var close := pattern.find(">", j)
				if close != -1:
					out += "("
					i = close + 1
					continue
			if j + 1 < length and pattern[j] == "P" and pattern[j + 1] == "<":
				var close_p := pattern.find(">", j)
				if close_p != -1:
					out += "("
					i = close_p + 1
					continue
			if j < length and pattern[j] == "'":
				var close_q := pattern.find("'", j + 1)
				if close_q != -1:
					out += "("
					i = close_q + 1
					continue

		out += ch
		i += 1

	return out


func _count_groups(pattern: String) -> int:
	var count := 0
	var i := 0
	var length := pattern.length()
	var in_class := false

	while i < length:
		var ch := pattern[i]

		if ch == "\\" and i + 1 < length:
			i += 2
			continue

		if in_class:
			if ch == "]":
				in_class = false
			i += 1
			continue

		if ch == "[":
			in_class = true
			i += 1
			continue

		if ch == "(":
			if i + 1 < length and pattern[i + 1] == "?":
				i += 1
				continue
			count += 1

		i += 1

	return count
