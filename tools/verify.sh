#!/usr/bin/env bash
# Full check: import (parse errors), headless tests, 48 h one-dog soak and 48 h 12-dog
# pack soak, both compared with their exact seed-42 baselines. Prints a short report and
# exits non-zero on any ERROR/WARNING line, test failure or baseline change. Logs go to
# $LOG_DIR.
#   tools/verify.sh            # all four
#   tools/verify.sh soak       # one or more of: import test soak pack pack30
# pack30 (30 dogs, 2 bowl pairs, about 45 s) is not in the default run; it checks errors
# and prints needs and frame time.
#
# A baseline change fails the run. If the change is intended (new tuning), update the
# baseline below and in docs/m2_pack.md, and say why in the commit.
set -uo pipefail
cd "$(dirname "$0")/.."
G=tools/godot.sh
# A script error can leave Godot running instead of quitting; cap every run.
T="timeout --kill-after=10 ${VERIFY_TIMEOUT:-300}"
LOG_DIR="${LOG_DIR:-${TMPDIR:-/tmp}/dogz3d-verify}"
mkdir -p "$LOG_DIR"
STEPS="${*:-import test soak pack}"
FAIL=0
# Behavior choice counts, name=count sorted by name (Godot 4.6.1 Linux headless, seed 42).
SOAK_BASELINE="drink=11 eat=9 idle=90 sleep=5 wander=24"
PACK_BASELINE="drink=48 eat=57 greet=242 idle=656 play_together=266 sleep=97 wait_turn=106 wander=174"

# "Behavior choices: { &"idle": 90, ... }" -> "idle=90 ..." sorted by name.
choices() {
	grep -m1 "^Behavior choices" "$1" | grep -oE '&"[a-z_]+": [0-9]+' \
		| sed -E 's/&"([a-z_]+)": ([0-9]+)/\1=\2/' | sort | paste -sd' ' -
}

check_baseline() {
	local name="$1" log="$2" expected="$3" got
	got=$(choices "$log")
	if [[ "$got" != "$expected" ]]; then
		echo "[$name] BASELINE CHANGED"
		echo "  expected: $expected"
		echo "  got:      $got"
		FAIL=1
	fi
}

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
			$T $G --headless --path . --import > "$LOG_DIR/import.log" 2>&1 || FAIL=1
			check_log import "$LOG_DIR/import.log"
			echo "[import] done"
			;;
		test)
			$T $G --headless --fixed-fps 60 --path . -- --fresh --no-save --seed=42 --test=all \
				> "$LOG_DIR/test.log" 2>&1 || FAIL=1
			check_log test "$LOG_DIR/test.log"
			grep -E "^(FAIL|Tests:)" "$LOG_DIR/test.log" || { echo "[test] no summary"; FAIL=1; }
			;;
		soak)
			$T $G --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 \
				--quit-after-hours=48 --autofeed --autopet --seed=42 --log \
				> "$LOG_DIR/soak.log" 2>&1 || FAIL=1
			check_log soak "$LOG_DIR/soak.log"
			grep -A5 "=== Soak summary" "$LOG_DIR/soak.log" || { echo "[soak] no summary"; FAIL=1; }
			check_baseline soak "$LOG_DIR/soak.log" "$SOAK_BASELINE"
			;;
		pack)
			$T $G --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 \
				--quit-after-hours=48 --autofeed --autopet --seed=42 --dogs=12 \
				> "$LOG_DIR/pack.log" 2>&1 || FAIL=1
			check_log pack "$LOG_DIR/pack.log"
			grep -A4 "^Behavior choices" "$LOG_DIR/pack.log" | sed 's/^/[pack] /' \
				|| { echo "[pack] no summary"; FAIL=1; }
			check_baseline pack "$LOG_DIR/pack.log" "$PACK_BASELINE"
			;;
		pack30)
			$T $G --headless --fixed-fps 60 --path . -- --fresh --no-save --timescale=60 \
				--quit-after-hours=48 --autofeed --autopet --seed=42 --dogs=30 --bowls=2 \
				> "$LOG_DIR/pack30.log" 2>&1 || FAIL=1
			check_log pack30 "$LOG_DIR/pack30.log"
			grep -A4 "^Behavior choices" "$LOG_DIR/pack30.log" | sed 's/^/[pack30] /' \
				|| { echo "[pack30] no summary"; FAIL=1; }
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
