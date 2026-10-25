class_name TMScannerSequential
extends TMScannerBackend

## Fallback backend: try every rule on its own and keep the earliest match
## (ties go to the lower rule index, which is TextMate's priority order).
##
## Used when the combined alternation is too large or when one broken pattern
## would make the whole PCRE2 alternation fail.  Patterns that do not compile
## are disabled individually, keeping the alternative numbering intact.

class Handle:
	var regexes: Array = []
	var capture_counts: PackedInt32Array = PackedInt32Array()
	var disabled: int = 0


func backend_name() -> String:
	return "sequential"


func tolerant() -> bool:
	return true


func compile(alternatives: PackedStringArray, capture_counts: PackedInt32Array) -> Variant:
	var handle := Handle.new()
	handle.capture_counts = capture_counts
	handle.regexes.resize(alternatives.size())

	for i in alternatives.size():
		var regex := RegEx.new()
		if regex.compile(alternatives[i], false) == OK:
			handle.regexes[i] = regex
		else:
			handle.regexes[i] = null
			handle.disabled += 1

	return handle


func search(handle: Variant, subject: String, offset: int) -> TMMatch:
	var h := handle as Handle
	if h == null:
		return null

	var best := TMMatch.new()
	best.alt = -1

	for i in h.regexes.size():
		var regex = h.regexes[i]
		if regex == null:
			continue

		var m: RegExMatch = regex.search(subject, offset)
		if m == null:
			continue

		var start := m.get_start(0)
		if best.alt != -1 and start >= best.start:
			continue

		best.alt = i
		best.start = start
		best.end = m.get_end(0)

		var count := h.capture_counts[i]
		if count > 0:
			var groups := PackedInt32Array()
			groups.resize(count * 2)
			for g in count:
				groups[g * 2] = m.get_start(g + 1)
				groups[g * 2 + 1] = m.get_end(g + 1)
			best.groups = groups
		else:
			best.groups = PackedInt32Array()

	if best.alt == -1:
		return null
	return best
