#!/bin/bash
# ============================================================================
# tests/test-profiles.sh — git push 제거 회귀 + --profile minimal|core|full
# ----------------------------------------------------------------------------
# 실행: bash tests/test-profiles.sh
#
#   P0  push allow 제거 업그레이드 회귀 (jq 경로 + node 폴백)
#   P1~ 프로필 (BRIEF 필수 케이스 1~10)
#
# 격리: HOME 은 mktemp 샌드박스, npm/codex 는 exit 0 셔임. 실제 HOME 불변.
# 제약: macOS bash 3.2 호환, 모든 경로 인용.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
. "${REPO_DIR}/tests/helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 산출물 JSON 검증에 실제 jq 가 필요합니다" >&2
    exit 1
fi

init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"

PUSH='Bash(git push:*)'

# $1=repo $2=home, 나머지=install.sh 인자. 출력은 ${SANDBOX_ROOT}/last.out
run_inst() {
    local repo="$1" home="$2"; shift 2
    HOME="$home" bash "${repo}/install.sh" "$@" > "${SANDBOX_ROOT}/last.out" 2>&1
}

allow_has() {  # $1=settings $2=문자열
    jq -r '.permissions.allow[]?' "$1" 2>/dev/null | grep -qxF "$2"
}

# ── P0: push identity 업그레이드 제거 ───────────────────────────────────
# 구 fragment(push 포함)로 설치 → 신 fragment 로 재설치 → 설치기 소유 push 는 제거,
# 설치 전에 사용자가 넣어 둔 동일 문자열은 보존.
p0_case() {
    local tag="$1" runner="$2"
    local fx="${SANDBOX_ROOT}/p0-${tag}-repo" h="${SANDBOX_ROOT}/p0-${tag}-home"
    local pa="${SANDBOX_ROOT}/p0-${tag}-a" pb="${SANDBOX_ROOT}/p0-${tag}-b"
    local frag="${fx}/project/settings-fragments/cli-orchestration.json"
    make_fixture_repo "$fx"
    mkdir -p "$h" "$pa" "${pb}/.claude"
    cp "$frag" "${SANDBOX_ROOT}/p0-${tag}-new.json"
    jq '.permissions.allow += ["Bash(git push:*)"]' "${SANDBOX_ROOT}/p0-${tag}-new.json" > "$frag"
    # (b) 사용자가 설치 전에 같은 문자열을 넣어 둔 프로젝트
    printf '{"permissions":{"allow":["%s"]}}\n' "$PUSH" > "${pb}/.claude/settings.json"

    $runner run_inst "$fx" "$h" --project "$pa" || fail "P0[$tag] 구 fragment 설치 exit≠0"
    $runner run_inst "$fx" "$h" --project "$pb" || fail "P0[$tag] 구 fragment 설치(b) exit≠0"
    allow_has "${pa}/.claude/settings.json" "$PUSH" \
        && pass "P0[$tag] 구 fragment 설치 직후 push 존재(전제)" \
        || fail "P0[$tag] 구 fragment 설치에 push 없음(전제 깨짐)"

    cp "${SANDBOX_ROOT}/p0-${tag}-new.json" "$frag"
    $runner run_inst "$fx" "$h" --project "$pa" || fail "P0[$tag] 신 fragment 재설치 exit≠0"
    $runner run_inst "$fx" "$h" --project "$pb" || fail "P0[$tag] 신 fragment 재설치(b) exit≠0"
    allow_has "${pa}/.claude/settings.json" "$PUSH" \
        && fail "P0[$tag] (a) 업그레이드 후에도 설치기 소유 push allow 잔존" \
        || pass "P0[$tag] (a) 업그레이드가 설치기 소유 push allow 제거"
    allow_has "${pa}/.claude/settings.json" 'Bash(git pull:*)' \
        && pass "P0[$tag] 나머지 allow 유지" || fail "P0[$tag] 나머지 allow 소실"
    allow_has "${pb}/.claude/settings.json" "$PUSH" \
        && pass "P0[$tag] (b) 사용자가 먼저 넣은 push 문자열 보존" \
        || fail "P0[$tag] (b) 사용자 push 문자열이 지워짐"
}

direct() { "$@"; }
p0_case jq direct
if command -v node >/dev/null 2>&1; then
    p0_case node run_without_jq
else
    skip "P0[node] node 없음 — 폴백 경로 미검증"
fi


# ════════════════════════════════════════════════════════════════════════
# 프로필 (BRIEF 필수 케이스 1~10)
# ════════════════════════════════════════════════════════════════════════
R="$REPO_DIR"
newenv() {  # $1=tag → H_<tag>, P_<tag> 생성 (빈 HOME, 빈 프로젝트)
    mkdir -p "${SANDBOX_ROOT}/$1-home" "${SANDBOX_ROOT}/$1-proj"
}
H() { printf '%s' "${SANDBOX_ROOT}/$1-home"; }
P() { printf '%s' "${SANDBOX_ROOT}/$1-proj"; }
same_tree() {  # $1=dir $2=저장된 스냅샷 파일
    [ "$(snapshot_tree "$1")" = "$(cat "$2")" ]
}

# ── P1: minimal 산출물 + HOME 쓰기 0 ─────────────────────────────────────
newenv m
printf '{"name":"x","scripts":{"test":"jest","lint":"eslint .","build":"tsc"}}\n' > "$(P m)/package.json"
snapshot_tree "$(H m)" > "${SANDBOX_ROOT}/m-home.before"
run_inst "$R" "$(H m)" --profile minimal --project "$(P m)"; RC=$?
[ "$RC" -eq 0 ] && pass "P1 minimal exit 0" || { fail "P1 minimal exit ${RC}"; cat "${SANDBOX_ROOT}/last.out"; }
cp "${SANDBOX_ROOT}/last.out" "${SANDBOX_ROOT}/m.out"
same_tree "$(H m)" "${SANDBOX_ROOT}/m-home.before" \
    && pass "P1 minimal 샌드박스 HOME 트리 전·후 동일(메모리 시드 포함 쓰기 0)" \
    || fail "P1 minimal 이 HOME 에 썼음"
MS="$(P m)/.claude/settings.json"
if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(startswith("python3"))) | length >= 2' "$MS" >/dev/null 2>&1; then
    pass "P1 guardrails 병합됨"
else
    fail "P1 guardrails 미병합"
fi
[ "$(jq '[.permissions.allow[]?] | length' "$MS" 2>/dev/null)" = "0" ] \
    && pass "P1 settings allow 항목 0" || fail "P1 settings 에 allow 항목 존재"
[ -f "$(P m)/.claude/commands/verify-app.md" ] && pass "P1 verify-app.md 설치" || fail "P1 verify-app.md 없음"
[ -f "$(P m)/CLAUDE.md" ] && pass "P1 CLAUDE.md 골격 설치" || fail "P1 CLAUDE.md 없음"
[ "$(cat "$(P m)/.claude/.install-profile" 2>/dev/null)" = "profile=minimal" ] \
    && pass "P1 .install-profile = profile=minimal" || fail "P1 .install-profile 기록 이상"
for x in .claude/agents .claude/skills .claude/skill-rules.json .claude/hooks dev docs \
         .mcp.json.example .claude/commands/auto.md .claude/commands/check-health.md \
         .claude/settings-fragments; do
    [ -e "$(P m)/$x" ] && fail "P1 minimal 에 있으면 안 되는 산출물: $x" || pass "P1 없음: $x"
done
# 정확한 파일 집합 — system-setup 위임 산출물 등 숨은 쓰기까지 잡는다
M_FILES="$(cd "$(P m)" && find . -type f | LC_ALL=C sort | tr '\n' ' ')"
M_WANT="./.claude/.install-profile ./.claude/.settings-manifest ./.claude/commands/verify-app.md ./.claude/settings.json ./.manifest ./CLAUDE.md ./package.json "
[ "$M_FILES" = "$M_WANT" ] && pass "P1 minimal 파일 집합 정확" || fail "P1 minimal 파일 집합: [${M_FILES}]"
grep -q 'profile: minimal (explicit)' "${SANDBOX_ROOT}/m.out" \
    && pass "P1 요약 첫 줄 profile: minimal (explicit)" || fail "P1 요약 profile 표기 없음"
grep -q 'Global:' "${SANDBOX_ROOT}/m.out" && fail "P1 minimal 요약에 Global 줄" || pass "P1 요약에 Global 줄 없음"
grep -q 'Codex 플러그인\|PM2(--with-pm2)\|실행형 훅 4종' "${SANDBOX_ROOT}/m.out" \
    && fail "P1 minimal 체크리스트에 미실행 단계 안내" || pass "P1 체크리스트 컴포넌트 인식"

# ── P2: minimal 멱등 ─────────────────────────────────────────────────────
snapshot_tree "$(P m)" > "${SANDBOX_ROOT}/m-proj.1"
run_inst "$R" "$(H m)" --profile minimal --project "$(P m)" || fail "P2 2회차 exit≠0"
same_tree "$(P m)" "${SANDBOX_ROOT}/m-proj.1" && pass "P2 2회차 프로젝트 변경 0" || fail "P2 2회차 변경 발생"
[ "$(count_baks_in "$(P m)")" = "0" ] && pass "P2 신규 .bak 0" || fail "P2 .bak 생성됨"
same_tree "$(H m)" "${SANDBOX_ROOT}/m-home.before" && pass "P2 HOME 여전히 불변" || fail "P2 HOME 변경"

# ── P3: 골격 내용 ───────────────────────────────────────────────────────
MC="$(P m)/CLAUDE.md"
grep -q '\[' "$MC" && fail "P3 골격에 [ 자리표시자" || pass "P3 골격에 [ 없음"
grep -q '~/.claude/rules' "$MC" && fail "P3 골격이 글로벌 rules 참조" || pass "P3 글로벌 rules 참조 없음"
for s in test lint build; do
    grep -q "npm run ${s}" "$MC" && pass "P3 scripts.${s} 행 채움" || fail "P3 scripts.${s} 행 미채움"
done
grep -i '^| *dev' "$MC" | grep -q '미설정' && pass "P3 없는 script(dev) 는 미설정" || fail "P3 dev 행 이상"
[ "$(wc -l < "$R/templates/CLAUDE.minimal.md" | tr -d ' ')" -le 30 ] 2>/dev/null \
    && pass "P3 템플릿 30줄 이하" || fail "P3 템플릿 없음 또는 30줄 초과"
newenv np
run_inst "$R" "$(H np)" --profile minimal --project "$(P np)" || fail "P3 package.json 없는 minimal exit≠0"
grep -q 'npm run' "$(P np)/CLAUDE.md" 2>/dev/null && fail "P3 package.json 없는데 npm run 추론" \
    || pass "P3 package.json 없으면 전부 미설정"

# ── P4: python3 없으면 minimal fail-closed ──────────────────────────────
NOPY="${SANDBOX_ROOT}/nopy-bin"
mkdir -p "$NOPY"
OLDIFS="$IFS"; IFS=':'
for d in $PATH; do
    [ -d "$d" ] || continue
    for e in "$d"/*; do
        b="$(basename "$e")"
        case "$b" in python3*|python) continue ;; esac
        [ -x "$e" ] && [ ! -e "${NOPY}/${b}" ] && ln -s "$e" "${NOPY}/${b}" 2>/dev/null
    done
done
IFS="$OLDIFS"
newenv np4
snapshot_tree "$(H np4)" > "${SANDBOX_ROOT}/np4-h"; snapshot_tree "$(P np4)" > "${SANDBOX_ROOT}/np4-p"
( export PATH="$NOPY"; run_inst "$R" "$(H np4)" --profile minimal --project "$(P np4)" ); RC=$?
[ "$RC" -eq 1 ] && pass "P4 python3 없음 + minimal → exit 1" || fail "P4 exit ${RC} (기대 1)"
same_tree "$(H np4)" "${SANDBOX_ROOT}/np4-h" && same_tree "$(P np4)" "${SANDBOX_ROOT}/np4-p" \
    && pass "P4 프로젝트·HOME 무변경" || fail "P4 실패했는데 무언가 썼음"
( export PATH="$NOPY"; run_inst "$R" "$(H np4)" --profile minimal --project "${SANDBOX_ROOT}/np4-new" ); RC=$?
[ "$RC" -eq 1 ] && [ ! -e "${SANDBOX_ROOT}/np4-new" ] && pass "P4 없는 프로젝트 디렉토리도 만들지 않음" \
    || fail "P4 없는 프로젝트: exit ${RC}, 생성 여부 $([ -e "${SANDBOX_ROOT}/np4-new" ] && echo Y || echo N)"
( export PATH="$NOPY"; run_inst "$R" "$(H np4)" --profile core --project "$(P np4)" ); RC=$?
[ "$RC" -eq 0 ] && pass "P4 python3 없음 + core → 기존처럼 진행(exit 0)" || { fail "P4 core exit ${RC}"; tail -5 "${SANDBOX_ROOT}/last.out"; }
grep -q 'guardrails 훅 병합 스킵' "${SANDBOX_ROOT}/last.out" && pass "P4 core 는 WARN+skip 유지" || fail "P4 core WARN 없음"

# ── P5: 배타 규칙 ───────────────────────────────────────────────────────
newenv x
snapshot_tree "$(H x)" > "${SANDBOX_ROOT}/x-h"; snapshot_tree "$(P x)" > "${SANDBOX_ROOT}/x-p"
for args in "--profile minimal --with-advisor" "--profile minimal --with-cross-review" \
            "--profile minimal --global-only" "--full --profile minimal" "--profile core --full"; do
    # shellcheck disable=SC2086
    run_inst "$R" "$(H x)" $args --project "$(P x)"; RC=$?
    [ "$RC" -eq 1 ] && pass "P5 [$args] exit 1" || fail "P5 [$args] exit ${RC}"
done
run_inst "$R" "$(H x)" --profile bogus --project "$(P x)"; RC=$?
[ "$RC" -eq 1 ] && pass "P5 알 수 없는 프로필 exit 1" || fail "P5 bogus exit ${RC}"
same_tree "$(H x)" "${SANDBOX_ROOT}/x-h" && same_tree "$(P x)" "${SANDBOX_ROOT}/x-p" \
    && pass "P5 배타 위반 전부 무변경" || fail "P5 배타 위반인데 변경 발생"
# 기록된 minimal 위에 --with-advisor (프로필 미명시) 도 배타
run_inst "$R" "$(H m)" --with-advisor --project "$(P m)"; RC=$?
[ "$RC" -eq 1 ] && pass "P5 recorded minimal + --with-advisor → exit 1" || fail "P5 recorded minimal 우회 exit ${RC}"
# minimal + 프로젝트 전용 옵션은 허용
newenv mo
run_inst "$R" "$(H mo)" --profile minimal --with-pm2 --with-examples --project "$(P mo)"; RC=$?
[ "$RC" -eq 0 ] && pass "P5 minimal+pm2+examples 허용" || { fail "P5 minimal+옵션 exit ${RC}"; tail -5 "${SANDBOX_ROOT}/last.out"; }
grep -q 'profile: minimal+' "${SANDBOX_ROOT}/last.out" && pass "P5 요약 minimal+<옵션> 표기" || fail "P5 minimal+ 표기 없음"
[ -f "$(P mo)/.claude/hooks/post-tool-failure.sh" ] && pass "P5 --with-pm2 가 훅 파일 설치를 켬" || fail "P5 pm2 배선했는데 훅 파일 없음"
[ -z "$(ls -A "$(H mo)" 2>/dev/null)" ] && pass "P5 minimal+옵션도 HOME 쓰기 0" || fail "P5 minimal+옵션 HOME 씀"

# ── P6: 기록 재사용 (비TTY) ─────────────────────────────────────────────
run_inst "$R" "$(H m)" --project "$(P m)" < /dev/null; RC=$?
[ "$RC" -eq 0 ] && pass "P6 플래그 없이 재실행 exit 0" || fail "P6 exit ${RC}"
grep -q 'profile: minimal (recorded)' "${SANDBOX_ROOT}/last.out" && pass "P6 recorded 표기" || fail "P6 recorded 표기 없음"
[ ! -e "$(P m)/.claude/agents" ] && pass "P6 minimal 유지(에이전트 미설치)" || fail "P6 core 로 승격됨"
same_tree "$(H m)" "${SANDBOX_ROOT}/m-home.before" && pass "P6 HOME 불변" || fail "P6 HOME 변경"

# ── P7: 기록 없음 + 미명시 → core + 경고 1줄 ────────────────────────────
newenv c
HOME="$(H c)" bash "$R/install.sh" --project "$(P c)" > "${SANDBOX_ROOT}/c.out" 2> "${SANDBOX_ROOT}/c.err"; RC=$?
[ "$RC" -eq 0 ] && pass "P7 기본 실행 exit 0" || fail "P7 exit ${RC}"
[ "$(grep -c 'core 는 ~/.claude 를 수정합니다' "${SANDBOX_ROOT}/c.err")" = "1" ] \
    && pass "P7 stderr 경고 정확히 1줄" || fail "P7 stderr 경고 개수 이상"
grep -q 'profile: core (default)' "${SANDBOX_ROOT}/c.out" && pass "P7 profile: core (default)" || fail "P7 default 표기 없음"
[ -f "$(P c)/.claude/skill-rules.json" ] && pass "P7 core 산출물 설치" || fail "P7 core 산출물 없음"

# 정규화 스냅샷: 샌드박스 절대경로·타임스탬프 백업 이름을 지운 "내용 해시  경로" 목록
# $1=dir $2=tag (그 tag 의 proj/home 경로를 PROJ/HOME 으로 치환), ./projects 는 제외
norm_snap() {
    local pr pp hr hp
    pp="$(P "$2")"; pr="$(cd "$pp" && pwd -P)"; hp="$(H "$2")"; hr="$(cd "$hp" && pwd -P)"
    ( cd "$1" 2>/dev/null || return 0
      find . -type f -print | grep -v '\.bak\.[0-9T]*Z$' | grep -v '^\./projects/' | LC_ALL=C sort | \
      while IFS= read -r f; do
          printf '%s  %s\n' "$(sed -e "s#${pr}#PROJ#g" -e "s#${pp}#PROJ#g" -e "s#${hr}#HOME#g" -e "s#${hp}#HOME#g" "$f" \
              | shasum -a 256 | awk '{print $1}')" "$f"
      done )
}

# ── P8: --full == --profile full, 변경 전 full 대비 push 1건 외 동일 ─────
newenv f1; newenv f2
run_inst "$R" "$(H f1)" --full --project "$(P f1)" || fail "P8 --full exit≠0"
run_inst "$R" "$(H f2)" --profile full --project "$(P f2)" || fail "P8 --profile full exit≠0"
[ "$(norm_snap "$(P f1)" f1)" = "$(norm_snap "$(P f2)" f2)" ] \
    && pass "P8 --full 과 --profile full 프로젝트 산출물 동일" || fail "P8 프로젝트 산출물 상이"
[ "$(norm_snap "$(H f1)/.claude" f1)" = "$(norm_snap "$(H f2)/.claude" f2)" ] \
    && pass "P8 --full 과 --profile full 글로벌 산출물 동일" || fail "P8 글로벌 산출물 상이"
BASE="${SANDBOX_ROOT}/base-repo"; mkdir -p "$BASE"
if git -C "$R" archive c39be55 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/install.sh" ]; then
    # 비교 대상은 "설치기 로직" 이다. global/ 페이로드(rules·skills 내용)는 sync-from-live 로
    # 정당하게 갱신되므로 현재 것을 덮어써 내용 변경이 이 회귀 검사를 깨지 않게 한다.
    rm -rf "$BASE/global" && cp -R "$R/global" "$BASE/global"
    # docs/ 도 현재 작업트리 사본으로 맞춘다. git archive 는 한글 파일명을 NFC 로 풀지만
    # 오래된 macOS 체크아웃은 같은 이름이 NFD 로 남아 있어, 내용이 같아도 경로 문자열이
    # 달라 스냅샷 비교가 실패한다(설치기 로직과 무관한 체크아웃 환경 차이).
    rm -rf "$BASE/docs" && cp -R "$R/docs" "$BASE/docs"
    newenv f0
    run_inst "$BASE" "$(H f0)" --full --project "$(P f0)" || fail "P8 변경 전 --full exit≠0"
    # .settings-manifest 는 push identity 기록 1건 차이를 담는다 — 아래에서 따로 검증
    D8="$(diff <(norm_snap "$(P f0)" f0) <(norm_snap "$(P f1)" f1) | grep '^[<>]' \
        | grep -v ' ./.claude/settings.json$' | grep -v ' ./.claude/.install-profile$' \
        | grep -v ' ./.claude/.settings-manifest$' | grep -v ' ./.claude/settings.json.bak' || true)"
    [ -z "$D8" ] && pass "P8 변경 전 full 대비 settings 계열·.install-profile 외 파일 동일" || fail "P8 파일 차이: ${D8}"
    M8="$(diff "$(P f0)/.claude/.settings-manifest" "$(P f1)/.claude/.settings-manifest" | grep '^[<>]' || true)"
    if [ -z "$M8" ] || { [ "$(printf '%s\n' "$M8" | grep -c '^<')" -le 1 ] && ! printf '%s\n' "$M8" | grep -q '^>' \
        && printf '%s\n' "$M8" | grep -q 'git push'; }; then
        pass "P8 .settings-manifest 차이는 push identity 뿐"
    else
        # 해시형 기록이면 내용으로 비교할 수 없다 — 차이 원문을 남긴다
        printf '%s\n' "$M8" | head -4
        fail "P8 .settings-manifest 에 push 외 차이"
    fi
    S0="$(jq -S 'del(.permissions.allow[] | select(. == "Bash(git push:*)"))' "$(P f0)/.claude/settings.json")"
    S1="$(jq -S . "$(P f1)/.claude/settings.json")"
    [ "$S0" = "$S1" ] && pass "P8 settings.json 은 push allow 1건만 차이" || fail "P8 settings.json 에 push 외 차이"
    [ "$(norm_snap "$(H f0)/.claude" f0)" = "$(norm_snap "$(H f1)/.claude" f1)" ] \
        && pass "P8 변경 전 full 대비 글로벌 산출물 동일" || fail "P8 변경 전 대비 글로벌 상이"
else
    skip "P8 변경 전 리비전(c39be55) 추출 불가"
fi

# ── P9: 프로필 전환 ─────────────────────────────────────────────────────
newenv up
run_inst "$R" "$(H up)" --profile minimal --project "$(P up)" || fail "P9 minimal exit≠0"
UP_BEFORE="$(cd "$(P up)" && find . -type f | LC_ALL=C sort)"
run_inst "$R" "$(H up)" --profile full --project "$(P up)" || fail "P9 minimal→full exit≠0"
UP_LOST=""
while IFS= read -r f; do [ -e "$(P up)/$f" ] || UP_LOST="${UP_LOST} $f"; done <<EOF
$UP_BEFORE
EOF
[ -z "$UP_LOST" ] && pass "P9 minimal→full 삭제 0" || fail "P9 minimal→full 삭제:${UP_LOST}"
[ -d "$(P up)/.claude/agents" ] && pass "P9 minimal→full 추가 설치" || fail "P9 full 자산 미설치"
[ "$(cat "$(P up)/.claude/.install-profile")" = "profile=full" ] && pass "P9 기록 갱신 full" || fail "P9 기록 미갱신"
snapshot_tree "$(P f1)" > "${SANDBOX_ROOT}/f1.before"
snapshot_tree "$(H f1)" > "${SANDBOX_ROOT}/f1h.before"
run_inst "$R" "$(H f1)" --profile minimal --project "$(P f1)"; RC=$?
[ "$RC" -eq 0 ] && pass "P9 full→minimal exit 0" || fail "P9 full→minimal exit ${RC}"
F1_LOST=""
while IFS= read -r line; do
    f="${line##* }"; [ -e "$(P f1)/$f" ] || [ -L "$(P f1)/$f" ] || F1_LOST="${F1_LOST} $f"
done < "${SANDBOX_ROOT}/f1.before"
[ -z "$F1_LOST" ] && pass "P9 full→minimal 삭제 0" || fail "P9 full→minimal 삭제:${F1_LOST}"
grep -q '이전 설치에서 남은 installer 소유 자산 [1-9][0-9]*건' "${SANDBOX_ROOT}/last.out" \
    && pass "P9 남은 자산 N건 요약" || fail "P9 남은 자산 요약 없음"
same_tree "$(H f1)" "${SANDBOX_ROOT}/f1h.before" && pass "P9 full→minimal HOME 불변" || fail "P9 full→minimal HOME 변경"
[ -f "$(P f1)/.claude/agents/$(ls "$R/project/agents" | head -1)" ] && \
    [ "$(file_hash "$(P f1)/.claude/settings.json")" != "" ] && pass "P9 기존 자산 그대로" || fail "P9 기존 자산 이상"

# ── P10: --uninstall 이 .install-profile 제거 ───────────────────────────
run_inst "$R" "$(H m)" --uninstall --project "$(P m)"; RC=$?
[ "$RC" -eq 0 ] && pass "P10 uninstall exit 0" || fail "P10 uninstall exit ${RC}"
[ ! -e "$(P m)/.claude/.install-profile" ] && pass "P10 .install-profile 제거" || fail "P10 .install-profile 잔존"

# ── P11 (Codex P2): .install-profile 이 FIFO 여도 무기한 대기하지 않음 ──
newenv ff
mkdir -p "$(P ff)/.claude"; mkfifo "$(P ff)/.claude/.install-profile"
( run_inst "$R" "$(H ff)" --profile minimal --project "$(P ff)" ) & FPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    kill -0 "$FPID" 2>/dev/null || break; sleep 1
done
if kill -0 "$FPID" 2>/dev/null; then
    kill "$FPID" 2>/dev/null; pkill -f "$(P ff)" 2>/dev/null
    fail "P11 FIFO 기록 파일에서 설치가 멈춤"
else
    wait "$FPID"; pass "P11 FIFO 기록 파일이어도 설치 완료(exit $?)"
fi

# ── P12 (Codex P2): .claude 가 링크로 바뀐 뒤 uninstall 이 링크 너머 기록을 지우지 않음 ──
newenv lk
run_inst "$R" "$(H lk)" --profile minimal --project "$(P lk)" || fail "P12 설치 exit≠0"
mv "$(P lk)/.claude" "${SANDBOX_ROOT}/lk-outside"
ln -s "${SANDBOX_ROOT}/lk-outside" "$(P lk)/.claude"
run_inst "$R" "$(H lk)" --uninstall --project "$(P lk)"
[ -f "${SANDBOX_ROOT}/lk-outside/.install-profile" ] && pass "P12 링크 너머 .install-profile 보존" \
    || fail "P12 uninstall 이 링크 너머 .install-profile 삭제"

finish
