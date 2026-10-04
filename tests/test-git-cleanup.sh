#!/bin/bash
# ============================================================================
# tests/test-git-cleanup.sh — global/skills/git-cleanup/scripts/git-cleanup.sh
# ----------------------------------------------------------------------------
# 샌드박스 bare remote + clone 으로 머지/스쿼시/미머지 브랜치와 워크트리
# (clean·dirty·디렉토리 소실)를 만들고 scan 분류와 apply 결과를 검증한다.
# gh 조회는 GIT_CLEANUP_NO_GH=1 로 끈다 (네트워크 무관).
# ============================================================================
set -u
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
# shellcheck source=helpers.sh
. "${TESTS_DIR}/helpers.sh"
SCRIPT="${REPO_ROOT}/global/skills/git-cleanup/scripts/git-cleanup.sh"

init_sandbox
export GIT_CLEANUP_NO_GH=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

REMOTE="${SANDBOX_ROOT}/remote.git"
W="${SANDBOX_ROOT}/work"
g() { git -C "$W" "$@" >/dev/null 2>&1; }
commit_file() { echo "$2" > "$W/$1"; g add "$1"; g commit -m "$3"; }

git init -q --bare -b main "$REMOTE"
git clone -q "$REMOTE" "$W" 2>/dev/null
g switch -c main
commit_file base.txt base "init"
g push -u origin main
g remote set-head origin main

# merged: --no-ff 머지
g switch -c feat/merged; commit_file a.txt a "a"
g switch main; g merge --no-ff feat/merged -m "merge a"
# squashed: squash 머지 (ancestor 아님) + 원격에도 존재
g switch -c feat/squashed; commit_file b.txt b "b"; g push origin feat/squashed
g switch main; g merge --squash feat/squashed; g commit -m "squash b"
commit_file later.txt later "main 이 squash 이후 전진 — 트리 동일 경로가 아니라 patch-id 경로를 타게 한다"
# unmerged: 로컬 + 원격
g switch -c feat/unmerged; commit_file c.txt c "c"; g push origin feat/unmerged
g switch main
g push origin main
# 워크트리: clean+merged / dirty+merged / 디렉토리 소실
g branch wt/clean main; g branch wt/dirty main; g branch wt/gone main
g worktree add "${SANDBOX_ROOT}/wt-clean" wt/clean
g worktree add "${SANDBOX_ROOT}/wt-dirty" wt/dirty
g worktree add "${SANDBOX_ROOT}/wt-gone" wt/gone
echo junk > "${SANDBOX_ROOT}/wt-dirty/untracked.txt"
rm -rf "${SANDBOX_ROOT}/wt-gone"

# ── scan ────────────────────────────────────────────────────────────────
SCAN="$(cd "$W" && bash "$SCRIPT" scan 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && pass "G1 scan exit 0" || fail "G1 scan exit ${RC}: ${SCAN}"

expect_line() { # $1 id, $2 regex
    if printf '%s\n' "$SCAN" | grep -Eq "$2"; then pass "$1"; else fail "$1 — 패턴 없음: $2"; printf '%s\n' "$SCAN" | sed 's/^/    | /'; fi
}
reject_line() {
    if printf '%s\n' "$SCAN" | grep -Eq "$2"; then fail "$1 — 금지 패턴 발견: $2"; else pass "$1"; fi
}
expect_line "G2 --no-ff 머지 브랜치 DELETE"     '^DELETE +local +feat/merged '
expect_line "G3 squash 머지 브랜치 DELETE"       '^DELETE +local +feat/squashed .*squash'
expect_line "G4 미머지 브랜치 KEEP"              '^KEEP +local +feat/unmerged '
expect_line "G5 원격 squash 브랜치 DELETE 후보"  '^DELETE +remote +origin/feat/squashed '
expect_line "G6 원격 미머지 브랜치 KEEP"         '^KEEP +remote +origin/feat/unmerged '
expect_line "G7 clean 워크트리 REMOVE"           '^REMOVE +worktree +.*wt-clean '
expect_line "G8 dirty 워크트리 KEEP"             '^KEEP +worktree +.*wt-dirty .*dirty'
expect_line "G9 소실 워크트리 PRUNE"             '^PRUNE +worktree +.*wt-gone '
reject_line "G10 main 은 후보가 아님"            ' (local|remote) +(origin/)?main '
reject_line "G11 dirty 워크트리의 브랜치는 DELETE 아님" '^DELETE +local +wt/dirty '

# scan 은 아무것도 바꾸지 않는다
if git -C "$W" rev-parse -q --verify feat/merged >/dev/null && [ -d "${SANDBOX_ROOT}/wt-clean" ]; then
    pass "G12 scan 은 읽기 전용"
else
    fail "G12 scan 이 상태를 바꿈"
fi

# ── apply (원격 제외) ───────────────────────────────────────────────────
OUT="$(cd "$W" && bash "$SCRIPT" apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && pass "G13 apply exit 0" || fail "G13 apply exit ${RC}: ${OUT}"
has() { git -C "$W" rev-parse -q --verify "$1" >/dev/null; }
! has refs/heads/feat/merged   && pass "G14 feat/merged 삭제됨"   || fail "G14 feat/merged 남음"
! has refs/heads/feat/squashed && pass "G15 feat/squashed 삭제됨" || fail "G15 feat/squashed 남음"
has refs/heads/feat/unmerged   && pass "G16 feat/unmerged 보존"   || fail "G16 feat/unmerged 삭제됨"
has refs/heads/main            && pass "G17 main 보존"            || fail "G17 main 삭제됨"
[ ! -d "${SANDBOX_ROOT}/wt-clean" ] && ! has refs/heads/wt/clean \
    && pass "G18 clean 워크트리+브랜치 제거" || fail "G18 clean 워크트리 남음"
[ -f "${SANDBOX_ROOT}/wt-dirty/untracked.txt" ] && has refs/heads/wt/dirty \
    && pass "G19 dirty 워크트리 보존" || fail "G19 dirty 워크트리 손실"
git -C "$W" worktree list --porcelain | grep -q 'wt-gone' \
    && fail "G20 소실 워크트리 prune 안 됨" || pass "G20 소실 워크트리 prune"
git -C "$REMOTE" rev-parse -q --verify refs/heads/feat/squashed >/dev/null \
    && pass "G21 --remote 없이는 원격 보존" || fail "G21 --remote 없이 원격 삭제됨"

# ── apply --remote ──────────────────────────────────────────────────────
(cd "$W" && bash "$SCRIPT" apply --remote >/dev/null 2>&1)
git -C "$REMOTE" rev-parse -q --verify refs/heads/feat/squashed >/dev/null \
    && fail "G22 --remote 로 원격 squash 브랜치 삭제 안 됨" || pass "G22 --remote 원격 squash 브랜치 삭제"
git -C "$REMOTE" rev-parse -q --verify refs/heads/feat/unmerged >/dev/null \
    && pass "G23 원격 미머지 브랜치 보존" || fail "G23 원격 미머지 브랜치 삭제됨"
git -C "$REMOTE" rev-parse -q --verify refs/heads/main >/dev/null \
    && pass "G24 원격 main 보존" || fail "G24 원격 main 삭제됨"

# ── 현재 체크아웃 브랜치는 머지됐어도 건드리지 않는다 ───────────────────
g switch -c feat/current main
SCAN="$(cd "$W" && bash "$SCRIPT" scan 2>&1)"
reject_line "G25 현재 브랜치는 DELETE 아님" '^DELETE +local +feat/current '

# ── 공백만 다른 패치는 squash 머지로 오인하지 않는다 (patch-id 기본은 공백 무시) ──
g switch main
g switch -c feat/ws; commit_file ws.txt 'print("a b")' "ws"
g switch main; commit_file ws.txt 'print("ab")' "ws on main"; g push origin main
g switch feat/current
SCAN="$(cd "$W" && bash "$SCRIPT" scan 2>&1)"
expect_line "G27 공백만 다른 브랜치는 KEEP" '^KEEP +local +feat/ws '

# ── 반복 블록: 위치만 다른 같은 변경은 squash 머지가 아니다 (patch-id 는 행 번호 무시) ──
g switch main
rep_file() { awk -v at="$1" 'BEGIN{for(i=1;i<=20;i++){print "x"; if(i==at) print "ADD"}}' > "$W/rep.txt"; }
rep_file 0; g add rep.txt; g commit -m "rep base"; g push origin main
g switch -c feat/rep; rep_file 15; g commit -am "add at line 15"
g switch main;        rep_file 5;  g commit -am "add at line 5"; g push origin main
g switch feat/current
SCAN="$(cd "$W" && bash "$SCRIPT" scan 2>&1)"
expect_line "G30 위치만 다른 동일 변경은 KEEP" '^KEEP +local +feat/rep '

# ── 현재 브랜치의 원격도 보호 ───────────────────────────────────────────
g push origin feat/current
SCAN="$(cd "$W" && bash "$SCRIPT" scan 2>&1)"
reject_line "G28 현재 브랜치의 원격은 DELETE 아님" '^DELETE +remote +origin/feat/current '

# ── 분류 후 원격 tip 이 바뀌면 원격 삭제 거부 (lease) ───────────────────
g switch main
g switch -c feat/raced; g push origin feat/raced; g switch main
OTHER="${SANDBOX_ROOT}/other"
git clone -q -b feat/raced "$REMOTE" "$OTHER" 2>/dev/null
echo new > "$OTHER/new.txt"; git -C "$OTHER" add new.txt >/dev/null 2>&1
git -C "$OTHER" commit -qm "new work" >/dev/null 2>&1; git -C "$OTHER" push -q origin feat/raced >/dev/null 2>&1
(cd "$W" && GIT_CLEANUP_NO_FETCH=1 bash "$SCRIPT" apply --remote >/dev/null 2>&1)
if [ "$(git -C "$REMOTE" rev-parse refs/heads/feat/raced 2>/dev/null)" = "$(git -C "$OTHER" rev-parse HEAD)" ]; then
    pass "G29 원격 tip 변경 시 lease 로 삭제 거부"
else
    fail "G29 검증 안 된 원격 커밋이 삭제됨"
fi

# ── git 레포 밖에서는 실패 ──────────────────────────────────────────────
(cd "$SANDBOX_ROOT" && bash "$SCRIPT" scan >/dev/null 2>&1) \
    && fail "G26 레포 밖에서 exit 0" || pass "G26 레포 밖에서 non-zero exit"

finish
