#!/bin/bash
# QA repro — cc-version-hardening. 사용: bash repro.sh <repo-root>
# 실제 HOME 미사용: 모든 실행은 init_sandbox 의 mktemp HOME/프로젝트.
set -uo pipefail
R="$1"
. "$R/tests/helpers.sh"
init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
S="$SANDBOX_ROOT"
echo "SANDBOX=$S"
REAL_SNAP=$(ls -la "$HOME/.claude" 2>/dev/null | md5)
now() { python3 -c 'import time;print("%.2f"%time.time())'; }
mk() { mkdir -p "$1"; printf '%s' "$2" > "$1/claude"; chmod +x "$1/claude"; }
# PATH 변형용 디렉터리: 시스템/홈브루 도구 심볼릭 링크(특정 이름 제외)
mkpathdir() { # dir exclude-regex
  mkdir -p "$1"
  for d in /opt/homebrew/bin /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do b=$(basename "$f"); echo "$b" | grep -Eq "$2" && continue
      [ -e "$1/$b" ] || ln -s "$f" "$1/$b"; done
  done
}
mkpathdir "$S/p_sys" '^g?timeout$'; ln -s /usr/bin/timeout "$S/p_sys/timeout"
mkpathdir "$S/p_gt" '^timeout$'
P_SYS="$S/p_sys"; P_GT="$S/p_gt"; P_DEF="$PATH"
run() { # name body basepath extra-env... -- args...
  local n="$1" body="$2" bp="$3"; shift 3
  local envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  mkdir -p "$S/$n-home" "$S/$n-proj"; mk "$S/$n-bin" "$body"
  local t0 t1; t0=$(now)
  env ${envs[@]+"${envs[@]}"} HOME="$S/$n-home" PATH="$S/$n-bin:$S/shims:$bp" /bin/bash "$R/install.sh" --project "$S/$n-proj" "$@" > "$S/$n.out" 2>&1 < /dev/null
  local rc=$?; t1=$(now)
  local w p h e left
  w=$(grep -c '최소 2.1.293' "$S/$n.out"); p=$(grep -c '버전을 읽지 못' "$S/$n.out")
  h=$(grep -o '응답 없음([^)]*)' "$S/$n.out" | head -1)
  e=$(grep -Ei 'unbound|syntax error|value too great|invalid arithmetic|invalid time' "$S/$n.out" | head -1)
  left=$(pgrep -f 'sleep (4[1-9]|3[0-9])$' | wc -l | tr -d ' ')
  printf '%-16s rc=%s sec=%s warn=%s parsefail=%s hang=[%s] left=%s err=[%s] done=%s\n' \
    "$n" "$rc" "$(python3 -c "print('%.1f'%($t1-$t0))")" "$w" "$p" "$h" "$left" "$e" "$(grep -c '설치 완료\|DRY RUN' "$S/$n.out")"
  pkill -f 'sleep (4[1-9]|3[0-9])$' 2>/dev/null; true
}
E='#!/bin/bash
echo "'; T='"'
C=(-- --dry-run --components commands)
echo "== 1. L-1 대조표 (기본 PATH)"
run tdate  "${E}built 2026.11.22 version 2.1.292${T}" "$P_DEF" "${C[@]}"
run tbuild '#!/bin/bash
echo "build 2026.11.22"
echo "2.1.330 (Claude Code)"' "$P_DEF" "${C[@]}"
run trel   "${E}release 3.0.0 v2.1.292${T}" "$P_DEF" "${C[@]}"
run tbeta  "${E}2.1.292-beta.1 (Claude Code)${T}" "$P_DEF" "${C[@]}"
run t1234  "${E}claude 12.3.4${T}" "$P_DEF" "${C[@]}"
run t1000  "${E}10.0.0 (Claude Code)${T}" "$P_DEF" "${C[@]}"
run tafter "${E}2.1.330 (Claude Code) built 2026.01.01${T}" "$P_DEF" "${C[@]}"
run tdev   "${E}dev2.1.300${T}" "$P_DEF" "${C[@]}"
run tempty '#!/bin/bash
exit 0' "$P_DEF" "${C[@]}"
echo "== 1b. 이전 QA 19사례 회귀"
run t292   "${E}2.1.292 (Claude Code)${T}" "$P_DEF" "${C[@]}"
run t293   "${E}2.1.293 (Claude Code)${T}" "$P_DEF" "${C[@]}"
run t2129  "${E}2.1.29 (Claude Code)${T}" "$P_DEF" "${C[@]}"
run tv292  "${E}v2.1.292${T}" "$P_DEF" "${C[@]}"
run t000   "${E}0.0.0${T}" "$P_DEF" "${C[@]}"
run tmulti '#!/bin/bash
echo "Claude Code CLI"
echo "build 2.1.300 (Claude Code)"' "$P_DEF" "${C[@]}"
run tmulti2 '#!/bin/bash
echo "Claude Code CLI"
echo "version 2.1.100"' "$P_DEF" "${C[@]}"
run t4f    "${E}2.1.293.1${T}" "$P_DEF" "${C[@]}"
run t4flow "${E}2.1.292.9${T}" "$P_DEF" "${C[@]}"
run t0lead "${E}2.01.300${T}" "$P_DEF" "${C[@]}"
run t08    "${E}2.1.08${T}" "$P_DEF" "${C[@]}"
run tbig   "${E}99999999999999999999.0.0${T}" "$P_DEF" "${C[@]}"
run texit1 '#!/bin/bash
echo "2.1.292"; exit 1' "$P_DEF" "${C[@]}"
run texit1n '#!/bin/bash
exit 1' "$P_DEF" "${C[@]}"
run tstderr '#!/bin/bash
echo "2.1.292" >&2' "$P_DEF" "${C[@]}"
run thang  '#!/bin/bash
read x' "$P_DEF" "${C[@]}"
echo "== 2. L-2 타임아웃: 경로 3종 x (자식+멈춤 / TERM 무시)"
CHILD='#!/bin/bash
sleep 41 & sleep 42; wait'
TRAP='#!/bin/bash
trap "" TERM; sleep 43'
run sys_child  "$CHILD" "$P_SYS" CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run gt_child   "$CHILD" "$P_GT"  CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run fb_child   "$CHILD" "$P_DEF" CLAUDE_VERSION_TIMEOUT=1 CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
run sys_trap   "$TRAP" "$P_SYS" CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run gt_trap    "$TRAP" "$P_GT"  CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run fb_trap    "$TRAP" "$P_DEF" CLAUDE_VERSION_TIMEOUT=1 CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
echo "-- 경로 확인(sys/gt 에서 어떤 timeout 이 잡히는가)"
PATH="$S/sys_child-bin:$S/shims:$P_SYS" command -v timeout gtimeout
PATH="$S/gt_child-bin:$S/shims:$P_GT" /bin/bash -c 'command -v timeout || echo "timeout: none"; command -v gtimeout'
echo "== 2b. CLAUDE_VERSION_TIMEOUT 값 (fake: sleep 39; echo 2.1.292)"
SLOW='#!/bin/bash
sleep 39; echo 2.1.292'
for v in 1 0 abc -3 "" 00 08 99999999999999999999; do
  run "v_tool_[$v]" "$SLOW" "$P_DEF" "CLAUDE_VERSION_TIMEOUT=$v" "${C[@]}"
  run "v_fb_[$v]"   "$SLOW" "$P_DEF" "CLAUDE_VERSION_TIMEOUT=$v" CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
done
echo "== 2c. 경계: 타임아웃 1초 vs sleep 0.5 (3회 x 경로 3종)"
EDGE='#!/bin/bash
sleep 0.5; echo 2.1.292'
for k in 1 2 3; do
  run "e_sys$k" "$EDGE" "$P_SYS" CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
  run "e_gt$k"  "$EDGE" "$P_GT"  CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
  run "e_fb$k"  "$EDGE" "$P_DEF" CLAUDE_VERSION_TIMEOUT=1 CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
done
echo "== 3. 실제 claude --dry-run smoke (샌드박스 HOME)"
mkdir -p "$S/real-home" "$S/real-proj"
t0=$(now); HOME="$S/real-home" PATH="$S/shims:$PATH" /bin/bash "$R/install.sh" --project "$S/real-proj" --dry-run --profile core > "$S/real.out" 2>&1 < /dev/null; rc=$?; t1=$(now)
echo "real: claude=$(claude --version) rc=$rc sec=$(python3 -c "print('%.1f'%($t1-$t0))") warn=$(grep -c '최소 2.1.293\|응답 없음\|버전을 읽지 못' "$S/real.out")"
t0=$(now); _o=$(claude --version </dev/null); t1=$(now); echo "claude --version 단독: $(python3 -c "print('%.2f'%($t1-$t0))")s"
echo "== 4. 버전 미달 vs 정상 --profile core 바이트 비교"
run dlow  "${E}2.1.292 (Claude Code)${T}" "$P_DEF" -- --profile core
run dhigh "${E}2.1.330 (Claude Code)${T}" "$P_DEF" -- --profile core
( cd "$S" && diff -r dlow-proj dhigh-proj >/dev/null && echo "proj diff: IDENTICAL" || { echo "proj diff:"; diff -r dlow-proj dhigh-proj | head -20; } )
( cd "$S" && diff -r dlow-home dhigh-home >/dev/null && echo "home diff: IDENTICAL" || { echo "home diff:"; diff -r dlow-home dhigh-home | head -20; } )
echo "files home=$(find "$S/dlow-home" -type f | wc -l) proj=$(find "$S/dlow-proj" -type f | wc -l)"
echo "== 잔존 tmp (mktemp 누수 확인: claude --version 결과 임시파일 내용 2.1.292 포함 파일)"
grep -l '^2.1.292$' "${TMPDIR:-/tmp}"/tmp.* 2>/dev/null | wc -l
[ "$(ls -la "$HOME/.claude" 2>/dev/null | md5)" = "$REAL_SNAP" ] && echo "REAL ~/.claude top-level listing unchanged" || echo "REAL ~/.claude listing CHANGED"
echo "S=$S"
