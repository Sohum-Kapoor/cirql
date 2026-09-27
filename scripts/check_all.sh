#!/usr/bin/env bash
# Run `jac check` on every Jac file and `jac test` on every server module, in THIS
# checkout (use a worktree, never the directory a `jac start` is serving: plain
# `test` blocks persist nodes into ./.jac/data). Prints one line per module and a
# summary; exit 1 on any failure.
set -u
cd "$(dirname "$0")/.."
export PATH="$PWD/.venv/bin:${CIRQL_VENV:-/Users/sohum/Downloads/cirql/.venv/bin}:$PATH"
fail=0
echo "== jac check"
if ! jac check main.jac $(ls *.sv.jac *.test.jac) 2>&1 | grep -E '^=+ .*(passed|failed)' ; then fail=1; fi
jac check main.jac $(ls *.sv.jac *.test.jac) 2>&1 | grep -q ' failed' && fail=1
echo "== jac test (one module at a time)"
for m in $(ls *.sv.jac | sed 's/\.sv\.jac$//'); do
  [ -f "$m.test.jac" ] || continue
  out=$(jac test "$m.sv.jac" 2>&1)
  ran=$(echo "$out" | grep -E '^Ran ' | tail -1)
  if echo "$out" | grep -qE '^OK'; then printf '%-14s OK   %s\n' "$m" "$ran"; else printf '%-14s FAIL %s\n' "$m" "$ran"; echo "$out" | grep -E 'FAIL:|Error|AssertionError' | head -5; fail=1; fi
done
[ $fail -eq 0 ] && echo "ALL GREEN" || echo "FAILURES"
exit $fail
