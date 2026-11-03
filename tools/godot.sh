#!/usr/bin/env bash
# Runs Godot 4.6.1 (Linux, official build) with the given args, downloading and
# SHA-512-verifying it on first use. For Linux; on Windows use the console exe
# directly (see DEVELOPMENT.md).
#   tools/godot.sh --headless --path . --import
set -euo pipefail
VERSION="4.6.1-stable"
NAME="Godot_v${VERSION}_linux.x86_64"
DIR="${GODOT_CACHE:-$HOME/.cache/godot}/${VERSION}"
BIN="$DIR/$NAME"
if [[ ! -x "$BIN" ]]; then
	mkdir -p "$DIR"
	BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"
	echo "tools/godot.sh: downloading $NAME ..." >&2
	curl -fsSL -o "$DIR/$NAME.zip" "$BASE/$NAME.zip"
	curl -fsSL -o "$DIR/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
	(cd "$DIR" && grep " $NAME.zip\$" SHA512-SUMS.txt | sha512sum -c - >&2)
	unzip -oq "$DIR/$NAME.zip" -d "$DIR"
	rm -f "$DIR/$NAME.zip"
	chmod +x "$BIN"
fi
exec "$BIN" "$@"
