class_name TMFallback
extends RefCounted

## Highlighting for extensions without a TextMate grammar.  Reproduces the old
## GriddyCode behaviour: a flat word -> color table plus delimited regions.

var keywords: Dictionary = {}
## Array of [start_key: String, end_key: String, color: Color]
var regions: Array = []
var default_color: Color = Color.WHITE

var _word_regex := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
var _out := PackedInt32Array()
var _has_last := false
var _last_color := Color.WHITE


func setup(categories: Dictionary, keyword_to_category: Dictionary, region_list: Array, fallback_color: Color) -> void:
	default_color = fallback_color

	keywords.clear()
	for word in keyword_to_category:
		var category := String(keyword_to_category[word])
		if categories.has(category):
			keywords[String(word)] = categories[category]

	regions.clear()
	for entry in region_list:
		if not (entry is Array) or entry.size() < 3:
			continue
		var category := String(entry[2])
		var color: Color = categories.get(category, fallback_color)
		regions.append([String(entry[0]), String(entry[1]), color])


func tokenize(line: String) -> PackedInt32Array:
	_out = PackedInt32Array()
	_has_last = false

	var spans: Array = []

	for hit in _word_regex.search_all(line):
		var word := hit.get_string()
		if keywords.has(word):
			spans.append([hit.get_start(0), hit.get_end(0), keywords[word]])

	for region in regions:
		var start_key: String = region[0]
		var end_key: String = region[1]
		var color: Color = region[2]
		var from := 0
		while from < line.length():
			var open_at := line.find(start_key, from)
			if open_at == -1:
				break
			var close_at := line.length()
			if end_key != "":
				var found := line.find(end_key, open_at + start_key.length())
				if found != -1:
					close_at = found + end_key.length()
			spans.append([open_at, close_at, color])
			from = close_at if close_at > open_at else open_at + start_key.length()

	if spans.is_empty():
		return _out

	var bounds: Array = [0, line.length()]
	for span in spans:
		bounds.append(span[0])
		bounds.append(span[1])
	bounds.sort()

	for i in range(bounds.size() - 1):
		var start: int = bounds[i]
		var end: int = bounds[i + 1]
		if end <= start:
			continue
		var color := default_color
		var best := -1
		for span in spans:
			if span[0] <= start and span[1] >= end and span[0] >= best:
				best = span[0]
				color = span[2]
		_emit(start, end, color)

	return _out


func _emit(from: int, to: int, color: Color) -> void:
	if to <= from:
		return
	if not _has_last or _last_color != color:
		_out.append(from)
		_out.append((color.r8 << 24) | (color.g8 << 16) | (color.b8 << 8) | color.a8)
		_has_last = true
		_last_color = color
