#!/bin/sh
set -eu

# Reject common corruption patterns in lib/
# - markdown fences
# - file headers like "### /path/file"
# - line-number prefixes like "123: "
if grep -R -n -E '^(###\s+/|```|[0-9]+:\s)' lib/ >/dev/null 2>&1; then
	echo "Error: Detected Goose-style corruption in lib/ (headers, fences, or line numbers)."
	exit 1
fi

exit 0
