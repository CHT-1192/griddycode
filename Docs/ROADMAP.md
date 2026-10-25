# Roadmap

## Long-term goal: a Neovim with effects

Grow GriddyCode into a keyboard-driven, hackable editor that can actually be
someone's daily driver — while keeping the thing no other editor has: a
world-space UI where every page is made of lines and the camera is the
transition.

"Neovim" here means the *editing* half: files, buffers, search, language
intelligence, keymaps, a plugin surface. "With effects" is the half that
already exists and must survive every change below.

## Where we are (2026-10)

**Present**
- Text surface: Godot's `CodeEdit` (cursor, selection, undo/redo, auto-indent
  come from the engine, not from us).
- Highlighting: TextMate grammars, 14 languages, progressive warmup, per-line
  cache (`Docs/HIGHLIGHTING.md`).
- World-space UI with camera framing: file picker, settings, comments, notices.
- Lua for language definitions and themes; 15 langs, 18 themes.
- Presentation layer: 5 shaders, music-reactive camera, Discord presence.

**Missing for daily use**
- Project search, multi-buffer editing, split view.
- LSP (diagnostics, completion, hover, go-to-definition); completion today is
  a per-language Lua regex pass over the current buffer.
- Configurable keymaps and modes; keys are hardcoded `Input.is_action_*` calls.
- File operations (create/rename/delete), save-all, reload on external change.
- Session restore beyond the single last file.

## Principles

1. **Everything is still a line.** New panels should live in the world and be
   framed by the camera, not by a scrollbar.
2. **The camera is the transition.** No slide / fade animations fighting the
   camera (see the settings page decision).
3. **Keep the text surface.** Do not write a text buffer; stay on `CodeEdit`
   and accept its limits until they actually block a feature.
4. **Lua stays the mod layer.** Anything users are expected to tweak (langs,
   themes, eventually keymaps) should be reachable from Lua.
5. **Large files are a first-class case.** Any new feature must keep the
   "first frame in milliseconds, fill in the background" property.

## Milestones

**M1 — Project search** (highest value, lowest risk)
A world-space search panel: query, file list with match counts, jump to match.
Ripgrep-style scan on a `Thread`, results streamed in. Acceptance: searching a
7 000-line project returns the first results under 200 ms and never blocks a
frame.

**M2 — Buffers and splits**
Open several files at once, switch with a world-space buffer list, optional
side-by-side split. Per-buffer cursor/scroll state. Acceptance: switching
buffers keeps highlighting warm and does not re-tokenize the whole file.

**M3 — LSP client**
JSON-RPC over stdio/TCP to a language server per project; diagnostics in the
gutter, completion and hover in the editor, go-to-definition as a camera move.
This replaces the Lua completion hacks. Acceptance: `pyright` (or `clangd`)
attaches, diagnostics appear, completion works on a 2 000-line file without
dropping frames.

**M4 — Keymaps and modes**
A keymap file (Lua) mapping actions to keys, plus an optional modal layer
(normal/insert) for people who want Vim muscle memory. Every hardcoded
`Input.is_action_*` becomes an action. Acceptance: remapping open/save/close
works from Lua without touching GDScript.

**M5 — File and session management**
Create/rename/delete from the picker, save-all, detect external modifications,
restore open buffers and cursors on start.

## Non-goals

- Building an IDE: no debugger, no integrated terminal, no VCS client in the
  first pass. (A debug adapter could come later, but it is not what makes this
  an editor.)
- Rewriting the text buffer or the rendering path.
- Chasing every VS Code feature; the differentiator is the presentation and
  the hackability, not feature parity.

## Open questions

- Modal editing: opt-in layer on top of the current key handling, or a real
  mode system that changes what the editor does?
- How much of the world-space UI survives once there are splits — does each
  split get its own camera?
- Do we keep Lua completion as a fallback once LSP exists, or delete it?
