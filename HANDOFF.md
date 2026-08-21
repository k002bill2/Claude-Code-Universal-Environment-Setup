# HANDOFF — harness-regression-fix (2026-08-21)

> 이 문서는 **실제 실행 출력**만 근거로 씁니다. 이전 판본의 "139/139 PASS · 모든 TODO 완료"
> 주장은 사실이 아니었습니다 — 같은 워크트리에서 재측정한 실제 값은 아래 *시작 시점 실측*입니다.

## 시작 시점 실측 (수정 전)

| 스위트 | 결과 |
|--------|------|
| test-merge-settings.sh | 29 PASS / 0 FAIL |
| test-manifest.sh | 9 PASS / 0 FAIL |
| test-install.sh | **71 PASS / 8 FAIL** |
| test-lifecycle.sh | **5 PASS / 4 FAIL** (L2·L6·L7·L8) |
| test-fragments.sh | 17 PASS / 0 FAIL |

## 근본 원인 — 관리 디렉토리가 전부 비어 있었다 (P0)

`install_global` 은 `for d in .../global/skills/*/` 로 **끝에 `/` 가 붙은** src 를 넘긴다.
`install_managed_dir` 의 `rel="${src_file#$src/}"` 는 패턴이 `.../dev-docs//` 가 되어
접두 제거에 실패하고, `rel` 에 **절대경로 전체**가 남았다. 그래서

1. 파일이 `dst/<절대경로>` 로 중첩 복사되고,
2. manifest 에도 절대경로가 기록되며,
3. 이어지는 stale 정리가 "소스에 없는 소유 파일"로 판단해 **방금 쓴 파일을 다시 지웠다**.

결과: `~/.claude/skills/<19개>` 가 **전부 빈 디렉토리**로 설치됨 (실측 `find -type f` = 0).
L5("managed-dir 사용자 파일 보존")가 통과하고 있었던 이유도 이것이다 — 관리 대상이
아예 없으니 훼손할 것도 없었다(공허한 통과).

## 수정 내역

- **install_managed_dir 재작성**: `src`/`dst` 말단 `/` 정규화, 접두 제거 실패 시 방어적
  skip, 디렉토리 단위 백업 제거(멱등 재설치 시 `.bak` 증식의 원인), 파일 단위 소유권 판정,
  경계 인지 stale 정리, 우리가 비운 디렉토리만 정리.
- **install_managed_file**: 공통 `mf_resolve` 사용, 내용이 소스와 동일하면 소유권 인수(adopt)
  → 이주가 수렴한다. manifest 는 값이 실제로 바뀔 때만 기록(바이트 안정성 확보).
- **`--uninstall` 신규**: 소유 파일/훅만 제거, 사용자 것 전부 보존, 멱등.
- **`MERGE_MANIFEST` 배선**: 이전에는 어디서도 설정되지 않아 settings 소유권 추적이
  통째로 죽은 코드였다(`unmerge_settings_fragment` 와 그 29개 테스트는 통과하고 있었지만
  실제 설치기에서는 한 번도 호출되지 않았다).
- **실패 롤백 신규**: EXIT 트랩 + 완료 센티널 + 역순 복원 저널.
- **guardrails P0**: 아래 별도 절.
- 문서: README(설치/제거/롤백 정책), install.sh 헤더, docs 설치기의 죽은 `MODELS.md` 참조 제거.

## guardrails 조각의 P0 — 모든 도구가 차단되고 있었다

배포되는 훅 명령이 `python3 << 'GUARD_BASH' ... GUARD_BASH` 형태였다. 히어독은
python 의 **stdin 을 대체**하므로 훅 페이로드가 사라지고 `json.loads('')` 가 예외를 던져
fail-closed 경로로 **exit 2** 가 된다. 즉 이 조각을 설치한 사용자는 **모든 Bash 명령과
모든 Edit/Write 가 차단**된다.

기존 F4 테스트가 이걸 못 잡은 이유: 테스트가 조각의 command 문자열을 실행하지 않고
자기 인라인 python 히어독을 돌렸다(공허한 검증). F6 은 조각의 command 를 **그대로**
셸에 먹이고 페이로드를 stdin 으로 준다.

함께 고친 것:
- **경로 경계**: `'rm /dev' in c` 식 부분 문자열 매칭 → `/devops-notes.txt`,
  `/etcd/config.yml` 같은 무고한 경로까지 차단하고 있었다. 경계(`$` 또는 `/`) 인지 매칭으로 교체.
- **`rm -rf /` 오탐**: 부분 문자열이라 `rm -rf /tmp/x` 도 차단했다. 루트/홈 "통째 삭제"만 매칭.
- **Notification AppleScript 인젝션**: 외부에서 오는 `.message` 를 스크립트 소스에
  보간하고 있었다. 실측 주입 결과:
  `display notification "hi" with title "INJECTED" with title "Claude Code"`.
  메시지를 별도 인자로 전달하도록 변경(F7 이 회귀 감시).

## 최종 실측 (수정 후)

| 스위트 | 결과 |
|--------|------|
| test-merge-settings.sh | 46 PASS / 0 FAIL |
| test-manifest.sh | 22 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 147 PASS / 0 FAIL |
| test-fragments.sh | 98 PASS / 0 FAIL |
| **합계** | **393 PASS / 0 FAIL** |

> 위 수치는 12차에 걸친 독립 리뷰 게이트를 모두 반영한 뒤의 최종 실측이다.
> 라운드별 지적과 처리 내역은 `IMPLEMENTATION.md` §7~§12 참조.

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean ·
temp-HOME 스모크 32/32 (dry-run·install·upgrade·uninstall·강제실패 롤백·node 폴백·
대괄호 경로 전 생애주기·업스트림 제거 자산 스윕, 그리고 실제 `~/.claude` 불변 확인).

## 독립 리뷰 지적 반영 (fix cycle 1/2 — P1 2건, P2 3건)

각 항목은 먼저 실패하는 회귀 테스트를 추가해 RED 를 확인한 뒤 최소 수정했다.

**P1-1 백업 retention 이 최신본을 지우고 있었다.**
`find ... | xargs -I{} ls -td {} | tail -1` 은 `-I{}` 때문에 **인자당 ls 를 한 번씩**
실행한다. 그래서 `ls -t` 가 파일 1개를 정렬하는 무의미한 연산이 되고, 결과 순서는
find 의 디렉토리 나열 순서(APFS 는 해시 기반이라 재현성 없음)가 된다.
mtime 을 직접 읽어 **한 번만** 정렬하도록 교체(`stat -c` → `stat -f` 폴백).
테스트는 개수만 세던 것을 **생존자 신원**까지 확인하도록 강화했고, 이름 순서와
mtime 순서를 **역상관**시켜 디렉토리 순서에 기대는 구현이 반드시 틀리게 만들었다
(그렇게 하기 전에는 M13 이 우연히 통과했다 — 실측으로 확인하고 고쳤다).

**P1-2 경로의 glob 메타문자가 manifest 를 오염시켰다.**
`${var#$pattern}` 의 우변은 **패턴**이라 `[ ] * ?` 가 특수문자로 해석된다.
`HOME=.../home[1]` → manifest 24/24 항목이 절대경로, 스킬 항목은 stale 정리가
스스로 지워 uninstall 이 아무것도 못 지움. 리포 경로에 대괄호가 있으면 스킬
**0개 설치 + exit 0**(조용한 실패). 네 곳 전부 인용으로 교체하고,
`mf_resolve` 에 "MF_REL 은 절대경로일 수 없다" 불변식을, 소스 접두 제거 실패에는
조용한 skip 대신 **즉시 실패**를 넣었다(롤백이 원상복구한다).

**P2-1 통째로 제거된 자산이 영원히 남았다.**
디렉토리 단위 stale 정리는 "이번에 열거된 디렉토리 안"만 본다. 스킬 디렉토리가
통째로 사라지거나 rules/agents 파일이 삭제되면 애초에 방문되지 않는다.
manifest 를 루트 단위로 훑는 스윕을 추가했다. 판정 기준은 "이번에 건드렸는가"가
아니라 **소스 존재 여부**다 — 전자로 하면 `--with-examples` 없이 재실행했을 때
이전에 깐 examples 가 지워진다(L11-9 가 이 성질을 감시한다).

**P2-2 권한 조각이 무용지물이었다.**
`Bash(git add)` 는 인자 없는 호출만 허용하는데 그런 호출은 아무 일도 하지 않는다.
인자를 받는 명령만 접두 문법(`Bash(git add:*)`)으로 바꾸고, 무인자 명령
(`git status`, `npm install`)은 정확 매칭을 유지했다. 광범위 권한
(`Bash(git *)`/`Bash(npm *)`/`Bash(docker *)`)은 복원하지 않았고, 되살아나면
F2 가 실패한다.

**P2-3 레거시 `.claude/MODELS.md` 가 남아 있었다.**
git 이력 전수 조사 결과 이 리포가 배포한 MODELS.md 본문은 **1종**뿐이라
해시 기반 제거가 안전하게 도출된다. 해시가 일치하면(= 손대지 않은 installer
소유물) 제거하고, 다르면(= 사용자 편집) 보존한 뒤 `[LEGACY-MODELS-KEPT]` 전용
안내로 수동 삭제를 요청한다(보존한 경우에만 출력 — L12-3b 가 감시).
사용자 `CLAUDE.md` 에 남을 수 있는 참조도 함께 정리하라고 안내한다.

## 마무리에서 추가로 잡은 것

- **대용량 저널 롤백(L9)**: L8 은 파일 1~2개만 바꾸고 실패해 저널이 짧다. `set -euo pipefail`
  은 트랩 안에서도 살아 있으므로, 저널이 길 때 복원 루프가 중간에 죽으면 "절반만 롤백된"
  트리가 남는다 — 롤백 없음보다 나쁘다. 관리 `.md` 35개를 한꺼번에 바꿔 저널을 키운 뒤
  실패시켜 검증했다: **63건 복원, HOME/PROJECT 모두 바이트 단위 일치**.
  (롤백을 끄면 HOME 52줄 / PROJECT 35줄 diff → 이 테스트는 공허하지 않다.)
- **10MB stdin 상한**: 이전 측정은 "모든 것이 차단되던" 버그 시점이라 상한을 증명하지
  못했다. 수정 후 재측정 — 11MB 는 `stdin exceeds 10MB limit` 사유로 exit 2, 0.9MB 는
  정상 통과(상한이 전부를 막는 것이 아님도 함께 증명).
- **`--uninstall --dry-run`**: README 가 문서화했지만 테스트가 없었다. 쓰기 0건 + 제거
  예정 항목 출력을 검증하는 assertion 추가(L7-D/L7-D2).
- **테스트 자체의 경합 버그**: `install.sh --help | grep -q` 는 `grep -q` 가 첫 매치에서
  즉시 끝나 생산자가 SIGPIPE 로 죽고, `set -o pipefail` 이 그것을 파이프라인 실패로
  바꾼다. 도움말에 2줄을 더하자 재현되기 시작했다(3회 중 3회). 출력을 먼저 변수에
  받도록 수정.

## 남은 사항 / 범위 밖

- **롤백 범위 한계(설계상)**: 위임 설치기(system-setup / advisor 번들)가 쓴 파일은
  저널 밖이라 롤백되지 않는다. "부분 설치 없음"은 이 설치기가 직접 쓴 것에 한한다.
- `docs/codex-advisor-worker-bundle/install.sh` 는 이번 범위에서 감사하지 않았다.
- `lib/merge-settings.sh` 는 이전 세션의 미커밋 작업이다. 이번에 `msf_prune_backups`
  는 직접 읽고 수정했지만(P1-1), **나머지 부분은 줄 단위로 리뷰하지 않았고 동작으로만**
  검증했다 — 32개 테스트 통과 + jq 없이(node 폴백) 전체 설치 스모크 + uninstall 실동작.
- **판단 결정 1 — 사용자 확정(2026-08-21)**: `Bash(npm install)` 은 정확 매칭으로
  유지한다. 리뷰어가 명시한 목록(`git add:*`, `git commit:*`, `npm run test:*`)에는
  없던 항목이라 "인자 없이 쓰는 명령" 범위를 넓혀 적용했고, 사용자가 이를 확정했다.
  근거: 무인자 `npm install` 은 package.json 기준 의존성 설치라는 실제 용도가 있고,
  `npm install <임의 패키지>` 까지 무조건 허용하는 것은 최소권한에 어긋난다.
  → `tests/test-fragments.sh` F2 가 이 결정을 회귀 감시한다(정확 매칭 존재 + 접두
  문법으로 바뀌지 않았는지).
- **판단 결정 2 (범위 한계)**: `LEGACY_MODELS_HASHES` 는 **이 리포의 git 이력**을
  전수 조사해 얻은 1종이다. docs 번들이 이 리포 밖에서 배포된 적이 있다면 다른 변형이
  존재할 수 있고, 그 경우 자동 삭제되지 않고 `[LEGACY-MODELS-KEPT]` 안내와 함께
  보존된다(안전한 방향의 실패). "전 세계에 정확히 1종" 이라는 뜻은 아니다.
- **비자명한 결합**: `manifest_prune_backups` 가 지우는 오래된 `.bak` 은 호출자에게
  어느 것을 지울지 알려주지 않는다. 롤백이 그것을 복원할 수 있는 이유는 호출 직전에
  `rb_track_backups` 로 `.bak` 집합 전체를 미리 추적해 두기 때문이다. 이 순서가 깨지면
  롤백이 조용히 백업을 잃는다.
- 경로에 개행이 포함되면 저널/manifest 가 깨진다(설치기 전체의 기존 가정과 동일).

## 상태

- Branch: `k002bill2/harness-regression-fix` (base `438aaf9`)
- **uncommitted** — 커밋/푸시/PR 은 사용자가 수행합니다.
