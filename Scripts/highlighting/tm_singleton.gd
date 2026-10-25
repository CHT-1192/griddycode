extends Node

## Autoload "TextMate": knows which grammar belongs to which file extension and
## caches the parsed grammars.

const MANIFEST_PATH := "res://Grammars/manifest.json"

var _loaded := false
var _extensions: Dictionary = {}
var _entries: Dictionary = {}
var _grammars: Dictionary = {}


func _ready() -> void:
	load_manifest()


func load_manifest(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	_extensions.clear()
	_entries.clear()

	var data: Variant = _read_json(MANIFEST_PATH)
	if not (data is Dictionary):
		push_warning("TextMate: cannot read %s" % MANIFEST_PATH)
		return

	var grammars = data.get("grammars", [])
	if not (grammars is Array):
		return

	for entry in grammars:
		if not (entry is Dictionary):
			continue
		var scope := String(entry.get("scope", ""))
		if scope == "":
			continue
		_entries[scope] = entry
		var extensions = entry.get("extensions", [])
		if extensions is Array:
			for extension in extensions:
				_extensions[String(extension).to_lower()] = scope


func has_grammar(extension: String) -> bool:
	return _extensions.has(extension.to_lower())


func scope_for_extension(extension: String) -> String:
	return String(_extensions.get(extension.to_lower(), ""))


func grammar_for_extension(extension: String) -> TMGrammar:
	var scope := scope_for_extension(extension)
	if scope == "":
		return null
	return grammar_for_scope(scope)


func grammar_for_scope(scope: String) -> TMGrammar:
	if _grammars.has(scope):
		return _grammars[scope]
	if not _entries.has(scope):
		return null

	var entry: Dictionary = _entries[scope]
	var path := String(entry.get("path", ""))
	var data: Variant = _read_json(path)
	if not (data is Dictionary):
		push_warning("TextMate: cannot read grammar for %s (%s)" % [scope, path])
		_grammars[scope] = null
		return null

	var grammar := TMGrammar.new()
	grammar.db = self
	grammar.load_from_dict(data, path)
	_grammars[scope] = grammar
	return grammar


func warnings() -> PackedStringArray:
	var all := PackedStringArray()
	for scope in _grammars:
		var grammar = _grammars[scope]
		if grammar != null:
			for warning in grammar.warnings:
				all.append(warning)
	return all


func _read_json(path: String) -> Variant:
	if path == "":
		return null

	# .json files are imported as JSON resources; prefer that so exported builds
	# keep working, and fall back to reading the raw file in the editor.
	if ResourceLoader.exists(path):
		var resource = load(path)
		if resource is JSON:
			var data = resource.data
			if data != null:
				return data

	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				return json.data

	return null
