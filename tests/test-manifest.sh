#!/bin/bash
# ============================================================================
# tests/test-manifest.sh — lib/manifest.sh 단위 테스트
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${REPO_DIR}/tests/helpers.sh"
. "${REPO_DIR}/lib/manifest.sh"

init_sandbox
D="${SANDBOX_ROOT}/work"
mkdir -p "$D"

echo "=== N1: get/set/remove 기본 동작 ==="
MF="${D}/manifest.tsv"
manifest_set "$MF" "rules/a.md" "hash-a"
manifest_set "$MF" "skills/b/SKILL.md" "hash-b"
if [ "$(manifest_get "$MF" "rules/a.md")" = "hash-a" ]; then
    pass "N1 get 조회 성공"
else
    fail "N1 get 조회 실패"
fi
manifest_set "$MF" "rules/a.md" "hash-a2"
if [ "$(manifest_get "$MF" "rules/a.md")" = "hash-a2" ]; then
    pass "N1 upsert 갱신 성공 (중복 라인 없음)"
else
    fail "N1 upsert 갱신 실패"
fi
LINES="$(wc -l < "$MF" | tr -d ' ')"
if [ "$LINES" = "2" ]; then
    pass "N1 upsert 후에도 라인 수 2 (중복 없음)"
else
    fail "N1 라인 수 ${LINES} (중복 발생)"
fi
manifest_remove "$MF" "skills/b/SKILL.md"
if [ -z "$(manifest_get "$MF" "skills/b/SKILL.md")" ]; then
    pass "N1 remove 성공"
else
    fail "N1 remove 실패"
fi

echo "=== N2: manifest_paths 전체 나열 ==="
MF2="${D}/manifest2.tsv"
manifest_set "$MF2" "x" "1"
manifest_set "$MF2" "y" "2"
COUNT="$(manifest_paths "$MF2" | wc -l | tr -d ' ')"
if [ "$COUNT" = "2" ]; then
    pass "N2 paths 2개 나열"
else
    fail "N2 paths ${COUNT}개 (기대 2)"
fi

echo "=== N3: 없는 manifest 조회는 에러 없이 빈 값 ==="
if [ -z "$(manifest_get "${D}/nope.tsv" "x" 2>/dev/null)" ]; then
    pass "N3 부재 manifest get → 빈 값"
else
    fail "N3 부재 manifest get 이 빈 값 아님"
fi

echo "=== N4: hash_file 은 동일 내용에 동일 해시 ==="
printf 'hello world\n' > "${D}/f1.txt"
printf 'hello world\n' > "${D}/f2.txt"
printf 'different\n' > "${D}/f3.txt"
H1="$(manifest_hash_file "${D}/f1.txt")"
H2="$(manifest_hash_file "${D}/f2.txt")"
H3="$(manifest_hash_file "${D}/f3.txt")"
if [ -n "$H1" ] && [ "$H1" = "$H2" ]; then
    pass "N4 동일 내용 동일 해시"
else
    fail "N4 동일 내용인데 해시 다름 (${H1} vs ${H2})"
fi
if [ "$H1" != "$H3" ]; then
    pass "N4 다른 내용 다른 해시"
else
    fail "N4 다른 내용인데 해시 같음"
fi

# 새 계약: prune 은 **설치기가 만든** 백업만 지운다. 실제 호출자(install.sh)가
# 하는 대로 소유 색인에 등록한 뒤 prune 을 부른다.
own_and_prune() {
    local target="$1"; shift
    local man; man="$(dirname "$target")/.manifest"
    local b
    for b in "$@"; do manifest_backup_record "$man" "$b"; done
    MANIFEST_BACKUP_INDEX="$(manifest_backup_index "$man")"
    export MANIFEST_BACKUP_INDEX
    manifest_prune_backups "$target"
}

echo "=== N5: bounded backup — 5회 백업해도 3개만 남음 ==="
TARGET="${D}/target.txt"
N5_OWNED=""
printf 'v0\n' > "$TARGET"
i=1
while [ "$i" -le 5 ]; do
    BAK="$(manifest_backup_path "$TARGET")"
    cp "$TARGET" "$BAK"
    printf 'v%s\n' "$i" > "$TARGET"
    N5_OWNED="${N5_OWNED} ${BAK}"
    own_and_prune "$TARGET" $N5_OWNED
    i=$((i + 1))
done
BAKCOUNT="$(find "$D" -maxdepth 1 \( -name 'target.txt.bak' -o -name 'target.txt.bak.*' \) | wc -l | tr -d ' ')"
if [ "$BAKCOUNT" -le 3 ] && [ "$BAKCOUNT" -ge 1 ]; then
    pass "N5 bounded backup (${BAKCOUNT} ≤ 3)"
else
    fail "N5 backup ${BAKCOUNT}개 — bounded 아님"
fi

# N6: 개수만 세면 "무엇을 지웠는지"를 검증하지 못한다. 실제로 오래된 것부터
# 지우는지 mtime 을 고정해 생존자 신원까지 확인한다.
echo "=== N6: bounded backup 은 가장 오래된 것을 지운다 (생존자 신원) ==="
D6="${D}/n6 dir with space"
mkdir -p "$D6"
T6="${D6}/target.txt"
printf 'current\n' > "$T6"
i=1
while [ "$i" -le 5 ]; do
    printf 'v%s\n' "$i" > "${T6}.bak.${i}"
    i=$((i + 1))
done
# 이름 순서와 mtime 순서를 "반대로" 준다. 디렉토리 나열 순서에 기대는 구현은
# 여기서 반드시 틀린다(디렉토리 순서는 APFS 에서 해시 기반이라 재현성이 없다 —
# 이름/시간을 역상관시켜야 결정적인 RED 가 된다).
touch -t 202601050101 "${T6}.bak.1"   # 최신
touch -t 202601040101 "${T6}.bak.2"
touch -t 202601030101 "${T6}.bak.3"
touch -t 202601020101 "${T6}.bak.4"
touch -t 202601010101 "${T6}.bak.5"   # 가장 오래됨

MANIFEST_BACKUP_KEEP=3
export MANIFEST_BACKUP_KEEP
own_and_prune "$T6" "${T6}.bak.1" "${T6}.bak.2" "${T6}.bak.3" "${T6}.bak.4" "${T6}.bak.5"

N6_LEFT="$(find "$D6" -maxdepth 1 -name 'target.txt.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N6_LEFT" -eq 3 ]; then
    pass "N6 백업 3개만 남음"
else
    fail "N6 백업 ${N6_LEFT}개 남음 (기대 3)"
fi
if [ ! -e "${T6}.bak.5" ] && [ ! -e "${T6}.bak.4" ]; then
    pass "N6 가장 오래된 2개(.bak.5,.bak.4)가 삭제됨"
else
    fail "N6 오래된 백업이 살아남음: $(ls "${T6}.bak.5" "${T6}.bak.4" 2>/dev/null | tr '\n' ' ')"
fi
N6_OK=true
for want in 1 2 3; do
    if [ ! -f "${T6}.bak.${want}" ] || [ "$(cat "${T6}.bak.${want}" 2>/dev/null)" != "v${want}" ]; then
        N6_OK=false
    fi
done
if $N6_OK; then
    pass "N6 최신 3개(.bak.1,.bak.2,.bak.3)가 내용까지 그대로 보존됨"
else
    fail "N6 최신 백업이 삭제/훼손됨 — 남은 것: $(for k in 1 2 3 4 5; do [ -f "${T6}.bak.${k}" ] && printf '%s ' "v${k}"; done)"
fi
unset MANIFEST_BACKUP_KEEP

# ============================================================================
echo "=== N7: find -maxdepth 이식성 카나리아 ==="
# ============================================================================
# 리뷰에서 "BSD find 는 -maxdepth 를 지원하지 않는다" 는 지적이 반복해서 올라온다.
# 사실이 아니다(BSD/macOS find 는 -maxdepth·-mindepth 를 지원한다). 주장 대신
# 이 플랫폼에서 실제로 동작하는지를 매 실행 검사해, 진짜 깨지는 환경이 생기면
# 그때 실패하도록 한다.
N7D="$(mktemp -d)"
mkdir -p "${N7D}/a/b"
: > "${N7D}/a/top.bak"
: > "${N7D}/a/b/deep.bak"
N7_TOP="$(find "${N7D}/a" -maxdepth 1 -name '*.bak' -print 2>/dev/null | wc -l | tr -d ' ')"
N7_RC=$?
N7_ALL="$(find "${N7D}/a" -name '*.bak' -print 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N7_RC" -eq 0 ] && [ "$N7_TOP" = "1" ] && [ "$N7_ALL" = "2" ]; then
    pass "N7 find -maxdepth 1 이 이 플랫폼에서 정상 동작 (깊이 제한 1 vs 전체 2)"
else
    fail "N7 find -maxdepth 미동작 (rc=${N7_RC}, top=${N7_TOP}, all=${N7_ALL}) — prune 이 조용히 무효가 된다"
fi
rm -rf "$N7D"

# ============================================================================
echo "=== N8: prune 은 installer 가 만든 '일반 파일' 백업만 지운다 ==="
# ============================================================================
# 사용자가 <file>.bak 이라는 이름의 디렉토리를 갖고 있을 수 있다. 이름만 보고
# rm -rf 하면 사용자 디렉토리가 통째로 날아간다.
N8D="$(mktemp -d)"
N8T="${N8D}/target.txt"
printf 'v0\n' > "$N8T"
mkdir -p "${N8T}.bak.9"                       # 사용자 디렉토리 (이름만 백업 형태)
printf 'user data\n' > "${N8T}.bak.9/keep.txt"
i=1
while [ "$i" -le 5 ]; do
    printf 'v%s\n' "$i" > "${N8T}.bak.${i}"
    touch -t "20260${i}010101" "${N8T}.bak.${i}"
    i=$((i + 1))
done
MANIFEST_BACKUP_KEEP=2
export MANIFEST_BACKUP_KEEP
own_and_prune "$N8T" "${N8T}.bak.1" "${N8T}.bak.2" "${N8T}.bak.3" "${N8T}.bak.4" "${N8T}.bak.5"
if [ -d "${N8T}.bak.9" ] && [ -f "${N8T}.bak.9/keep.txt" ]; then
    pass "N8 이름이 백업 형태인 사용자 디렉토리는 보존"
else
    fail "N8 prune 이 사용자 디렉토리를 rm -rf 로 삭제함"
fi
N8_LEFT="$(find "$N8D" -maxdepth 1 -type f -name 'target.txt.bak.*' | wc -l | tr -d ' ')"
if [ "$N8_LEFT" -eq 2 ]; then
    pass "N8 일반 파일 백업은 상한(2)까지 정리됨"
else
    fail "N8 일반 파일 백업이 ${N8_LEFT}개 (기대 2)"
fi
rm -rf "$N8D"

# ============================================================================
echo "=== H1: snapshot_tree 이식성 — shasum 이 없어도 빈 스냅샷을 만들지 않는다 ==="
# ============================================================================
# shasum 을 직접 부르고 오류를 삼키면, 그 도구가 없는 환경에서 스냅샷이 **비어서**
# 롤백·멱등 비교가 무조건 통과한다(거짓 안심). 이식 가능한 해시 헬퍼를 타야 한다.
H1D="$(mktemp -d)"
mkdir -p "${H1D}/tree"
printf 'alpha\n' > "${H1D}/tree/a.txt"
printf 'beta\n'  > "${H1D}/tree/b.txt"
H1_SHIM="${H1D}/shim"; mkdir -p "$H1_SHIM"
printf '#!/bin/bash\nexit 127\n' > "${H1_SHIM}/shasum"; chmod +x "${H1_SHIM}/shasum"

H1_OUT="$( PATH="${H1_SHIM}:${PATH}" snapshot_tree "${H1D}/tree" )"
if [ -n "$H1_OUT" ]; then
    pass "H1 shasum 부재에도 스냅샷이 비지 않음"
else
    fail "H1 shasum 부재 시 빈 스냅샷 — 롤백/멱등 비교가 무조건 통과한다"
fi
printf 'CHANGED\n' > "${H1D}/tree/a.txt"
H1_OUT2="$( PATH="${H1_SHIM}:${PATH}" snapshot_tree "${H1D}/tree" )"
if [ -n "$H1_OUT2" ] && [ "$H1_OUT" != "$H1_OUT2" ]; then
    pass "H1 shasum 부재에도 내용 변화를 실제로 탐지"
else
    fail "H1 shasum 부재 시 변화를 탐지하지 못함"
fi

# ============================================================================
echo "=== H2: snapshot_tree 는 모드·심볼릭 링크·빈 디렉토리까지 본다 ==="
# ============================================================================
# 내용 해시만 보면 실행 비트 소실, 링크→일반파일 변질, 빈 디렉토리 잔존을
# 롤백 비교가 놓친다 — 새로 넣은 chmod/경로 상태 롤백이 사실상 미검증이 된다.
# 각 차원을 **독립된 쌍**으로 검사한다(한 쌍에 여러 차이를 섞으면 다른 이유로
# 우연히 통과한다 — 실제로 그렇게 통과했다).
H2ROOT="$(mktemp -d)"
h2_pair() {   # $1 = 케이스명 → ${H2ROOT}/$1/a, .../b 를 만들고 공통 파일을 넣는다
    mkdir -p "${H2ROOT}/$1/a" "${H2ROOT}/$1/b"
    printf 'same\n'   > "${H2ROOT}/$1/a/file.txt"
    printf 'same\n'   > "${H2ROOT}/$1/b/file.txt"
    printf 'target\n' > "${H2ROOT}/$1/a/target.txt"
    printf 'target\n' > "${H2ROOT}/$1/b/target.txt"
}
h2_diff() {   # $1 = 케이스명 → 두 스냅샷이 달라야 한다
    [ "$(snapshot_tree "${H2ROOT}/$1/a")" != "$(snapshot_tree "${H2ROOT}/$1/b")" ]
}

h2_pair mode
chmod 755 "${H2ROOT}/mode/a/file.txt"
chmod 644 "${H2ROOT}/mode/b/file.txt"
if h2_diff mode; then
    pass "H2 실행 비트 차이를 탐지"
else
    fail "H2 모드 차이를 놓침 — chmod 롤백이 검증되지 않는다"
fi

h2_pair link
ln -s "target.txt" "${H2ROOT}/link/a/thing"      # 링크
printf 'target\n' > "${H2ROOT}/link/b/thing"     # 같은 내용의 일반 파일
if h2_diff link; then
    pass "H2 심볼릭 링크 vs 일반 파일을 구분"
else
    fail "H2 링크가 일반 파일로 바뀐 것을 놓침"
fi

h2_pair linktarget
ln -s "target.txt" "${H2ROOT}/linktarget/a/thing"
ln -s "other.txt"  "${H2ROOT}/linktarget/b/thing"   # 링크 대상만 다르다
if h2_diff linktarget; then
    pass "H2 심볼릭 링크의 대상 차이를 탐지"
else
    fail "H2 링크 대상이 바뀐 것을 놓침"
fi

h2_pair emptydir
mkdir -p "${H2ROOT}/emptydir/a/leftover"            # 빈 디렉토리 잔존
if h2_diff emptydir; then
    pass "H2 빈 디렉토리 잔존을 탐지"
else
    fail "H2 빈 디렉토리를 놓침 — 경로 상태 롤백이 검증되지 않는다"
fi
rm -rf "$H2ROOT"
rm -rf "$H1D"

# ============================================================================
echo "=== N9: 백업 소유는 경로가 아니라 '그 내용' 이어야 한다 ==="
# ============================================================================
# 색인이 경로만 담으면, 설치기 백업이 지워진 뒤 사용자가 같은 이름을 재사용했을 때
# retention 이 그 사용자 파일을 "우리 것" 으로 보고 지운다.
N9D="$(mktemp -d)"
N9T="${N9D}/target.txt"
N9MAN="${N9D}/.manifest"
printf 'v0\n' > "$N9T"
# 설치기가 만든 백업 1개를 등록한 뒤 그 파일을 지운다 (사용자가 치웠다고 가정)
printf 'installer backup\n' > "${N9T}.bak"
manifest_backup_record "$N9MAN" "${N9T}.bak"
rm -f "${N9T}.bak"
# 사용자가 같은 이름을 재사용
printf 'USER FILE — do not delete\n' > "${N9T}.bak"
# 설치기 백업들을 더 만들어 상한을 넘긴다
i=1
while [ "$i" -le 4 ]; do
    printf 'installer v%s\n' "$i" > "${N9T}.bak.${i}"
    manifest_backup_record "$N9MAN" "${N9T}.bak.${i}"
    touch -t "20260${i}010101" "${N9T}.bak.${i}"
    i=$((i + 1))
done
touch -t 202512010101 "${N9T}.bak"     # 가장 오래됨 → 이름 기준이면 1순위 삭제
MANIFEST_BACKUP_INDEX="$(manifest_backup_index "$N9MAN")"
export MANIFEST_BACKUP_INDEX
MANIFEST_BACKUP_KEEP=2 manifest_prune_backups "$N9T"
if [ -f "${N9T}.bak" ] && grep -q 'USER FILE' "${N9T}.bak"; then
    pass "N9 경로를 재사용한 사용자 파일은 삭제되지 않음"
else
    fail "N9 경로만 보고 사용자 파일을 삭제함 (내용 기반 소유 판정 부재)"
fi
rm -rf "$N9D"

finish
