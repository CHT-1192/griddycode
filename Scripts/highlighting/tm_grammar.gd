class_name TMGrammar
extends RefCounted

## A parsed TextMate grammar.  Raw JSON is indexed once (every `patterns` array
## becomes a container with an id), after which rule sets are expanded lazily
## and memoized.  Includes are resolved on demand so recursive grammars such as
## Python or C++ work without extra bookkeeping.

var scope_name := ""
var name := ""
var file_types: PackedStringArray = PackedStringArray()
var path := ""
var root_container := -1

## Used for cross grammar includes (`include: "source.css"`).  The TextMate
## autoload assigns itself here; tests may assign a stub.
var db: Object = null

var warnings: PackedStringArray = PackedStringArray()

## Array of Array.  Every entry is either a TMRule or a Dictionary with
## "__container" (inline another container) or "__include" (resolve by name).
var _containers: Array = []
var _repository: Dictionary = {}
var _rule_sets: Dictionary = {}
var _expanding: Dictionary = {}


func load_from_dict(data: Dictionary, p_path: String = "") -> void:
	path = p_path
	scope_name = String(data.get("scopeName", ""))
	name = String(data.get("name", scope_name))
	file_types.clear()
	var types = data.get("fileTypes", [])
	if types is Array:
		for t in types:
			file_types.append(String(t))

	var repository = data.get("repository", {})
	if repository is Dictionary:
		for key in repository:
			_repository[String(key)] = _index_entry(repository[key])

	var patterns = data.get("patterns", [])
	if patterns is Array:
		root_container = _index_patterns(patterns)
	else:
		root_container = _index_patterns([])


func is_valid() -> bool:
	return root_container >= 0


func rules() -> Array:
	return rule_set(root_container)


# --------------------------------------------------------------------------
# Indexing
# --------------------------------------------------------------------------

func _index_patterns(patterns: Array) -> int:
	var container_id := _containers.size()
	_containers.append([])
	var indexed: Array = []
	for entry in patterns:
		indexed.append(_index_entry(entry))
	_containers[container_id] = indexed
	return container_id


func _index_entry(entry: Variant) -> Variant:
	if entry is String:
		return {"__include": String(entry)}

	if not (entry is Dictionary):
		return {"__include": ""}

	var d: Dictionary = entry
	var has_match := d.has("match")
	var has_begin := d.has("begin")

	if not has_match and not has_begin:
		if d.has("include") and not d.has("patterns"):
			return {"__include": String(d["include"])}
		if d.has("patterns"):
			return {"__container": _index_patterns(d["patterns"])}
		if d.has("include"):
			return {"__include": String(d["include"])}
		return {"__include": ""}

	var rule := TMRule.new()
	rule.grammar = self

	if has_begin:
		rule.pattern = String(d["begin"])
		if d.has("end"):
			rule.kind = TMRule.KIND_BEGIN_END
			rule.end_pattern = String(d["end"])
		elif d.has("while"):
			rule.kind = TMRule.KIND_BEGIN_WHILE
			rule.while_pattern = String(d["while"])
		else:
			rule.kind = TMRule.KIND_BEGIN_END
			rule.end_pattern = ""
	else:
		rule.kind = TMRule.KIND_MATCH
		rule.pattern = String(d["match"])

	rule.name = String(d.get("name", ""))
	rule.content_name = String(d.get("contentName", ""))
	rule.captures = _captures(d.get("captures", {}))
	rule.begin_captures = _captures(d.get("beginCaptures", {}))
	rule.end_captures = _captures(d.get("endCaptures", {}))
	rule.apply_end_pattern_last = bool(d.get("applyEndPatternLast", false))

	if d.has("patterns"):
		rule.container_id = _index_patterns(d["patterns"])

	return rule


func _captures(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	for key in d:
		var group := int(str(key))
		var scope := ""
		var value = d[key]
		if value is Dictionary:
			scope = String(value.get("name", ""))
		elif value is String:
			scope = String(value)
		if scope != "":
			out[group] = scope
	return out


# --------------------------------------------------------------------------
# Rule sets
# --------------------------------------------------------------------------

## Flattened list of terminal rules (match / begin-end) for a container.
func rule_set(container_id: int) -> Array:
	if container_id < 0 or container_id >= _containers.size():
		return []
	if _rule_sets.has(container_id):
		return _rule_sets[container_id]

	var out: Array = []
	_rule_sets[container_id] = out

	for entry in _containers[container_id]:
		if entry is TMRule:
			out.append(entry)
		elif entry is Dictionary:
			if entry.has("__container"):
				out.append_array(rule_set(int(entry["__container"])))
			else:
				out.append_array(_expand(String(entry.get("__include", "")), container_id))

	return out


func _expand(include: String, from_container: int) -> Array:
	if include == "":
		return []

	if include.begins_with("#"):
		return _expand_repository(include.substr(1))

	if include == "$self" or include == "$base":
		return rule_set(root_container)

	var key := "%s|%d|%s" % [scope_name, from_container, include]
	if _expanding.has(key):
		return []
	_expanding[key] = true

	var result: Array = []

	if include.contains("#"):
		var parts := include.split("#", true, 1)
		var other := _resolve_grammar(parts[0])
		if other != null:
			result = other._expand_repository(parts[1])
	else:
		var other := _resolve_grammar(include)
		if other != null:
			if other == self:
				result = rule_set(root_container)
			else:
				result = other.rule_set(other.root_container)

	_expanding.erase(key)
	return result


func _expand_repository(repo_name: String) -> Array:
	if not _repository.has(repo_name):
		_warn("missing repository entry '#%s'" % repo_name)
		return []
	var entry = _repository[repo_name]
	if entry is TMRule:
		return [entry]
	if entry is Dictionary:
		if entry.has("__container"):
			return rule_set(int(entry["__container"]))
		return _expand(String(entry.get("__include", "")), -1)
	return []


func _resolve_grammar(target_scope: String) -> TMGrammar:
	if db != null and db.has_method("grammar_for_scope"):
		return db.grammar_for_scope(target_scope)
	_warn("cannot resolve external grammar '%s'" % target_scope)
	return null


func _warn(message: String) -> void:
	var text := "%s: %s" % [scope_name, message]
	if not warnings.has(text):
		warnings.append(text)
