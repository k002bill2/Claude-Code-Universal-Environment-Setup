#!/bin/bash
# QA 재검증 추가 사례 — FIX f83a3d1. 사용: bash recheck.sh <repo-root>
# 실제 HOME 미사용: install.sh 는 전부 HOME=mktemp 샌드박스. 실제 ~/.claude 는 find 로 읽기만.
# repro.sh 와 동시에 돌리지 말 것(서로의 sleep 4x 를 pkill 한다).
set -uo pipefail
R="$1"
. "$R/tests/helpers.sh"
init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
S="$SANDBOX_ROOT"
echo "SANDBOX=$S"
now() { python3 -c 'import time;print("%.2f"%time.time())'; }
mk() { mkdir -p "$1"; printf '%s' "$2" > "$1/claude"; chmod +x "$1/claude"; }
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
  e=$(grep -Ei 'unbound|syntax error|value too great|invalid arithmetic|invalid time|Killed' "$S/$n.out" | head -1)
  sleep 0.3; left=$(pgrep -f 'sleep 4[45]$' | wc -l | tr -d ' ')
  printf '%-18s rc=%s sec=%s warn=%s parsefail=%s hang=[%s] left=%s err=[%s] done=%s\n' \
    "$n" "$rc" "$(python3 -c "print('%.1f'%($t1-$t0))")" "$w" "$p" "$h" "$left" "$e" "$(grep -c '설치 완료\|DRY RUN' "$S/$n.out")"
  pkill -9 -f 'sleep 4[45]$' 2>/dev/null; true
}
C=(-- --dry-run --components commands)
echo "== R2. M-1 추가: TERM 무시 + 자식 (CLAUDE_VERSION_TIMEOUT=1, 목표 <= 3.0초, 잔존 0)"
TRAPCHILD='#!/bin/bash
trap "" TERM; sleep 44 & sleep 45; wait'
run sys_trapchild "$TRAPCHILD" "$P_SYS" CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run gt_trapchild  "$TRAPCHILD" "$P_GT"  CLAUDE_VERSION_TIMEOUT=1 "${C[@]}"
run fb_trapchild  "$TRAPCHILD" "$P_DEF" CLAUDE_VERSION_TIMEOUT=1 CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
echo "-- 경로 확인"
PATH="$S/sys_trapchild-bin:$S/shims:$P_SYS" /bin/bash -c 'command -v timeout; command -v gtimeout || echo "gtimeout: none"'
PATH="$S/gt_trapchild-bin:$S/shims:$P_GT" /bin/bash -c 'command -v timeout || echo "timeout: none"; command -v gtimeout'
echo "== R3. 정규화 경계 (fake: sleep 7; echo 2.1.330 — 실효 5초면 hang(5초), 300이면 7초 후 정상)"
SLOW7='#!/bin/bash
sleep 7; echo "2.1.330 (Claude Code)"'
for v in 1 300 301 000 0300 -1 " 5"; do
  run "n_tool_[$v]" "$SLOW7" "$P_DEF" "CLAUDE_VERSION_TIMEOUT=$v" "${C[@]}"
  run "n_fb_[$v]"   "$SLOW7" "$P_DEF" "CLAUDE_VERSION_TIMEOUT=$v" CC_VERSION_FORCE_BASH_TIMEOUT=1 "${C[@]}"
done
echo "== R4. I-3 v 접두 경계 (install.sh 통합 실행 + _pick_claude_version 직접 호출)"
E='#!/bin/bash
echo "'; T='"'
run i3_rev   "${E}rev2.1.100 2.1.330${T}" "$P_DEF" "${C[@]}"
run i3_v     "${E}v2.1.292${T}" "$P_DEF" "${C[@]}"
run i3_paren "${E}(v2.1.292)${T}" "$P_DEF" "${C[@]}"
run i3_dev   "${E}dev2.1.300${T}" "$P_DEF" "${C[@]}"
# 함수 본문만 추출해 평가(install.sh 본체는 실행하지 않음)
eval "$(sed -n '/^_pick_claude_version() {/,/^}/p' "$R/install.sh")"
for s in "rev2.1.100 2.1.330" "v2.1.292" "(v2.1.292)" "dev2.1.300" "release 3.0.0 v2.1.292" "x v2.1.292 1.0.0"; do
  printf 'pick [%s] -> %s\n' "$s" "$(_pick_claude_version "$s")"
done
echo "== R5. 실제 ~/.claude 무변경 (마커 → install.sh HOME=샌드박스 → find -newer)"
REAL="$HOME/.claude"
mkdir -p "$S/r5-home" "$S/r5-proj"
M="$S/r5.marker"; touch "$M"; sleep 1.1
HOME="$S/r5-home" PATH="$S/shims:$PATH" /bin/bash "$R/install.sh" --project "$S/r5-proj" --profile core > "$S/r5.out" 2>&1 < /dev/null
echo "r5 install rc=$? sandbox files=$(find "$S/r5-home" -type f | wc -l | tr -d ' ')"
find "$REAL" -newer "$M" -print 2>/dev/null > "$S/r5.changed"
echo "real ~/.claude changed paths during run: $(wc -l < "$S/r5.changed" | tr -d ' ')"
sed "s|^$REAL|~/.claude|" "$S/r5.changed" | head -40
# 설치기 산출물 이름과의 교집합: 샌드박스 HOME/.claude 에 생긴 상대경로 집합 vs 실제 변경 상대경로
( cd "$S/r5-home/.claude" && find . -print | sed 's|^\./||' | sort ) > "$S/r5.installer"
sed "s|^$REAL/\{0,1\}||" "$S/r5.changed" | sed '/^$/d' | sort > "$S/r5.rel"
echo "installer-output top-level: $(cut -d/ -f1 "$S/r5.installer" | sort -u | tr '\n' ' ')"
echo "intersection (changed ∩ installer paths): $(comm -12 "$S/r5.rel" "$S/r5.installer" | wc -l | tr -d ' ')"
comm -12 "$S/r5.rel" "$S/r5.installer" | head -20
echo "S=$S"
