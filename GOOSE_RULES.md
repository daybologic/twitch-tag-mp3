When writing files:
  * Output raw file content only.
  * Do not include line numbers.
  * Do not include file path headers.
  * Do not include markdown code fences.
  * Do not include annotations.
  * Use minimal diffs or targeted edits when possible.
  * Never rewrite entire files unless explicitly instructed.

Policy:
  * never use Developer.textEditor.write.
  * Only modify files via Developer.shell using git apply or in-place commands.
  * Always show git diff after modifications.
