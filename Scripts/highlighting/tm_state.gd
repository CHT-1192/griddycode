class_name TMState
extends RefCounted

## Tokenizer state: the stack of grammar rules that are currently open at the
## start of a line, plus the scope chain that goes with every frame.
##
## A state is mutated while a line is tokenized and cloned once at the end, so
## the clone can be stored as "state at the end of line N".


## One entry of the scope chain. Nodes are interned by the tokenizer, so equal
## chains are the same object and the resolved color is cached on the node.
class ScopeNode:
	var parent: ScopeNode = null
	var names: PackedStringArray = PackedStringArray()
	var full_key: String = ""
	var color: Color = Color.WHITE
	var id: int = 0


class Frame:
	var rule: TMRule = null
	var scope: ScopeNode = null
	var content_scope: ScopeNode = null
	## End pattern with back references resolved against the begin match.
	var end_pattern: String = ""
	## Anchor position to restore when this frame is popped.
	var prev_anchor: int = -1


var frames: Array = []
## Position at which \G anchored rules may match (TextMate's anchorPosition).
var anchor: int = -1


func clone() -> TMState:
	var state := TMState.new()
	state.frames = frames.duplicate()
	state.anchor = anchor
	return state


func is_empty() -> bool:
	return frames.is_empty()


func depth() -> int:
	return frames.size()


func top() -> Frame:
	if frames.is_empty():
		return null
	return frames[frames.size() - 1]


func push(frame: Frame) -> void:
	frames.append(frame)


func pop() -> void:
	if not frames.is_empty():
		frames.pop_back()


func current_scope() -> ScopeNode:
	var frame := top()
	if frame == null:
		return null
	return frame.content_scope


func content_container() -> int:
	var frame := top()
	if frame == null or frame.rule == null:
		return -1
	return frame.rule.container_id
