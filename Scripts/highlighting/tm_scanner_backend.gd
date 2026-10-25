class_name TMScannerBackend
extends RefCounted

## Contract between the tokenizer and the regular expression engine.
##
## The tokenizer never touches RegEx directly: it asks a backend to compile a
## list of alternatives (ordered by rule priority) and to search them.  Swapping
## PCRE2 for Oniguruma later therefore only means writing another subclass.


class TMMatch:
	## Index of the alternative that matched, in the order given to compile().
	var alt: int = -1
	var start: int = 0
	var end: int = 0

	## Capture groups of the matched alternative, relative to that alternative's
	## own pattern (group 1 first), stored as [start, end, start, end, ...].
	## Unmatched groups are -1.
	var groups: PackedInt32Array = PackedInt32Array()


func backend_name() -> String:
	return "base"


## Whether compile() tolerates individual patterns that fail to compile
## (sequential backend) instead of failing as a whole (combined backend).
func tolerant() -> bool:
	return false


## Returns an opaque handle, or null when the whole set cannot be compiled.
func compile(_alternatives: PackedStringArray, _capture_counts: PackedInt32Array) -> Variant:
	return null


func search(_handle: Variant, _subject: String, _offset: int) -> TMMatch:
	return null
