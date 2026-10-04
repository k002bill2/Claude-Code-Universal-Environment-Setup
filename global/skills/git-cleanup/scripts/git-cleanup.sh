#!/bin/bash
# ============================================================================
# git-cleanup.sh — 머지 완료된 브랜치·워크트리 정리 (bash 3.2 호환)
# ----------------------------------------------------------------------------
# 사용:
#   git-cleanup.sh [scan]            읽기 전용 분류표 출력 (기본)
#   git-cleanup.sh apply [--remote]  같은 분류를 다시 계산해 안전한 것만 삭제
#                                    --remote 가 있어야 원격 브랜치도 삭제
# 옵션: --base <branch>  비교 기준 (기본: origin/HEAD → main → master)
# 환경: GIT_CLEANUP_REMOTE(기본 origin) · GIT_CLEANUP_NO_GH=1(gh 조회 끔)
#       GIT_CLEANUP_NO_FETCH=1(fetch --prune 생략)
#
# 출력 행: <ACTION> <KIND> <NAME> <REASON>
#   ACTION = DELETE | REMOVE | PRUNE | KEEP,  KIND = local | remote | worktree
#
# "머지됨" 판정 (하나라도 참이면 내용 손실 없음):
#   1. 기준 브랜치의 ancestor          2. 트리가 기준과 동일
#   3. 브랜치 순변경의 patch-id 가 기준의 커밋 하나와 일치 (squash 머지)
#   4. gh: 이 브랜치 tip 을 head 로 하는 PR 이 MERGED
# 보호: 기준 브랜치·main·master·develop·현재 브랜치·dirty/locked 워크트리 브랜치.
# ============================================================================
set -u

MODE=scan
DO_REMOTE=0
BASE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        scan|apply) MODE="$1" ;;
        --remote)   DO_REMOTE=1 ;;
        --base)     BASE_ARG="${2:-}"; shift ;;
        -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "알 수 없는 인자: $1" >&2; exit 2 ;;
    esac
    shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "git 레포가 아닙니다: $(pwd)" >&2; exit 2; }

REMOTE="${GIT_CLEANUP_REMOTE:-origin}"
HAS_REMOTE=0
git remote get-url "$REMOTE" >/dev/null 2>&1 && HAS_REMOTE=1

FETCH_FAILED=0
if [ "$HAS_REMOTE" = 1 ] && [ "${GIT_CLEANUP_NO_FETCH:-0}" != 1 ]; then
    if ! git fetch --prune --quiet "$REMOTE" 2>/dev/null; then
        FETCH_FAILED=1; echo "WARN fetch 실패 — 로컬 ref 기준으로 진행 (원격 삭제는 하지 않음)" >&2
    fi
fi

# ── 기준 브랜치 ─────────────────────────────────────────────────────────
BASE_NAME="$BASE_ARG"
if [ -z "$BASE_NAME" ]; then
    BASE_NAME="$(git symbolic-ref --quiet --short "refs/remotes/${REMOTE}/HEAD" 2>/dev/null)"
    BASE_NAME="${BASE_NAME#"${REMOTE}"/}"
fi
if [ -z "$BASE_NAME" ]; then
    for c in main master; do
        git rev-parse -q --verify "refs/heads/$c" >/dev/null && { BASE_NAME="$c"; break; }
    done
fi
[ -n "$BASE_NAME" ] || { echo "기준 브랜치를 찾지 못했습니다 — --base 로 지정하세요" >&2; exit 2; }
BASE_REF="$BASE_NAME"
git rev-parse -q --verify "refs/remotes/${REMOTE}/${BASE_NAME}" >/dev/null && BASE_REF="${REMOTE}/${BASE_NAME}"
git rev-parse -q --verify "$BASE_REF" >/dev/null || { echo "기준 ref 없음: $BASE_REF" >&2; exit 2; }

CURRENT="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"

USE_GH=0
if [ "${GIT_CLEANUP_NO_GH:-0}" != 1 ] && [ "$HAS_REMOTE" = 1 ] && command -v gh >/dev/null 2>&1 \
    && git remote get-url "$REMOTE" | grep -q 'github.com'; then
    USE_GH=1
fi

is_protected() {
    case "$1" in
        "$BASE_NAME"|main|master|develop) return 0 ;;
    esac
    [ -n "$CURRENT" ] && [ "$1" = "$CURRENT" ] && return 0
    return 1
}

# 기준 이후 커밋들의 patch-id 집합 (merge-base 별로 다르므로 호출마다 계산)
# --verbatim: 기본 patch-id 는 공백을 무시해 'a b' 와 'ab' 를 같은 패치로 본다
base_patch_ids() {
    git log --no-merges -p "$1..$BASE_REF" 2>/dev/null | git patch-id --verbatim | cut -d' ' -f1
}

# merged_reason <ref> <branch-name> → 머지 사유 출력 후 0, 아니면 1
merged_reason() {
    local ref="$1" name="$2" mb pid num
    if git merge-base --is-ancestor "$ref" "$BASE_REF" 2>/dev/null; then
        echo "merged (ancestor of ${BASE_REF})"; return 0
    fi
    if git diff --quiet "$BASE_REF" "$ref" 2>/dev/null; then
        echo "tree identical to ${BASE_REF}"; return 0
    fi
    mb="$(git merge-base "$BASE_REF" "$ref" 2>/dev/null)"
    if [ -n "$mb" ]; then
        pid="$(git diff "$mb" "$ref" | git patch-id --verbatim | cut -d' ' -f1)"
        if [ -n "$pid" ] && base_patch_ids "$mb" | grep -qx "$pid"; then
            echo "squash-merged (patch-id matches ${BASE_REF})"; return 0
        fi
    fi
    if [ "$USE_GH" = 1 ]; then
        num="$(gh pr list --state merged --head "$name" --limit 20 \
            --json number,headRefOid \
            -q ".[] | select(.headRefOid == \"$(git rev-parse "$ref")\") | .number" 2>/dev/null | head -1)"
        if [ -n "$num" ]; then
            echo "squash-merged (PR #${num} merged)"; return 0
        fi
    fi
    return 1
}

unmerged_reason() {
    echo "unmerged: $(git rev-list --count "$BASE_REF..$1" 2>/dev/null) commit(s) not in ${BASE_REF}"
}

ROWS=""
row() { ROWS="${ROWS}$(printf '%-7s %-9s %s %s' "$1" "$2" "$3" "$4")
"; }

# ── 워크트리 ────────────────────────────────────────────────────────────
WT_KEEP_BRANCHES=" "      # dirty/locked 워크트리의 브랜치 — 로컬 삭제 금지
WT_REMOVE_BRANCHES=" "    # 워크트리 제거 후 함께 지울 브랜치
WT_PATHS_REMOVE=""
wt_flush() {
    [ -n "$wt_path" ] || return 0
    if [ "$wt_path" = "$TOPLEVEL" ] || [ "$wt_first" = 1 ]; then
        :
    elif [ "$wt_prunable" = 1 ] || [ ! -d "$wt_path" ]; then
        row PRUNE worktree "$wt_path" "directory missing"
    elif [ "$wt_locked" = 1 ]; then
        row KEEP worktree "$wt_path" "locked"
        [ -n "$wt_branch" ] && WT_KEEP_BRANCHES="${WT_KEEP_BRANCHES}${wt_branch} "
    else
        local dirty reason
        dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
        if [ "$dirty" != 0 ]; then
            row KEEP worktree "$wt_path" "dirty (${dirty} change(s))"
            [ -n "$wt_branch" ] && WT_KEEP_BRANCHES="${WT_KEEP_BRANCHES}${wt_branch} "
        elif [ -z "$wt_branch" ]; then
            row KEEP worktree "$wt_path" "detached HEAD"
        elif is_protected "$wt_branch"; then
            row KEEP worktree "$wt_path" "protected branch ${wt_branch}"
            WT_KEEP_BRANCHES="${WT_KEEP_BRANCHES}${wt_branch} "
        elif reason="$(merged_reason "refs/heads/$wt_branch" "$wt_branch")"; then
            row REMOVE worktree "$wt_path" "clean, branch ${wt_branch} ${reason}"
            WT_REMOVE_BRANCHES="${WT_REMOVE_BRANCHES}${wt_branch} "
            WT_PATHS_REMOVE="${WT_PATHS_REMOVE}${wt_path}
"
        else
            row KEEP worktree "$wt_path" "branch ${wt_branch} $(unmerged_reason "refs/heads/$wt_branch")"
            WT_KEEP_BRANCHES="${WT_KEEP_BRANCHES}${wt_branch} "
        fi
    fi
    wt_first=0
}
wt_first=1; wt_path=""; wt_branch=""; wt_locked=0; wt_prunable=0
while IFS= read -r line; do
    case "$line" in
        "worktree "*) wt_path="${line#worktree }"; wt_branch=""; wt_locked=0; wt_prunable=0 ;;
        "branch refs/heads/"*) wt_branch="${line#branch refs/heads/}" ;;
        locked*)   wt_locked=1 ;;
        prunable*) wt_prunable=1 ;;
        "") wt_flush; wt_path="" ;;
    esac
done <<EOF
$(git worktree list --porcelain)

EOF

# ── 로컬 브랜치 ─────────────────────────────────────────────────────────
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    case "$WT_KEEP_BRANCHES" in *" $b "*) continue ;; esac
    case "$WT_REMOVE_BRANCHES" in *" $b "*) row DELETE local "$b" "after worktree removal"; continue ;; esac
    if is_protected "$b"; then
        continue
    elif reason="$(merged_reason "refs/heads/$b" "$b")"; then
        row DELETE local "$b" "$reason"
    else
        row KEEP local "$b" "$(unmerged_reason "refs/heads/$b")"
    fi
done

# ── 원격 브랜치 ─────────────────────────────────────────────────────────
REMOTE_DEL=""      # "<name> <분류 시점 SHA>" — 삭제 lease 용
if [ "$HAS_REMOTE" = 1 ]; then
    for r in $(git for-each-ref --format='%(refname:short)' "refs/remotes/${REMOTE}/"); do
        name="${r#"${REMOTE}"/}"
        case "$name" in HEAD|"$REMOTE") continue ;; esac
        case "$name" in "$BASE_NAME"|main|master|develop) continue ;; esac
        # 현재 브랜치(및 그 upstream)의 원격은 작업 중일 수 있다
        { [ -n "$CURRENT" ] && [ "$name" = "$CURRENT" ]; } && continue
        [ "$r" = "$UPSTREAM" ] && continue
        if reason="$(merged_reason "refs/remotes/$r" "$name")"; then
            row DELETE remote "$r" "$reason"
            REMOTE_DEL="${REMOTE_DEL}${name} $(git rev-parse "refs/remotes/$r")
"
        else
            row KEEP remote "$r" "$(unmerged_reason "refs/remotes/$r")"
        fi
    done
fi

echo "# base: ${BASE_REF}   current: ${CURRENT:-<detached>}   mode: ${MODE}$([ "$DO_REMOTE" = 1 ] && echo ' --remote')"
printf '%s' "$ROWS"
[ -n "$ROWS" ] || echo "# 정리할 브랜치·워크트리 없음"

[ "$MODE" = apply ] || exit 0

# ── apply ───────────────────────────────────────────────────────────────
echo "# applying"
FAILED=0
run() { echo "+ $*"; "$@" || { echo "! 실패: $*" >&2; FAILED=1; }; }

if printf '%s' "$ROWS" | grep -q '^PRUNE '; then run git worktree prune; fi
printf '%s' "$WT_PATHS_REMOVE" | while IFS= read -r p; do
    [ -n "$p" ] && run git worktree remove "$p"     # --force 금지: dirty 면 git 이 거부
done
for b in $(printf '%s' "$ROWS" | awk '$1=="DELETE" && $2=="local" {print $3}'); do
    run git branch -D "$b"      # 위에서 머지 검증 완료 — squash 는 -d 가 거부하므로 -D
done
if [ "$DO_REMOTE" = 1 ]; then
    if [ "$FETCH_FAILED" = 1 ]; then
        echo "! fetch 실패 — 원격 상태를 확인할 수 없어 원격 삭제를 건너뜀" >&2; FAILED=1
    else
        # lease: 분류한 SHA 와 원격 tip 이 다르면 git 이 거부 (그 사이 push 된 커밋 보호)
        while read -r name sha; do
            [ -n "$name" ] && run git push "--force-with-lease=refs/heads/${name}:${sha}" "$REMOTE" ":refs/heads/${name}"
        done <<EOF
$REMOTE_DEL
EOF
    fi
elif printf '%s' "$ROWS" | grep -q '^DELETE  remote'; then
    echo "# 원격 후보는 건너뜀 — 삭제하려면 apply --remote"
fi
exit "$FAILED"
