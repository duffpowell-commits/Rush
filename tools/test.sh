#!/bin/sh
# Runs this repo's tests (test_cmd in .claude/hooks/guard.cfg) on the working tree and, if they
# pass, records the tree's hash so the push guard (.claude/hooks/guard.py) lets the push through.
# Usage: tools/test.sh   (from the repo root, or any folder inside it)
cd "$(git rev-parse --show-toplevel)" || exit 1
CMD=$(sed -n 's/^test_cmd *= *//p' .claude/hooks/guard.cfg)
PASS=$(sed -n 's/^pass_line *= *//p' .claude/hooks/guard.cfg)
[ -z "$CMD" ] && { echo "no test_cmd in .claude/hooks/guard.cfg"; exit 0; }
LOG=$(mktemp); RC=$(mktemp)
( XDG_DATA_HOME=${XDG_DATA_HOME:-$(mktemp -d)} sh -c "$CMD"; echo $? > "$RC" ) 2>&1 | tee "$LOG"
STATUS=$(cat "$RC"); rm -f "$RC"
if [ -n "$PASS" ] && ! grep -qE "$PASS" "$LOG"; then STATUS=1; fi
if grep -q "SCRIPT ERROR" "$LOG"; then STATUS=1; fi
rm -f "$LOG"
if [ "$STATUS" -ne 0 ]; then echo "TESTS FAILED: push stays blocked"; exit 1; fi
# Hash of the working tree as it is now (tracked + new files), without touching the real index.
IDX=$(mktemp); cp "$(git rev-parse --git-dir)/index" "$IDX" 2>/dev/null
TREE=$(GIT_INDEX_FILE=$IDX git add -A >/dev/null 2>&1 && GIT_INDEX_FILE=$IDX git write-tree)
rm -f "$IDX"
mkdir -p .claude/state && echo "$TREE" > .claude/state/tests_pass
echo "TESTS PASS: tree $TREE recorded; commit exactly this and push"
