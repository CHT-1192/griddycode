# Syntax highlighting

GriddyCode highlights code with TextMate grammars, the same grammar format VS
Code uses. The engine is plain GDScript: no native extension, no extra build
step. Each grammar is a `.tmLanguage` file (JSON) shipped in `Grammars/`.

## How it works

```
Grammars/manifest.json
        │  extension -> scope -> grammar file
        ▼
TextMate (autoload)          parsed grammars, memoized include expansion
        ▼
TMTokenizer                  per line: state stack + one PCRE2 scan per token
        │                     (TMScannerPCRE2, with TMScannerSequential as fallback)
        ▼
PackedInt32Array             [column, rgba, column, rgba, ...]
        ▼
TMHighlighter                Godot SyntaxHighlighter, caches lines, invalidates on edit
```

| File | Responsibility |
| --- | --- |
| `Scripts/highlighting/tm_singleton.gd` | Autoload `TextMate`: manifest, grammar cache |
| `tm_grammar.gd` | Parses a grammar, expands `include`s lazily, resolves cross grammar includes |
| `tm_rule.gd` | One TextMate rule (`match`, `begin`/`end`, `begin`/`while`) |
| `tm_scanner_backend.gd` | Scanner interface (`compile`, `search`) |
| `tm_scanner_pcre2.gd` | Merges a state's rules into one PCRE2 alternation (fast path) |
| `tm_scanner_sequential.gd` | Tries rules one by one (fallback, tolerates broken patterns) |
| `tm_tokenizer.gd` | The state machine: anchors, zero width matches, captures, scopes |
| `tm_state.gd` | Stack frames and interned scope nodes |
| `tm_theme.gd` | Scope selectors -> colors, plus the legacy category bridge |
| `tm_highlighter.gd` | Godot integration, per line cache and invalidation |
| `tm_fallback.gd` | Old keyword/region highlighter for files without a grammar |

The tokenizer mutates a `TMState` (a stack of open `begin`/`end` rules) per
line and hands the end state to the next line, which is what makes multi line
strings, comments and `<style>` blocks work.

## Adding or replacing a language

1. Drop the grammar into `Grammars/`, for example `Grammars/zig.tmLanguage`
   (JSON; convert plist grammars first).
2. Add it to `Grammars/manifest.json`:

   ```json
   { "scope": "source.zig", "name": "Zig", "path": "res://Grammars/zig.tmLanguage", "extensions": ["zig"] }
   ```

   Grammars that are only reached through an `include` (embedded languages)
   can leave `extensions` empty.
3. Run the tests (see below). `Tests/highlight/run_tests.gd` loads every
   manifest entry, so a broken grammar shows up immediately.

To keep a language on the old Lua highlighter instead, simply do not add a
manifest entry: unknown extensions fall back to `tm_fallback.gd`, which uses
the `highlight()` / `highlight_region()` calls from `Lua/Plugins/*.lua`.

## Themes

Existing themes keep working unchanged. `TMTheme.from_categories()` maps the
eleven legacy color categories (`reserved`, `string`, `comments`, …) onto
TextMate scopes:

| Scope selector | Category |
| --- | --- |
| `comment` | comments |
| `string` | string |
| `constant.numeric`, `constant.language` | binary |
| `constant.character.escape`, `keyword.operator` | operator |
| `keyword`, `storage`, `entity.name.tag` | reserved |
| `entity.name.function`, `support.function` | function |
| `entity.name.type`, `entity.other.attribute-name` | annotation |
| `variable.other.property`, `meta.object-literal.key` | member |
| `variable`, `variable.parameter` | variable |
| `punctuation`, `meta.brace` | symbol |
| `invalid` | error |

Rules declared later win ties, which is why `string`/`comment` are listed last:
they also color the punctuation inside strings and comments.

## Limitations

- **Color only.** `SyntaxHighlighter` in Godot returns `{column: {"color": …}}`;
  italic/bold per token is not supported by the engine. Comments cannot be
  italic.
- **No injections.** `injections` / `injectionSelector` grammars are ignored, so
  fenced code blocks inside Markdown stay plain. Cross grammar `include`s
  (HTML `<style>` / `<script>`, C++ embedded macros) do work.
- **No embedded language ids / token types.** Only colors are produced, which is
  enough for highlighting but not for bracket colorization.
- **Regex dialect.** Godot uses PCRE2; TextMate grammars assume Oniguruma.
  Patterns that fail to compile are disabled and logged. Back references in
  `end` patterns (`end: "(\\3)"` in MagicPython) are resolved against the begin
  match, the way TextMate does it.
- **Anchors.** `\G` only matches at TextMate's anchor position and `\A` only on
  the first line, matching VS Code semantics.
- **Long lines.** Lines over 20 000 characters are not tokenized.
- **Big states.** More than 400 alternatives for one state switches to the
  sequential scanner (slower but correct).

## Debugging

Set `TM_DEBUG=1` to print every match the tokenizer takes (rule, span, state
depth):

```sh
TM_DEBUG=1 godot --path . Tests/highlight/fixtures/sample.py
```

Tests and benchmark (2 000 lines of Python, roughly 4 500 lines/s on an Apple
M5):

```sh
godot --headless --path . --script res://Tests/highlight/run_tests.gd
```

`Tests/highlight/run_tests.gd` exits with the number of failed checks and
covers the theme bridge, the engine on a minimal grammar, MagicPython, backend
parity, the fallback, the Godot integration and every shipped grammar.

## Licensing

The grammars come from the VS Code repository (MIT). See
`Grammars/ThirdPartyNotices.md`.
