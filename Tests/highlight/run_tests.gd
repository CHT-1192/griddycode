extends SceneTree

## Headless test suite for the TextMate highlighter.
##
##   godot --headless --path . --script res://Tests/highlight/run_tests.gd
##
## Exit code is the number of failed checks.

const MINI_GRAMMAR := r"""
{
  "scopeName": "source.test",
  "patterns": [
    {"include": "#comment"},
    {"include": "#string"},
    {"match": "(if|else)\\b", "name": "keyword.control"},
    {"match": "([a-z_]+)(?=\\s*=)", "name": "variable.other", "captures": {"1": {"name": "variable.other.readwrite"}}}
  ],
  "repository": {
    "comment": {"match": "(#).*$", "name": "comment.line", "captures": {"1": {"name": "punctuation.definition.comment"}}},
    "string": {"begin": "\"", "end": "\"", "name": "string.quoted.double", "contentName": "string.content"}
  }
}
"""

const COLORS := {
	"reserved": Color("c678dd"),
	"annotation": Color("a2b429"),
	"string": Color("98c379"),
	"binary": Color("d19a66"),
	"symbol": Color("839fb6"),
	"variable": Color("e5c07b"),
	"operator": Color("56b6c2"),
	"comments": Color("7f848e"),
	"error": Color("d31820"),
	"function": Color("61afef"),
	"member": Color("e06c75"),
}
const DEFAULT_COLOR := Color("abb2bf")

var _checks := 0
var _failures := 0
var _db: Node


func _initialize() -> void:
	_db = load("res://Scripts/highlighting/tm_singleton.gd").new()
	_db.load_manifest()

	_test_theme()
	_test_mini_grammar()
	_test_python()
	_test_backend_parity()
	_test_fallback()
	_test_integration()
	_test_grammar_health()
	_bench()

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------------------
# Harness
# --------------------------------------------------------------------------

func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: ", label)


func check_color(tokens: PackedInt32Array, column: int, expected: Color, label: String) -> void:
	var actual := color_at(tokens, column)
	_checks += 1
	if actual != expected:
		_failures += 1
		print("  FAIL: %s (col %d expected %s, got %s)" % [label, column, expected.to_html(false), actual.to_html(false)])


func color_at(tokens: PackedInt32Array, column: int) -> Color:
	var result := DEFAULT_COLOR
	for i in range(0, tokens.size(), 2):
		if tokens[i] <= column:
			var value := tokens[i + 1]
			result = Color8((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
		else:
			break
	return result


func make_theme() -> TMTheme:
	return TMTheme.from_categories(COLORS, DEFAULT_COLOR)


# --------------------------------------------------------------------------
# Theme
# --------------------------------------------------------------------------

func _test_theme() -> void:
	print("theme")
	var theme := make_theme()

	# keyword.operator is more specific than keyword
	check(theme.color_for("source.test keyword.operator.assignment") == COLORS["operator"], "operator specificity")
	check(theme.color_for("source.test keyword.control") == COLORS["reserved"], "keyword")
	# string/comment are declared later, so they also win over punctuation inside them
	check(theme.color_for("source.test comment.line punctuation.definition.comment") == COLORS["comments"], "comment covers punctuation")
	check(theme.color_for("source.test string.quoted punctuation.definition.string") == COLORS["string"], "string covers punctuation")
	check(theme.color_for("source.test constant.numeric") == COLORS["binary"], "numeric")
	check(theme.color_for("source.test entity.name.function") == COLORS["function"], "function name")
	check(theme.color_for("source.test plain.text") == DEFAULT_COLOR, "default")
	# caching must not change the answer
	check(theme.color_for("source.test keyword.control") == COLORS["reserved"], "keyword cached")


# --------------------------------------------------------------------------
# Engine behaviour on a tiny grammar
# --------------------------------------------------------------------------

func _test_mini_grammar() -> void:
	print("mini grammar")
	var grammar := TMGrammar.new()
	grammar.load_from_dict(JSON.parse_string(MINI_GRAMMAR), "mini")
	var tokenizer := TMTokenizer.new()
	tokenizer.setup(grammar, make_theme())
	var state := TMState.new()

	tokenizer.tokenize("if x \"abc\"", state)
	var tokens := tokenizer.tokens()
	check_color(tokens, 0, COLORS["reserved"], "mini keyword")
	check_color(tokens, 3, DEFAULT_COLOR, "mini plain")
	check_color(tokens, 5, COLORS["string"], "mini string open")
	check(tokens.size() > 0, "mini tokens emitted")

	tokenizer.tokenize("# hi if else", state)
	tokens = tokenizer.tokens()
	check_color(tokens, 0, COLORS["comments"], "mini comment covers keyword")
	check_color(tokens, 9, COLORS["comments"], "mini comment to end")

	# multi line string keeps its frame and closes on the second line
	var multiline := TMState.new()
	tokenizer.tokenize("\"abc", multiline)
	check(multiline.depth() == 1, "string frame open")
	tokenizer.tokenize("def\"", multiline)
	check_color(tokenizer.tokens(), 0, COLORS["string"], "string content second line")
	check(multiline.depth() == 0, "string frame closed")

	# capture groups paint a sub range
	tokenizer.tokenize("total = 1", TMState.new())
	tokens = tokenizer.tokens()
	check_color(tokens, 0, COLORS["variable"], "capture group")


# --------------------------------------------------------------------------
# Real grammar
# --------------------------------------------------------------------------

func _test_python() -> void:
	print("python grammar")
	var grammar: TMGrammar = _db.grammar_for_extension("py")
	check(grammar != null, "python grammar loads")
	if grammar == null:
		return
	check(grammar.rules().size() > 20, "python root rules")
	check(grammar.warnings.is_empty(), "python grammar has no warnings")

	var tokenizer := TMTokenizer.new()
	tokenizer.setup(grammar, make_theme())
	var state := TMState.new()

	tokenizer.tokenize("# comment with def inside", state)
	var tokens := tokenizer.tokens()
	check_color(tokens, 0, COLORS["comments"], "python comment")
	check_color(tokens, 10, COLORS["comments"], "def inside comment is not a keyword")
	check(state.depth() == 0, "comment pops at end of line")

	tokenizer.tokenize("    return \"text with if inside\"", state)
	tokens = tokenizer.tokens()
	check_color(tokens, 4, COLORS["reserved"], "return keyword")
	check_color(tokens, 11, COLORS["string"], "string opens")
	check_color(tokens, 17, COLORS["string"], "if inside string stays string")
	check(state.depth() == 0, "string closes")

	# triple quoted block spans lines
	var triple := TMState.new()
	tokenizer.tokenize("\"\"\"", triple)
	check_color(tokenizer.tokens(), 0, COLORS["string"], "triple quote opens")
	check(triple.depth() > 0, "triple quote keeps state")
	tokenizer.tokenize("triple quoted block", triple)
	check_color(tokenizer.tokens(), 0, COLORS["string"], "triple quote body")
	tokenizer.tokenize("\"\"\"", triple)
	check(triple.depth() <= 1, "triple quote closes its string")
	tokenizer.tokenize("next_statement = 1", triple)
	check(triple.depth() == 0, "docstring statement closes on the next line")

	tokenizer.tokenize("value = 42 + other", state)
	tokens = tokenizer.tokens()
	check_color(tokens, 6, COLORS["operator"], "assignment operator")
	check_color(tokens, 8, COLORS["binary"], "number")


# --------------------------------------------------------------------------
# Backend parity
# --------------------------------------------------------------------------

func _test_backend_parity() -> void:
	print("backend parity")
	var alternatives := PackedStringArray(["(if|else)\\b", "([a-z_]+)(?=\\s*=)", "(\\d+)"])
	var counts := PackedInt32Array([1, 1, 1])
	var pcre2 := TMScannerPCRE2.new()
	var sequential := TMScannerSequential.new()
	var pcre2_handle = pcre2.compile(alternatives, counts)
	check(pcre2_handle != null, "pcre2 compiles")
	var sequential_handle = sequential.compile(alternatives, counts)
	check(sequential_handle != null, "sequential compiles")

	for subject in ["if x = 12", "else 7", "plain"]:
		for offset in [0, 3]:
			var a = pcre2.search(pcre2_handle, subject, offset)
			var b = sequential.search(sequential_handle, subject, offset)
			if a == null or b == null:
				check(a == null and b == null, "parity null %s@%d" % [subject, offset])
				continue
			check(a.alt == b.alt and a.start == b.start and a.end == b.end, "parity match %s@%d" % [subject, offset])
			check(a.groups == b.groups, "parity groups %s@%d" % [subject, offset])


# --------------------------------------------------------------------------
# Fallback (no grammar)
# --------------------------------------------------------------------------

func _test_fallback() -> void:
	print("fallback")
	var fallback := TMFallback.new()
	fallback.setup(
		COLORS,
		{"def": "reserved", "print": "function"},
		[["#", "", "comments", true], ["\"", "\"", "string", true]],
		DEFAULT_COLOR
	)
	var tokens := fallback.tokenize("def # note")
	check_color(tokens, 0, COLORS["reserved"], "fallback keyword")
	check_color(tokens, 4, COLORS["comments"], "fallback region")

	tokens = fallback.tokenize("print \"text\"")
	check_color(tokens, 0, COLORS["function"], "fallback function keyword")
	check_color(tokens, 6, COLORS["string"], "fallback quoted region")


# --------------------------------------------------------------------------
# Godot integration
# --------------------------------------------------------------------------

func _test_integration() -> void:
	print("integration")
	var edit := CodeEdit.new()
	edit.text = "def f():\n    return 1\n"
	var highlighter := TMHighlighter.new()
	highlighter.set_theme(make_theme())
	highlighter.set_grammar(_db.grammar_for_extension("py"))
	highlighter.configure_fallback(COLORS, {}, [], DEFAULT_COLOR)
	edit.syntax_highlighter = highlighter
	root.add_child(edit)

	var line0 := highlighter.get_line_syntax_highlighting(0)
	check(line0.size() > 0, "integration line has colors")
	check(bool(line0.has(0)), "integration column 0 present")
	if line0.has(0):
		var color: Color = line0[0]["color"]
		check(color == COLORS["reserved"], "integration def is reserved")

	# the highlighter must answer out of order without re-reading everything
	var line1 := highlighter.get_line_syntax_highlighting(1)
	check(line1.size() > 0, "integration second line")
	var again := highlighter.get_line_syntax_highlighting(0)
	check(again.size() == line0.size(), "integration cached result stable")

	# editing invalidates from the edited line
	edit.set_line(0, "# comment")
	highlighter.invalidate_from(0)
	var edited := highlighter.get_line_syntax_highlighting(0)
	var first_color: Color = edited[0]["color"]
	check(first_color == COLORS["comments"], "integration edit recolors")

	edit.queue_free()


# --------------------------------------------------------------------------
# Grammar health
# --------------------------------------------------------------------------

func _test_grammar_health() -> void:
	print("grammar health")
	var samples := {
		"py": "def f(x): return \"s\"",
		"js": "const x = \"a\"; // c",
		"ts": "let x: number = 1;",
		"json": "{\"a\": 1}",
		"lua": "local x = 1 -- c",
		"go": "func main() {}",
		"c": "int main(void) { return 0; }",
		"cpp": "std::vector<int> v;",
		"rs": "fn main() { let x = 1; }",
		"css": "body { color: red; }",
		"html": "<div class=\"x\">hi</div>",
		"md": "# Title",
		"sh": "echo \"hi\"",
		"yaml": "key: value",
	}

	for extension in samples:
		var grammar: TMGrammar = _db.grammar_for_extension(extension)
		check(grammar != null, "grammar %s loads" % extension)
		if grammar == null:
			continue
		check(grammar.rules().size() > 0, "grammar %s has rules" % extension)
		var tokenizer := TMTokenizer.new()
		tokenizer.setup(grammar, make_theme())
		tokenizer.tokenize(samples[extension], TMState.new())
		check(tokenizer.tokens().size() > 0, "grammar %s tokenizes" % extension)

	# cross grammar include: HTML opens a CSS block
	var html: TMGrammar = _db.grammar_for_extension("html")
	var css: TMGrammar = _db.grammar_for_extension("css")
	if html != null and css != null:
		var tokenizer := TMTokenizer.new()
		tokenizer.setup(html, make_theme())
		var state := TMState.new()
		tokenizer.tokenize("<style>", state)
		tokenizer.tokenize("body { color: red; }", state)
		var embedded := tokenizer.tokens()
		check(embedded.size() > 0, "html css block tokenizes")
		check_color(embedded, 0, COLORS["reserved"], "css selector inside html")

		var standalone := TMTokenizer.new()
		standalone.setup(css, make_theme())
		standalone.tokenize("body { color: red; }", TMState.new())
		check(embedded == standalone.tokens(), "embedded css matches standalone css")


# --------------------------------------------------------------------------
# Performance
# --------------------------------------------------------------------------

func _bench() -> void:
	print("bench")
	var grammar: TMGrammar = _db.grammar_for_extension("py")
	if grammar == null:
		return

	var lines: Array[String] = []
	for i in 1000:
		lines.append("def function_%d(value, other):  # comment %d" % [i, i])
		lines.append("    return value + other * %d" % i)

	var tokenizer := TMTokenizer.new()
	tokenizer.setup(grammar, make_theme())
	var state := TMState.new()
	var start := Time.get_ticks_msec()
	for line in lines:
		tokenizer.tokenize(line, state)
	var elapsed := Time.get_ticks_msec() - start
	print("  %d lines in %d ms (%.0f lines/s)" % [lines.size(), elapsed, lines.size() * 1000.0 / maxf(elapsed, 1)])
	check(elapsed < 4000, "bench under 4s for 2000 lines")
