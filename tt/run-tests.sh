#!/usr/bin/env bash
# Twitch MP3 tagger.
# Copyright (c) 2023-2026, Rev. Duncan Ross Palmer (2E0EOL)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
#     * Neither the name of the the maintainer, nor the names of its contributors
#       may be used to endorse or promote products derived from this software
#       without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

set -u # strict on undefined vars, but no `-e`

BASE_DIR="tt"

failures=()
total=0
passed=0
failed=0
skipped=0
notApplicable=0

# Ensure directory exists
if [[ ! -d "$BASE_DIR" ]]; then
	echo "⚠️ Directory '$BASE_DIR' does not exist." >&2
	exit 0
fi

# Find and execute .sh files
while IFS= read -r -d '' script; do
	(( total++ ))

	testName="${script#$BASE_DIR}"

	if [[ "$testName" =~ "run-tests.sh" ]]; then
		(( notApplicable++ ))

		echo "☑️     N/A: $testName"
	elif [ -x "$script" ]; then
		# Run the script in a subshell, so "exit" doesn’t kill the runner
		(
			cd "$BASE_DIR"
			"./${script#$BASE_DIR/}" >/dev/null 2>&1
		) < /dev/null # <-- critical fix: prevent script from reading find’s output
		status=$?

		if [[ $status -eq 0 ]]; then
			(( passed++ ))

			echo "✅ PASSED: $testName"
		else
			(( failed++ ))

			echo "❌ FAILED (exit $status): $testName"
			failures+=("$testName (exit $status)")
		fi
	else
		(( skipped++ ))

		echo "⚠️ SKIPPED: $testName"
	fi
done < <(find "$BASE_DIR" -maxdepth 1 -name "*.sh" -type f -print0)

echo "================================"
if (( failed > 0 )); then
	echo "Some tests failed:"
	for f in "${failures[@]}"; do
		echo " - $f"
	done
else
	echo "All tests passed successfully 🎉"
fi

# Final summary
echo "================================"
echo "Test Summary:"
echo "  Total  : $total"
echo "✅ Passed : $passed"
echo "☑️    N/A : $notApplicable"
echo "⚠️Skipped: $skipped"
echo "❌ Failed : $failed"
echo

if (( failed > 0 )); then
	exit 1
fi

exit 0
