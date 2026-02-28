# Goose Operating Rules for This Repository

These rules are mandatory for all Goose sessions operating in this repository.

## Core Principle

Never rewrite entire files unless explicitly instructed.
All changes must be minimal, targeted, and verifiable via git diff.

---

## File Modification Policy

1. Do NOT use Developer.textEditor.write to rewrite full file contents.
2. Do NOT output:
   - Line numbers (e.g. "1: ")
   - File path headers (e.g. "### /path/to/file")
   - Markdown fences (``` blocks)
   - Any annotations or commentary inside source files.
3. Only write raw source code content when modifying files.
4. Prefer surgical edits over full rewrites.
5. Only use Developer.shell for modifications.

---

## Approved Modification Methods

When changing code, use one of the following:

A) Shell-based in-place edits (preferred for simple refactors)
   Example:
     perl -pi -e 's/\bOldName\b/NewName/g' path/to/file.pm

B) Unified diff patches applied via git:
   - Generate a proper unified diff.
   - Apply using:
       git apply --check patch.diff
       git apply patch.diff

C) Minimal targeted editor updates (only if necessary),
   and only if they do NOT involve rewriting the entire file.

---

## Mandatory Post-Change Verification

After any modification:

1. Run:
       git diff
2. Ensure only the intended lines changed.
3. Run repository validation scripts if present.
4. Do NOT commit automatically unless explicitly instructed.

If unrelated formatting changes appear, abort and revert.

---

## Absolute Prohibitions

- Never rewrite files from numbered displays.
- Never copy display-format output back into source files.
- Never introduce formatting that was not explicitly requested.
- Never add or remove whitespace except where required by the change.
- You are not allowed to use Developer.textEditor under any circumstances.

---

## Failure Handling

If a patch fails to apply:
- Do NOT guess.
- Re-read the current file content.
- Regenerate a correct patch against the actual file state.

If in doubt, stop and request clarification.

---

These rules override default Goose behavior.
