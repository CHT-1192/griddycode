class_name TMRule
extends RefCounted

## A single compiled TextMate rule: either a `match` rule or a `begin`/`end`
## (or `begin`/`while`) rule that pushes a frame onto the state stack.
##
## `container_id` points into the owning grammar's pattern containers and is
## what gets searched while the rule is open.

const KIND_MATCH := 0
const KIND_BEGIN_END := 1
const KIND_BEGIN_WHILE := 2

var kind: int = KIND_MATCH

## For KIND_MATCH this is the match pattern, for begin rules the begin pattern.
var pattern: String = ""
var end_pattern: String = ""
var while_pattern: String = ""

var name: String = ""
var content_name: String = ""

## group number (int) -> scope name (String)
var captures: Dictionary = {}
var begin_captures: Dictionary = {}
var end_captures: Dictionary = {}

var apply_end_pattern_last: bool = false
var container_id: int = -1
var grammar: TMGrammar = null


func is_begin() -> bool:
	return kind != KIND_MATCH


func is_while() -> bool:
	return kind == KIND_BEGIN_WHILE


func opening_pattern() -> String:
	return pattern
