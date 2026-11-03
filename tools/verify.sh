#!/usr/bin/env bash
# Full check: import (parse errors), headless tests, 48 h soak. Prints a short report
# and exits non-zero on any ERROR/WARNING line or test failure. Logs go to $LOG_DIR.
#   tools/verify.sh            # all three
#   tools/verify.sh soak       # one or more of: import test soak
set -uo pipefail
cd "$(dirname "$0")/.."
G=tools/godot.sh
LOG_DIR="${LOG_DIR:-${TMPDIR:-/tmp}/dogz3d-verify}"
mkdir -p "$LOG_DIR"
STEPS="${*:-import test soak}"
FAIL=0

check_log() {
	local name="$1" log="$2"
	local bad
	bad=$(grep -E "ERROR|WARNING" "$log" || true)
	if [[ -n "$bad" ]]; then
		echo "[$name] ERROR/WARNING lines:"
		echo "$bad" | head -20
		FAIL=1
	fi
}

for step in $STEPS; do
	case "$step" in
		import)
			$G --headless --path . --import > "$LOG_DIR/import.log" 2>&1 || FAIL=1
			check_log import "$LOG_DIR/import.log"
			echo "[import] done"
			;;
		test)
			$G --headless --fixed-fps 60 --path . -- --fresh --no-save --seed=42 --test=all \
				> "$LOG_DIR/test.log" 2>&1 || FAIL=1
			check_log test "$LOG_DIR/test.log"
			grep -E "^(FAIL|Tests:)" "$LOG_DIR/test.log" || { echo "[test] no summary"; FAIL=1; }
			;;
		soak)
			$G --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 \
				--quit-after-hours=48 --autofeed --autopet --seed=42 --log \
				> "$LOG_DIR/soak.log" 2>&1 || FAIL=1
			check_log soak "$LOG_DIR/soak.log"
			grep -A5 "=== Soak summary" "$LOG_DIR/soak.log" || { echo "[soak] no summary"; FAIL=1; }
			;;
		*)
			echo "unknown step: $step"
			FAIL=1
			;;
	esac
done
if [[ $FAIL -eq 0 ]]; then
	echo "VERIFY OK"
else
	echo "VERIFY FAILED (logs in $LOG_DIR)"
fi
exit $FAIL
