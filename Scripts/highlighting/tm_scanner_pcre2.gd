class_name TMScannerPCRE2
extends TMScannerBackend

## Default backend: all alternatives of a state are merged into one PCRE2
## alternation, so a single RegEx.search() finds the next token for the whole
## state.  Each alternative is wrapped in its own capture group; the wrapper
## groups are what tells us which rule matched.

class Handle:
	var regex: RegEx = null
	var wrappers: PackedInt32Array = PackedInt32Array()
	var capture_counts: PackedInt32Array = PackedInt32Array()


func backend_name() -> String:
	return "pcre2"


func compile(alternatives: PackedStringArray, capture_counts: PackedInt32Array) -> Variant:
	if alternatives.is_empty():
		return null

	var parts := PackedStringArray()
	var wrappers := PackedInt32Array()
	var next_group := 1

	for i in alternatives.size():
		wrappers.append(next_group)
		parts.append("(" + alternatives[i] + ")")
		next_group += 1 + capture_counts[i]

	var pattern := "|".join(parts)
	var regex := RegEx.new()
	if regex.compile(pattern, false) != OK:
		return null

	# If the grammar contains constructs that change group numbering (branch
	# reset, conditionals) the counts do not line up and captures would be
	# garbage: let the tokenizer fall back to the sequential backend.
	if regex.get_group_count() != next_group - 1:
		return null

	var handle := Handle.new()
	handle.regex = regex
	handle.wrappers = wrappers
	handle.capture_counts = capture_counts
	return handle


func search(handle: Variant, subject: String, offset: int) -> TMMatch:
	var h := handle as Handle
	if h == null:
		return null

	var m := h.regex.search(subject, offset)
	if m == null:
		return null

	var alt := -1
	for i in h.wrappers.size():
		if m.get_start(h.wrappers[i]) != -1:
			alt = i
			break
	if alt == -1:
		return null

	var result := TMMatch.new()
	result.alt = alt
	result.start = m.get_start(0)
	result.end = m.get_end(0)

	var count := h.capture_counts[alt]
	if count > 0:
		var groups := PackedInt32Array()
		groups.resize(count * 2)
		for g in count:
			groups[g * 2] = m.get_start(h.wrappers[alt] + 1 + g)
			groups[g * 2 + 1] = m.get_end(h.wrappers[alt] + 1 + g)
		result.groups = groups

	return result
