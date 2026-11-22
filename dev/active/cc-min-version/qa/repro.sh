#!/bin/bash
set -uo pipefail
R="$1"
. "$R/tests/helpers.sh"
init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
S="$SANDBOX_ROOT"
echo "SANDBOX=$S REALHOME=$HOME"
REAL_HOME_SNAP=$(ls -la "$HOME/.claude" 2>/dev/null | md5)
mk() { mkdir -p "$1"; printf '%s' "$2" > "$1/claude"; chmod +x "$1/claude"; }
run() { # name script-body args...
  local n="$1" body="$2"; shift 2
  mkdir -p "$S/$n-home" "$S/$n-proj"; mk "$S/$n-bin" "$body"
  HOME="$S/$n-home" PATH="$S/$n-bin:$S/shims:$PATH" bash "$R/install.sh" --project "$S/$n-proj" "$@" > "$S/$n.out" 2>&1 < /dev/null
  local rc=$?
  local w; w=$(grep -c '최소 2.1.293' "$S/$n.out"); local p; p=$(grep -c '버전을 읽지 못' "$S/$n.out")
  local e; e=$(grep -Ei 'unbound|syntax error|value too great|invalid arithmetic' "$S/$n.out" | head -1)
  printf '%-14s rc=%s warn=%s parsefail=%s err=[%s]\n' "$n" "$rc" "$w" "$p" "$e"
}
E='#!/bin/bash
echo "'
T='"'
run t292   "${E}2.1.292 (Claude Code)${T}" --components commands
run t293   "${E}2.1.293 (Claude Code)${T}" --components commands
run t1000  "${E}10.0.0 (Claude Code)${T}" --components commands
run t2129  "${E}2.1.29 (Claude Code)${T}" --components commands
run tv292  "${E}v2.1.292${T}" --components commands
run t000   "${E}0.0.0${T}" --components commands
run tempty '#!/bin/bash
exit 0' --components commands
run tmulti '#!/bin/bash
echo "Claude Code CLI"
echo "build 2.1.300 (Claude Code)"' --components commands
run tmulti2 '#!/bin/bash
echo "Claude Code CLI"
echo "version 2.1.100"' --components commands
run t4f    "${E}2.1.293.1${T}" --components commands
run t4flow "${E}2.1.292.9${T}" --components commands
run t0lead "${E}2.01.300${T}" --components commands
run t08    "${E}2.1.08${T}" --components commands
run tbig   "${E}99999999999999999999.0.0${T}" --components commands
run tdate  "${E}built 2026.11.22 version 2.1.292${T}" --components commands
run texit1 '#!/bin/bash
echo "2.1.292"; exit 1' --components commands
run texit1n '#!/bin/bash
exit 1' --components commands
run tstderr '#!/bin/bash
echo "2.1.292" >&2' --components commands
run thang  '#!/bin/bash
read x' --components commands
run pmin   "${E}2.1.292${T}" --profile minimal
run pcmd   "${E}2.1.292${T}" --components commands
run pdry   "${E}2.1.292${T}" --dry-run --components commands
# uninstall after install in same home/proj
mk "$S/pcmd-bin" "${E}2.1.292${T}"
HOME="$S/pcmd-home" PATH="$S/pcmd-bin:$S/shims:$PATH" bash "$R/install.sh" --project "$S/pcmd-proj" --uninstall --yes > "$S/unin.out" 2>&1 < /dev/null; echo "uninstall rc=$? warn=$(grep -c '최소 2.1.293' "$S/unin.out")"; tail -3 "$S/unin.out"
# byte-identical: low vs 2.1.330, profile minimal
run dlow  "${E}2.1.292${T}" --profile minimal
run dhigh "${E}2.1.330${T}" --profile minimal
# normalize sandbox path differences
( cd "$S" && diff -r dlow-proj dhigh-proj >/dev/null && echo "proj diff: IDENTICAL" || { echo "proj diff:"; diff -r dlow-proj dhigh-proj | head -20; } )
( cd "$S" && diff -r dlow-home dhigh-home >/dev/null && echo "home diff: IDENTICAL" || { echo "home diff:"; diff -r dlow-home dhigh-home | head -20; } )
echo "home files: $(find "$S/dlow-home" -type f | wc -l) proj files: $(find "$S/dlow-proj" -type f | wc -l)"
echo "-- t292 warn lines:"; grep -n '최소\|claude update' "$S/t292.out"
echo "-- tempty:"; grep -n '버전' "$S/tempty.out"
echo "-- pdry warn:"; grep -n '최소\|DRY RUN' "$S/pdry.out" | head
[ "$(ls -la "$HOME/.claude" 2>/dev/null | md5)" = "$REAL_HOME_SNAP" ] && echo "REAL ~/.claude listing unchanged"
echo "S=$S"
