#!/bin/sh
# Percentage of tracked source that is Jac, by bytes (roughly what GitHub's language
# bar computes). Judges require >= 40% Jac. Run at 02:00 and before submitting.
cd "$(dirname "$0")/.." || exit 1
jac=$(git ls-files | grep -E '\.jac$' | xargs -r wc -c | tail -1 | awk '{print $1}')
all=$(git ls-files | grep -E '\.(jac|js|jsx|ts|tsx|py|css|html|sh)$' | xargs -r wc -c | tail -1 | awk '{print $1}')
[ "$all" -gt 0 ] || { echo "no code files tracked"; exit 1; }
pct=$((jac * 100 / all))
echo "Jac: $jac bytes / code: $all bytes = ${pct}%"
[ "$pct" -ge 40 ] && echo "OK (>= 40%)" || echo "BELOW 40% — move logic into .jac"
