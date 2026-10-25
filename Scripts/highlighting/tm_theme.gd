class_name TMTheme
extends RefCounted

## Maps a TextMate scope stack to a color.
##
## Rules are plain selectors such as "keyword.operator" or the descendant form
## "meta.function entity.name.function".  The most specific matching rule wins;
## ties go to the rule that was declared last, which mirrors how VS Code treats
## themes.  Resolved colors are cached per full scope key.

class Rule:
	var parts: PackedStringArray = PackedStringArray()
	var color: Color = Color.WHITE
	var specificity: int = 0
	var order: int = 0


## Legacy GriddyCode theme categories (the keys of LuaSingleton.keywords) mapped
## onto TextMate scopes.  Order matters: rules declared later win ties, so broad
## containers such as string/comment are declared last and therefore also color
## the punctuation inside them.
const BRIDGE := [
	["punctuation", "symbol"],
	["meta.brace", "symbol"],
	["constant.numeric", "binary"],
	["constant.language", "binary"],
	["constant.character.escape", "operator"],
	["constant.other", "variable"],
	["keyword.operator", "operator"],
	["keyword", "reserved"],
	["storage", "reserved"],
	["entity.name.tag", "reserved"],
	["entity.name.function", "function"],
	["support.function", "function"],
	["entity.name.type", "annotation"],
	["entity.other.attribute-name", "annotation"],
	["variable.other.property", "member"],
	["meta.object-literal.key", "member"],
	["variable.parameter", "variable"],
	["variable", "variable"],
	["invalid", "error"],
	["string", "string"],
	["comment", "comments"],
]

var rules: Array = []
var default_color: Color = Color.WHITE

var _cache: Dictionary = {}


static func from_categories(categories: Dictionary, fallback: Color) -> TMTheme:
	var theme := TMTheme.new()
	theme.default_color = fallback

	var order := 0
	for entry in BRIDGE:
		var selector: String = entry[0]
		var category: String = entry[1]
		if not categories.has(category):
			continue
		theme.add_rule(selector, categories[category], order)
		order += 1

	return theme


func add_rule(selector: String, color: Color, order: int = -1) -> void:
	var rule := Rule.new()
	rule.parts = selector.strip_edges().split(" ", false)
	rule.color = color
	rule.specificity = _specificity(rule.parts)
	rule.order = order if order >= 0 else rules.size()
	rules.append(rule)
	rules.sort_custom(_compare_rules)
	_cache.clear()


func color_for(full_key: String) -> Color:
	var cached = _cache.get(full_key)
	if cached != null:
		return cached

	var scopes := full_key.split(" ", false)
	var result := default_color
	var best_specificity := -1
	var best_order := -1

	for rule in rules:
		if rule.specificity < best_specificity:
			continue
		if not _matches(rule.parts, scopes):
			continue
		if rule.specificity > best_specificity or rule.order >= best_order:
			best_specificity = rule.specificity
			best_order = rule.order
			result = rule.color

	_cache[full_key] = result
	return result


func rule_count() -> int:
	return rules.size()


func _compare_rules(a: Rule, b: Rule) -> bool:
	if a.specificity != b.specificity:
		return a.specificity < b.specificity
	return a.order < b.order


func _specificity(parts: PackedStringArray) -> int:
	var total := 0
	for part in parts:
		total += part.split(".").size()
	return total


## Descendant selector matching: every part must appear in the scope stack, in
## order, with the last part matching the innermost scope.
static func _matches(parts: PackedStringArray, scopes: PackedStringArray) -> bool:
	var scope_index := scopes.size() - 1
	for k in range(parts.size() - 1, -1, -1):
		var selector := parts[k]
		var found := -1
		for i in range(scope_index, -1, -1):
			if _scope_matches(selector, scopes[i]):
				found = i
				break
		if found == -1:
			return false
		scope_index = found - 1
	return true


static func _scope_matches(selector: String, scope: String) -> bool:
	if selector == scope:
		return true
	if scope.length() > selector.length() and scope.begins_with(selector) and scope[selector.length()] == ".":
		return true
	# TextMate also allows a selector to be a dotted prefix of the scope name
	# in the other direction (selector "string.quoted" vs scope "string").
	return false
