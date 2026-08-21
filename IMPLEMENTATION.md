# IMPLEMENTATION — 기술 구현 세부사항

> 근거는 전부 실행 출력입니다. 수치는 `HANDOFF.md` 의 최종 실측과 일치합니다.

---

## 1. 소유권 manifest (`lib/manifest.sh`)

TSV 한 줄 = `<루트 기준 상대경로><TAB><설치 시점 해시>`.

- 글로벌 루트 = `~/.claude` → `~/.claude/.manifest`
- 프로젝트 루트 = `<PROJECT_DIR>` → `<PROJECT_DIR>/.manifest`

기록 해시는 "installer 가 마지막으로 그 파일에 쓴 내용"의 해시다. 따라서
`manifest[relpath] == 현재 dst 해시` ⇔ 설치 이후 사용자가 건드리지 않았다.

### 소유권 판정 (`install_managed_file` / `install_managed_dir` 공통)

| dst 상태 | 판정 | 동작 |
|----------|------|------|
| 없음 | — | 설치 + 기록 |
| manifest 미기록 · 내용 == 소스 | 이주(adopt) | 소유권 인수, UNCHANGED |
| manifest 미기록 · 내용 ≠ 소스 | 사용자 추가 | **보존** (SKIPPED) |
| 기록 해시 == 현재 해시 | installer 소유·미변경 | 갱신 |
| 기록 해시 ≠ 현재 해시 | 사용자 수정 | **보존** (SKIPPED) |

**adopt 규칙의 이유**: 이것이 없으면 manifest 도입 이전에 설치된 파일이 영원히
"소유권 불명"으로 남아 어떤 업그레이드도 받지 못한다. 내용이 소스와 바이트 동일하면
잃을 사용자 데이터가 없으므로 안전하게 인수할 수 있고, 이주가 수렴한다.
(L3/L4 는 그대로 통과한다 — 사용자가 편집한 순간 내용이 달라져 adopt 조건에서 빠진다.)

### manifest 바이트 안정성

`manifest_set` 은 remove-then-append 라 호출할 때마다 줄 순서가 바뀔 수 있다.
그런데 `.manifest` 는 `~/.claude` 안에 있어서 **멱등성 테스트가 해싱하는 대상**이다
(B2/E2/L2 는 HOME 전체 트리 해시를 비교한다). 그래서 **기록 값이 실제로 달라질 때만**
`manifest_set` 을 호출한다. 검증: 연속 2회 설치 후 `cmp` 로 바이트 동일 확인.

---

## 2. `install_managed_dir` 재작성 (P0)

### 회귀의 원인

```bash
# install_global
for d in "${SCRIPT_DIR}/global/skills/"*/   # d 끝에 '/' 가 붙는다
    install_managed_dir "$d" ...

# install_managed_dir (구버전)
rel="${src_file#$src/}"                     # 패턴이 '.../dev-docs//' 가 된다
```

접두 제거가 실패해 `rel` 에 절대경로 전체가 남는다 → 파일이 `dst/<절대경로>` 로
중첩 복사 → manifest 에도 절대경로 기록 → 이어지는 stale 정리가 "소스에 없는 소유
파일"로 보고 방금 쓴 파일을 삭제. 최종 상태는 **빈 스킬 디렉토리 19개**.

실측(수정 전): `find ~/.claude/skills -type f | wc -l` → `0`

### 수정

1. `src="${src%/}"` · `dst="${dst%/}"` 정규화.
2. 접두 제거가 실패하면(`rel == src_file`) 그 파일은 건너뛴다 — 절대경로 중첩 복사를
   **구조적으로** 불가능하게 만드는 방어선.
3. 디렉토리 단위 백업(`cp -Rp dst dst.bak`) 제거. 구버전은 `diff -rq` 로 동일성을
   판단했는데, 사용자가 파일 하나만 추가해도 diff 가 깨져 **매 실행마다 `.bak` 트리가
   증식**했다(실측: 재실행 1회당 `.bak` 29개 증가, L2 가 잡던 증상).
   파일 단위 판정에서는 덮어쓰는 대상이 "installer 가 쓴 뒤 아무도 안 건드린 파일"
   뿐이라 백업할 사용자 내용이 존재하지 않는다.
4. stale 정리는 관할 접두(`skills/<skill>/`)로 한정하고, **소유·미변경**일 때만 삭제.
5. `find -type d -empty -delete` 제거 — 사용자가 만든 빈 디렉토리까지 지웠다.
   대신 우리가 지운 파일의 상위만 `prune_empty_parents` 로 정리.

### 호출 단위 = 스킬 1개

`install_managed_dir` 은 스킬 **1개당 1회** 호출되므로 manifest 관할 접두는
`skills/<skill-name>/` 이다. L6 테스트가 원래 `skills/stale-skill/...`(존재하지 않는
최상위 스킬)을 심었기 때문에 어떤 호출의 관할에도 들지 않아 영원히 정리되지 않았다 —
테스트가 실제 호출 의미론과 어긋나 있었다. 실제 관리되는 디렉토리(`dev-docs`) 안에
실제 해시로 심도록 정정했다.

---

## 3. `--uninstall`

설치 정책의 역연산. 파일은 `기록 해시 == 현재 해시` 일 때만 제거, settings 는
`.settings-manifest` 가 기록한 hooks/permissions identity 만 제거.

### 선행 수정: `MERGE_MANIFEST` 배선

`lib/merge-settings.sh` 의 `unmerge_settings_fragment` 와 그 29개 테스트는 **이미
통과하고 있었다**. 그러나 `install.sh` 는 `MERGE_MANIFEST` 를 **어디서도 설정하지
않았다**(`grep` 결과 0건). 소유권이 기록되지 않으니 제거할 근거도 없었다 — 완성된
기능이 배선되지 않아 죽어 있던 경우다.

- 글로벌: `~/.claude/.settings-manifest`
- 프로젝트: `<project>/.claude/.settings-manifest`

제거 대상 fragment id 는 하드코딩하지 않고 **기록에서 직접 뽑는다**. 하드코딩하면
더 이상 배포하지 않는 옛 조각의 소유분이 영원히 남는다.

### 보존 계약

`*.bak` 은 남긴다(복구 수단을 제거가 지우면 안 된다). 위임 설치기 산출물은 이
manifest 밖이라 대상이 아니다. 재실행 멱등(L7-12 가 HOME 스냅샷으로 검증).

---

## 4. 실패 롤백

### 트리거를 EXIT 하나로 모은 이유

- ERR 트랩만으로는 `delegate_system_setup` 의 `exit 1` 을 못 잡는다(`exit` 는 ERR 을 발화하지 않는다).
- 시그널 트랩만으로는 `set -e` 실패를 못 잡는다.

→ `trap rb_finish EXIT` + `INSTALL_COMPLETE` 센티널. `INT`/`TERM` 은 `exit 130`/`exit 143`
으로 EXIT 트랩에 합류시켜 복원 경로를 하나로 유지한다.

### 저널

경로를 이번 실행에서 **처음** 건드리기 직전에 그 시점 상태를 기록한다
(`file` = 내용 사본 + `cp -p` 로 모드 보존, `absent` = 없었음). 최초 상태만 남기므로
같은 파일을 여러 번 고쳐도 복원 지점은 하나다. 실패 시 저널을 **역순**으로 되감는다.

추적 지점: 관리 파일/디렉토리 쓰기·삭제, manifest 갱신, `settings.json` 병합
(백업 경로는 결정적이라 호출 **전에** 미리 추적), `chmod +x`, uninstall 의 제거,
그리고 `manifest_prune_backups` 가 지울 수 있는 기존 `.bak` 들(`rb_track_backups`).

### 테스트가 거짓 양성이 되지 않게 한 방법

"mutation 전에 죽어서 복원된 것처럼 보이는" 함정을 막기 위해, 사보타주 스크립트가
죽기 직전에 **그 시점의 목적지 파일을 증거로 복사**한다. 그 사본에 업스트림 변경이
들어 있어야만(= 실제 변형이 이미 일어난 뒤에 실패했음이 증명되어야만) 복원 주장을
검사한다(L8A-2/L8A-3, L8B-2/L8B-3).

또한 케이스마다 fixture 리포를 새로 뜬다. 처음에 공유했더니 앞 케이스가 심은 업스트림
변경이 뒤 케이스의 **기준 설치에 이미 포함**되어, 아무것도 안 바뀌었는데 "복원됨"으로
통과하는 거짓 양성이 실제로 나왔다(실측 후 분리).

---

## 5. guardrails 조각 (P0 + 보안)

### P0 — 히어독이 stdin 을 먹었다

```bash
python3 << 'GUARD_BASH'   # 히어독이 python 의 stdin 이 된다
...json.loads(sys.stdin.read())...
GUARD_BASH
```

훅 페이로드가 python 에 도달하지 못해 `json.loads('')` 가 예외 → fail-closed → **exit 2**.
즉 **모든 Bash 명령과 모든 Edit/Write 가 차단**된다. 실측:

```
$ printf '%s' '{"tool_input":{"command":"npm run build"}}' | bash -c "$CMD"
malformed JSON: Expecting value: line 1 column 1 (char 0)
exit=2      # 0(허용) 이어야 한다
$ ... | bash -c "python3 << 'EOF' ... EOF"
python read from stdin: ''
```

수정: `python3 -c "$(cat <<'TAG' ... TAG)"` — 명령 치환으로 스크립트를 `-c` 인자에
넣으면 stdin 은 파이프 그대로 남는다.

**기존 F4 가 못 잡은 이유**: 조각의 command 문자열을 실행하지 않고 테스트가 자기
인라인 python 히어독을 돌렸다. F6 은 조각의 command 를 그대로 셸에 먹이고 페이로드를
stdin 으로 준다(= Claude Code 가 하는 방식).

### 경로 경계

부분 문자열 매칭(`'rm /dev' in c`, `p.startswith('/etc')`)이라 `/devops-notes.txt`,
`/etcd/config.yml`, `/devtools/x.ts` 같은 무고한 경로를 차단했다. 경계(`$` 또는 `/`)
인지 매칭으로 교체. `rm -rf /` 도 부분 문자열이라 `rm -rf /tmp/x` 를 막았다 —
루트/홈 "통째 삭제"만 매칭하도록 정정.

### Notification AppleScript 인젝션

외부에서 오는 `.message` 를 스크립트 소스에 보간하고 있었다. 실측 주입:

```
display notification "hi" with title "INJECTED" with title "Claude Code"
```

메시지를 **별도 인자**로 넘기도록 변경(`on run argv` / `item 1 of argv`).
`jq` 부재 시 조용히 빈 메시지가 되던 문제도 python3 폴백으로 보완.

---

## 6. 테스트 변경 요약

| 파일 | 변경 |
|------|------|
| `tests/test-lifecycle.sh` | L6 재작성(실제 관리 디렉토리·실제 해시 + 사용자 추가/수정 보존), L7 실동작 14건(+dry-run), L8 롤백 12건, L9 대용량 저널 롤백 5건, **L10 대괄호 경로 7건**, **L11 업스트림 제거 자산 스윕 10건**, **L12 레거시 MODELS.md 6건** |
| `tests/test-install.sh` | E1 소유권 모델에 맞게 정정 (아래 주의) |
| `tests/test-fragments.sh` | F2 권한 문법 재작성, F5 참조/SSOT 문맥 한정, F6 배포 훅 실행 검증 13건(+10MB 상한), F7 인젝션 3건, **F8 문서 계약 4건** |
| `tests/test-manifest.sh` | **N6 백업 생존자 신원 3건** |
| `tests/test-merge-settings.sh` | **M13 백업 생존자 신원 3건** |

### 테스트 인프라 버그: `grep -q` + `pipefail`

```bash
if bash install.sh --help 2>&1 | grep -q '\-\-uninstall'; then   # 경합
```

`grep -q` 는 첫 매치에서 즉시 종료한다 → 생산자가 SIGPIPE 로 죽는다 →
`set -o pipefail` 이 그걸 파이프라인 실패로 바꾼다. 도움말 출력이 2줄 늘어나자
재현되기 시작했다(3회 중 3회 FAIL). 출력을 변수에 먼저 받아 해결.
`grep -c` 는 입력을 끝까지 읽으므로 같은 문제가 없다.

### 주의 — E1 은 기대값이 뒤집힌 변경이다

`tests/test-install.sh` 의 E1 은 원래 **manifest 에 없는 파일을 목적지에 심고 제거되는지**
확인했다. 그것은 제거하기로 한 `rm -rf` 통째 교체 의미론이고, 새 소유권 모델에서는
정확히 "사용자 추가 파일" 의 정의라 **보존이 정답**이다. 두 주장은 동시에 성립할 수 없다.

정정 방식: stale 파일을 **실제 해시로 manifest 에 기록**해 소유 파일로 만들고(→ 제거 검증
유지), 별도로 **사용자 추가 파일**을 함께 심어 보존을 검증하는 assertion 을 추가했다.
하나였던 검증이 둘이 되었다. 이것은 지시받은 L2/L6/L7/L8 범위 **밖**의 테스트 의미론
변경이므로 리뷰에서 별도로 확인해 주십시오.


---

## 7. 독립 리뷰 지적 반영 (fix cycle 1/2)

### 7.1 백업 retention — `xargs -I{}` 가 정렬을 무력화

```bash
# 이전 (두 라이브러리 공통)
victim="$(find ... -print | xargs -I{} ls -td {} | tail -1)"
```

`-I{}` 는 **인자마다 ls 를 한 번씩** 실행한다. 즉 `ls -td` 가 매번 파일 하나를
정렬하므로 정렬이 존재하지 않는 것과 같고, 최종 순서는 find 의 디렉토리 나열
순서다. APFS 의 디렉토리 순서는 이름 해시 기반이라 재현성이 없다 —
같은 코드가 어떤 디렉토리에서는 우연히 맞고 어떤 디렉토리에서는 틀린다
(실측: N6 은 v2·v3·v5 생존, M13 은 우연히 정답).

교체: mtime 을 직접 읽어 `<mtime>\t<path>` 목록을 만들고 **한 번만** `sort -n`.
`stat` 은 GNU(`-c '%Y'`) → BSD/macOS(`-f '%m'`) 순으로 시도한다. macOS 의 stat 은
`-c` 를 모르는 옵션으로 거부(exit 1)하므로 이 순서가 안전하다(실측 확인).
GNU-only 플래그(`find -printf`, `ls --time-style`, `sort -z`)는 쓰지 않았다.

**테스트 강화**: 기존 N5/M12 는 개수만 셌다 — 그래서 "무엇을 지웠는지"를 검증하지
못했다. N6/M13 은 mtime 을 고정하고 **생존자 신원**을 확인하며, 이름 순서와 mtime
순서를 **역상관**시켜 디렉토리 순서에 의존하는 구현이 결정적으로 실패하게 만든다.

### 7.2 glob 메타문자 경로

`${var#$pattern}` 의 우변은 패턴이다. 경로에 `[ ] * ?` 가 있으면 접두 제거가
조용히 실패한다. 네 곳(`mf_resolve` 2곳, `install_managed_dir`, `install_global_docs`)
과 stale 정리의 관할 계산까지 다섯 곳을 `${dst#"$CLAUDE_HOME"/}` 형태로 인용했다.
`case` 문의 패턴(`"$CLAUDE_HOME"/*)`)은 이미 인용되어 있어 정상이었다.

방어선 두 개를 추가했다:
- `mf_resolve` 불변식 — MF_REL 이 비었거나 `/` 로 시작하면 즉시 실패. manifest 에
  절대경로가 들어가면 uninstall 이 대상을 못 찾고 stale 정리가 자기 기록을 지운다.
- 소스 접두 제거 실패 시 **즉시 실패**. 이전에는 조용히 `continue` 라서 대괄호
  리포 경로에서 "0개 설치 + exit 0" 이라는 최악의 침묵이 됐다.

### 7.3 루트 단위 stale 스윕

`manifest_source_candidates <scope> <relpath>` 가 manifest 항목을 그것을 만든 소스
경로로 되짚는다(관리 접두가 아니면 return 1 → 스윕 대상 제외). 후보가 전부 없으면
업스트림에서 제거된 자산이므로 소유·미변경일 때만 삭제한다.

`.claude/skills/`·`.claude/agents/` 는 `project/` 와 `examples/` 두 곳에서 올 수
있어 후보를 둘 다 낸다. docs 는 `normalize_docs_dirname` 의 역함수가 단사가 아니므로
역정규화·항등 두 후보를 모두 낸다(보수적: 하나라도 있으면 유지).

프로젝트 스윕은 examples/pm2 설치까지 끝난 **뒤**에 호출한다. 그 전에 돌리면 아직
설치되지 않은 옵션 자산을 훑게 되어 순서 의존이 생긴다.

### 7.4 권한 조각

`Bash(git add)` 는 정확 매칭이라 인자 있는 호출을 허용하지 못한다 — 인자 없는
`git add` 는 아무 일도 하지 않으므로 항목 자체가 무용지물이었다. 인자를 받는
명령만 `cmd:*` 접두 문법으로 바꾸고 무인자 명령은 정확 매칭을 유지했다.
`Bash(npm install)` 은 의도가 "package.json 기준 의존성 설치"이므로 정확 매칭을
유지했다 — `npm install <임의 패키지>` 는 프롬프트를 거치는 편이 맞다.

F2 의 낡은 "와일드카드 없음" 검사는 `:*` 를 오탐하므로, 금지 대상을
"공백 + `*`"(`Bash(git *)`) 로 좁혔다.

### 7.5 레거시 MODELS.md

git 이력 전수 조사(`git log` + 각 커밋의 heredoc 본문 해시)로 배포된 변형이
**1종**임을 확인했고, 옛 `install_managed` 가 `content="$(cat)"` → `printf '%s\n'`
로 쓰므로 파일 내용 해시가 본문 해시와 일치함도 확인했다
(`53d7b0c6…`). 따라서 해시 기반 제거가 안전하게 도출된다.

안내는 **보존한 경우에만** 나와야 한다. 처음 작성한 L12-3 은 로그에서 `MODELS.md`
라는 낱말만 찾아 일반 안내문에도 걸려 **항상 통과**했다 — 전용 표지
`[LEGACY-MODELS-KEPT]` 로 바꾸고, 제거한 경우/파일이 없는 경우에는 그 표지가
**없어야 한다**는 반대 방향 assertion(L12-3b, L12-4)을 함께 넣었다.

---

## 8. 독립 리뷰 지적 반영 (fix cycle 2/2)

전부 **RED → GREEN** 으로 진행했다. 각 항목의 RED 출력은 아래에 실제 실패 메시지로 남긴다.

### 8.1 P1-a — 소유 집합이 사용자 항목까지 삼켰다 (`lib/merge-settings.sh`)

조각이 선언한 identity 를 **전부** 소유로 기록하고 있었다. 그런데 그중에는 "사용자가
이미 settings.json 에 넣어둔 것과 우연히 같은 identity" 가 섞인다. 소유로 기록되면
`--uninstall` 이 사용자 항목을 지운다 — README Uninstall Policy 의 보존 계약 위반이다.

```
FAIL: M14 사용자가 이미 갖고 있던 hook 을 소유로 기록함 (uninstall 이 사용자 것을 지운다)
FAIL: M14 uninstall 이 사용자 allow 를 삭제함: []
```

수정: `foreign = (병합 전 settings 의 identity) - (이전 소유)`, `owned = new - foreign`.

**`prev` 를 빼는 것이 핵심이다.** 빼지 않으면 2회차 실행에서 우리가 지난번에 넣은
항목이 "이미 settings 에 있으니 사용자 것"으로 오판되어 소유 기록이 통째로 비고,
`--uninstall` 이 아무것도 못 지우는 상태가 된다. M14 는 이 **양방향**을 모두 고정한다
(사용자 선점분은 비소유 / 재실행 후에도 우리 것은 소유 유지).

`grep -F -x -v -f` 의 빈 파일 분기(`else cp`)는 grep 구현별 차이 때문에 남겨 둔다 —
step 3 이 이미 같은 이유로 `if [ ! -s new.txt ]` 를 갖고 있다.

### 8.2 P1-b — secret/credential 디렉토리 성분 차단 복원 (`guardrails.json`)

basename 만 검사해서 `secrets/config.yml` 이 통과했다(실측 exit 0).

```
FAIL: F6 secret 디렉토리 성분 차단 (secrets/config.yml) — exit 0, 기대 2
FAIL: F6 credential 디렉토리 성분 차단 (credentials/aws.json) — exit 0, 기대 2
```

수정: 경로 성분(`norm.split("/")`)이 `secret/secrets/credential/credentials`(+ 숨김
형태)와 **완전 일치**하면 그 아래 전부 차단. 성분 완전 일치라 `mysecrets-project/`,
`secretsmanager/` 같은 무고한 이름은 통과한다(F6 이 오탐 방향도 고정).
basename 부분문자열 검사(`my-secrets.txt`)는 기존 동작이라 그대로 둔다.

JSON 이스케이프는 **손으로 만지지 않았다** — `json.dumps` 로 재직렬화하고, 검증은
`jq empty` 가 아니라 **배포된 command 를 실제로 실행**해서 했다(F6). 이 문자열은
"JSON 안의 셸 히어독 안의 python" 3중 중첩이라 이스케이프 한 글자가 어긋나면
원래의 P0(모든 도구 차단)이 그대로 재발한다.

### 8.3 P1-c — 구버전 업그레이드 이주 (`MERGE_LEGACY_REMOVALS` 실배선)

`MERGE_LEGACY_REMOVALS` 는 엔진에만 있고 `install.sh` 는 한 번도 설정하지 않았다.
그래서 구버전 설치의 `Bash(npm *)`·`Bash(git *)`·`Bash(docker *)` 와 옛 guard 훅이
영원히 남았다.

```
FAIL: L13-2 광범위 권한 3건 잔존: ["Bash(docker *)","Bash(git *)","Bash(npm *)", ...]
FAIL: L13-3 옛 guardrails 훅(부분문자열 매칭 버전) 잔존
FAIL: L13-4 폐기된 Write(*.tsx) 훅 잔존
```

**배선만으로는 동작하지 않는다 — 이것이 이 항목의 함정이다.** 엔진은
`[ -f "$manifest" ]` 일 때 legacy 분기를 건너뛰는데, manifest 파일은 **첫 조각 병합에서
생성**된다. 그래서 같은 실행의 2번째 조각부터는 "파일이 있으니 legacy 아님"으로 판정돼
이주에서 빠진다 — 그리고 광범위 권한의 출처인 `cli-orchestration.json` 이 정확히 그
2번째다. 판정 기준을 **파일 존재 → 이 조각의 소유 기록 부재**(`[ ! -s "$prev_file" ]`)로
바꿔야 비로소 목표물에 닿는다.

폭발 반경은 `install.sh` 쪽 게이트가 제한한다: settings 경로별로 **실행 시작 시점의**
`.settings-manifest` 부재만 legacy 로 본다(`note_legacy_state`). 손으로 쓴
settings.json 에 처음 설치하는 사용자의 `Bash(npm *)` 를 지우지 않기 위해서다.

이주 근거는 `lib/legacy-identities.tsv` (base 438aaf9 조각 → `msf_extract_records`,
14건). 포맷이 `.settings-manifest` 와 같아 `msf_manifest_records` 를 그대로 재사용한다.
제거 대상 = (목록) − (이번 조각의 identity) 이므로 **지금도 배포하는 항목은 남고 폐기된
것만 사라진다**. 파일이 없으면 조용히 넘어가지 않고 `log_warn` + SKIPPED 로 알린다.

"결정론적으로 도출했다"는 주장을 검사로 바꿨다 — **F9** 가 매 실행마다 `git show
438aaf9:` 로 재생성해 shipped 파일과 `cmp` 한다.

### 8.4 P2 — `dev/*/.gitkeep` 소유권 기록

`ensure_gitkeep` 이 manifest 에 기록하지 않아 `--uninstall` 이 자기가 만든 표식을 남겼다.

```
FAIL: L14-2 manifest 에 기록 없음: 17줄
FAIL: L14-4 installer 소유 .gitkeep 잔존
```

기록은 **비-dry-run 분기에서만** 하고, 기존 `[ -e "$path" ]` 조기 반환은 그대로 둔다 —
그 반환이 곧 "사용자가 먼저 만든 `.gitkeep` 은 절대 인수하지 않는다"는 보장이고,
재실행 시 manifest 바이트가 흔들리지 않게 하는 장치이기도 하다(L14-3 이 고정).

### 8.5 P2 — 번들 문서의 죽은 주장 정리

`docs/**/*.md` 는 `~/.claude/docs/claude-code-setup/` 로 **설치되어 에이전트가 읽는다**.
설치기가 더 이상 하지 않는 일이 적혀 있으면 그것이 곧 하네스에 주입되는 오정보다.

- `MODELS.md` 를 설치물로 안내: 2곳 (`claude_code_setup_prompt.md`, `3대 프레임워크`)
- `settings.json` 에 `model` 을 박는 예시/지시: 4곳 (setup_prompt, 프로젝트별 템플릿,
  완벽 가이드북, Parallel Agents Safety Protocol)

모델 ID **참조표**(Opus 4.8 / Fable 5 …)는 건드리지 않았다 — 그건 설치기 동작에 대한
주장이 아니라 일반 레퍼런스다. JSON 예시는 콤마까지 맞춰 유효성을 유지했고, 편집한
문서의 모든 ```json 블록이 파싱되는지 확인했다(12블록). **F9** 가 두 주장 모두를 감시한다.

### 8.6 테스트 추가 요약

| 파일 | 추가 |
|------|------|
| `tests/test-merge-settings.sh` | **M14** 소유 집합 양방향 8건 |
| `tests/test-fragments.sh` | **F6** secret 성분 차단 8건, **F9** 드리프트+문서 계약 3건 |
| `tests/test-lifecycle.sh` | **L13** 구버전 업그레이드 이주 13건, **L14** gitkeep 소유권 6건 |

L13 의 구버전 fixture 는 identity 를 하드코딩하지 않고 `lib/legacy-identities.tsv` 에서
재구성한다. 데이터 파일 자체의 정확성은 F9 가 base 와 대조하므로 순환하지 않는다.

### 8.7 최종 실측

| 스위트 | 결과 |
|--------|------|
| test-manifest.sh | 12 PASS / 0 FAIL |
| test-merge-settings.sh | 40 PASS / 0 FAIL |
| test-fragments.sh | 70 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 88 PASS / 0 FAIL |
| **합계** | **290 PASS / 0 FAIL** |

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean ·
스모크 6종(멱등·dry-run 0 writes·uninstall 선택성·node 폴백 전체 설치·강제실패 롤백
바이트 복원·실제 `~/.claude` 불변).

---

## 9. 리뷰어 + Codex 지적 반영 (fix cycle 3/3)

### 9.1 이주 목록 과잉 주장 — `base` 전부가 아니라 `base - 현재`

`lib/legacy-identities.tsv` 가 base 의 **모든** identity(14건)를 담고 있었다. 그중 6건은
지금도 배포 중인 것과 동일하다(pm2 훅 2, verification 훅 3, cli-orchestration 의
SubagentStop 훅 1). 이 6건은 사용자가 독립적으로 직접 만들었을 수도 있는데, 이주 목록에
들어가면 `prev` 에 포함되고 → §8.1 의 `foreign = present - prev` 에서 빠지고 → **소유로
주장**되어 `--uninstall` 이 사용자 항목을 지운다.

```
FAIL: F9 이주 목록이 현재 배포 identity 6건을 포함 — 사용자 항목을 주장해 uninstall 이 지운다
FAIL: L15-2 uninstall 이 공유 identity 를 삭제함 — 이주 목록 과잉 주장
```

목록을 `base - 현재`(8건)로 좁혔다. **제거 동작은 달라지지 않는다** — `removals = prev - new`
이므로 공유분은 애초에 제거 대상이 아니었다. 달라지는 것은 소유 주장 범위뿐이다.
F9 가 드리프트(재생성 결과와 `cmp`)와 과잉 주장(현재 조각과의 교집합 0) 양쪽을 감시한다.

### 9.2 이주 대조(corroboration) — `.settings-manifest` 부재는 증거가 못 된다

Codex [P1]: 직접 관리하는 `settings.json` 에 우연히 `Bash(npm *)` 한 줄이 있으면,
manifest 가 없다는 이유만으로 legacy 로 분류돼 **사용자 설정이 삭제**된다.

구버전 설치기는 조각의 identity 를 **한꺼번에** 썼다. 그래서 "이주 목록이 통째로 들어
있음" 이 그 설치기의 지문이 된다. 목록 중 하나라도 빠져 있으면 사용자가 직접 쓴 것으로
보고 건드리지 않는다(`legacy_corroborated`). 부분 일치는 이주하지 않는다 — L17 이 고정.

이주가 실제로 발동하면 `log_warn` 으로 몇 건을 지웠는지와 `.bak` 위치를 알린다.
조용히 지우지 않는다.

### 9.3 조각 단위 이주 판정 — 스킵된 조각의 이주 기회 상실

Codex [P1]: 첫 실행에서 python3 이 없어 `guardrails` 병합이 스킵돼도
`cli-orchestration` 이 `.settings-manifest` 를 만든다. 다음 실행에서 파일 존재만 보면
"이주 완료"로 오판해 **옛 guardrails 훅(취약한 부분문자열 매칭 버전)이 영구히 남는다**.

판정 단위를 `settings` 파일에서 **(settings, fragment) 조합**으로 바꿨다 — 그 조각의 소유
기록이 없으면 아직 이주 전이다. L18 이 이 상태(manifest 에 cli-orchestration 기록만 있는
settings)를 직접 만들어 고정한다.

### 9.4 기존 빈 `.gitkeep` 인수

리뷰어 지적: `ensure_gitkeep` 이 **새로 만들 때만** 기록해서, base 438aaf9 이 이미 만들어
둔 `dev/active/.gitkeep` 은 영원히 소유권 불명으로 남고 `--uninstall` 이 자기 산출물을
남긴다.

```
FAIL: L16-1 기존 .gitkeep 이 소유권 불명으로 남음 (uninstall 이 산출물을 남긴다)
```

내용이 **비어 있으면** installer 가 만드는 것과 바이트 동일이라 잃을 사용자 데이터가
없다 → 인수한다(§1 의 adopt 규칙과 같은 근거). 내용이 있으면 사용자 파일이므로 인수하지
않는다(L16-2). 기록은 값이 실제로 달라질 때만 써서 재실행 멱등을 지킨다(L16-3).

### 9.5 인용된 보호 경로 우회

Codex [P1]: 경로 정규식이 "공백 다음의 인용 없는 경로" 만 봐서 `rm -rf "/etc"`,
`rm -rf "$HOME"` 가 **exit 0 으로 통과**했다. 파괴적 명령 가드에서 따옴표가 곧 우회
수단이면 가드가 아니다. (1차 리뷰에서 P3 로 기록했던 항목을 Codex 가 P1 로 재평가했고,
그 판단이 맞다.)

경로 검사 전용 사본에서 따옴표를 **공백으로** 치환한다(제거하면 토큰이 붙어 경계가
무너진다). 원본은 파괴적 명령 검사에 그대로 쓴다. 오탐 방향(`rm -rf "/tmp/x"`)도 F6 이
함께 고정한다.

### 9.6 보존된 사용자 훅에 `chmod` 금지

Codex [P2]: `install_managed_file` 이 사용자 수정 훅을 보존하고 조기 반환해도, 뒤따르는
`chmod +x` 가 **무조건** 실행됐다. 보존 계약을 내용이 아니라 권한 쪽에서 깬다.
installer 소유·미변경(기록 해시 == 현재 해시)일 때만 권한을 손대도록 좁혔다(L19).

### 9.7 `msf_list_has` 의 SIGPIPE 취약성 (자체 발견)

`printf | grep -q` 로 썼는데, `grep -q` 는 첫 매치에서 즉시 끝나고 그러면 생산자가
SIGPIPE 로 죽으며 `set -o pipefail` 이 그것을 파이프라인 실패로 바꾼다 — 이 리포가 테스트
인프라에서 이미 당한 함정이다(§6). 지금은 목록이 짧아 파이프 버퍼에 다 들어가서 **우연히**
동작했다. 서브프로세스도 파이프도 없는 `case` 부분 일치로 교체했다.

### 9.8 최종 실측

| 스위트 | 결과 |
|--------|------|
| test-manifest.sh | 12 PASS / 0 FAIL |
| test-merge-settings.sh | 40 PASS / 0 FAIL |
| test-fragments.sh | 77 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 99 PASS / 0 FAIL |
| **합계** | **308 PASS / 0 FAIL** |

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean ·
스모크 7종(구버전 업그레이드 end-to-end · 멱등 · uninstall 선택성 · gitkeep 인수/제거 ·
node 폴백 · 강제실패 롤백 바이트 복원 · dry-run 0 writes · 실제 `~/.claude` 불변).

신규 테스트: **M14**(8) · **F6 secret**(8) · **F6 인용우회**(6) · **F9**(4) ·
**L13**(13) · **L14**(6) · **L15**(2) · **L16**(5) · **L17**(1) · **L18**(1) · **L19**(2).

---

## 10. Codex 게이트 반복 (cycle 4~7)

각 라운드마다 RED → GREEN 으로 처리했다. 라운드가 여러 번인 이유는 적대적 리뷰어가
**앞 라운드의 수정이 만든 새 표면**을 계속 겨눴기 때문이다(인용 우회 → 구분자 우회 →
경로 정규화 → 심볼릭 링크 → 조상 링크 → 삭제 경로의 링크 재검사).

### 10.1 guardrails — 우회 4종을 순차로 막았다

| 라운드 | 우회 | 실측 |
|--------|------|------|
| 3 | 인용된 보호 경로 | `rm -rf "/etc"` → exit 0 |
| 4 | 셸 구분자 경계 | `rm -rf /etc; echo ok` → exit 0 |
| 5 | 경로 표기(`..`, `//`) | `rm -rf /tmp/../etc/passwd` → exit 0 |
| 6 | 토큰 내부 인용 | `rm -rf /e"tc"` → exit 0 |

최종 형태: 따옴표를 **공백으로 바꾼 해석**과 **제거한 해석** 두 가지를 만들고, 각
토큰을 슬래시 축약 + `normpath` 로 정규화한 뒤, 경계 문자에 `;&|` 를 포함해 검사한다.
하나라도 걸리면 차단(보수적). 오탐 방향(`/tmp/x`, `./build`, `mysecrets-project/`)도
같은 수의 assertion 으로 고정했다.

**셸 브레이스 확장 함정**: `re.sub(r"/{2,}", ...)` 를 넣었더니 배포 경로에서
`re.sub(r"/2", ...)` 가 되어 있었다. 조각의 python 은 셸 히어독을 거치는데 셸이
`{2,}` 를 브레이스 확장으로 먹는다. 소스는 멀쩡한데 **배포본만 깨지는** 종류라,
`jq empty` 나 소스 검토로는 절대 안 잡힌다 — F6 이 배포된 command 를 실제로
실행하기 때문에 잡혔다. 정규식에 `{n,m}` 수량자 금지를 주석으로 못박았다.

### 10.2 경로 탈출 — manifest 는 신뢰 입력이 아니다

`.manifest` 는 프로젝트 안에 있어 리포가 값을 통제할 수 있다. `../../victim` 에 실제
해시를 맞춰 넣으면 관리 루트 밖 파일이 지워진다. 실측으로 **uninstall 뿐 아니라 일반
설치의 루트 스윕에서도** 삭제가 재현됐다.

`manifest_path_safe`(빈 값·절대경로·성분 `..` 거부)를 만들고 소비 지점 **3곳**
(uninstall, 루트 스윕, 관리 디렉토리 stale)에 모두 걸었다. 한 곳만 막으면 나머지가
그대로 뚫린다 — 실제로 처음엔 2곳만 막았다가 루트 스윕이 남아 있었다.

### 10.3 심볼릭 링크 — 최종 경로만으로는 부족하다

- 관리 디렉토리 자리의 링크 → `cp` 가 링크를 통해 밖에 씀 (실측: 바깥에 SKILL.md 생성)
- **조상** 경로의 링크(`.claude/skills` 자체가 링크) → 실측 **19개 파일**이 밖에 기록
- 설치 **이후** 링크로 바뀐 경우 → 삭제 경로가 링크 너머 파일을 지움

`path_ancestors_safe` / `managed_path_safe` 로 루트~대상 사이 **모든 성분**을 검사하고,
쓰기 경로와 **삭제 경로 양쪽**에서 호출한다. 삭제 직전 재검사가 따로 필요한 이유는
설치와 삭제 사이에 링크가 생길 수 있기 때문이다.

`settings.json` 이 링크인 경우는 예외로 두었다 — dotfiles 관리에서 흔하고 사용자가
의도한 것이다. 링크를 일반 파일로 갈아치우지 않고 `msf_resolve_link` 로 **대상 파일을**
갱신해 링크를 보존한다.

### 10.4 불완전한 체크아웃에서의 파괴적 스윕

`docs/` 하나만 빠진 사본으로 설치하면, 스윕이 후보 소스 부재를 "업스트림에서 삭제됨"
으로 읽어 **설치된 문서 21개 중 20개를 지우고 exit 0** 이었다. `global/` 이 통째로
빠진 경우는 병합 실패로 롤백돼 우연히 안전했을 뿐이다.

`source_root_of` 로 후보가 속한 최상위 소스 디렉토리를 보고, 그것이 없으면
**판단을 보류**한다(경고 + skip). 없는 근거로 지우지 않는다.

### 10.5 그 밖

- 소유 기록 실패 전파: `msf_write_manifest` 반환값을 무시해, 기록 경로가 디렉토리면
  `mv` 가 **그 안으로** 옮기고도 성공으로 보고했다. settings 는 바뀌고 기록만 없는
  = 영원히 uninstall 불가한 상태가 정상처럼 보였다. 비일반파일 경로 거부 + 사후 확인 +
  호출부 5곳 전파.
- `settings.json` 모드 보존: 원자적 `mv` 가 0600 을 0644 로 바꿨다. `msf_copy_mode`.
- `--uninstall --project <없는 경로>` 가 디렉토리를 새로 만들었다 — 제거가 파일시스템을
  늘리면 안 된다.
- 보존된 사용자 훅에 `chmod +x` 를 걸던 문제(보존 계약을 권한 쪽에서 깸).
- 디렉토리 충돌: 관리 파일 자리에 디렉토리가 있으면 `cp` 가 그 **안으로** 복사하고
  manifest 는 디렉토리를 설치 파일로 기록했다.

### 10.6 기각한 지적 — `find -maxdepth`

"BSD/macOS find 는 `-maxdepth` 를 지원하지 않는다" 는 지적이 **세 라운드에 걸쳐 반복**
올라왔다. 사실이 아니다. 실측:

```
$ /usr/bin/find a -maxdepth 1 -name '*.bak' -print   # exit 0
$ maxdepth1=1  전체=3                                 # 깊이 제한 정상 동작
$ man find | grep -c maxdepth                        # 5
```

M13/N5/N6(백업 생존자 신원)이 통과하는 것 자체가 `-maxdepth` 가 동작한다는 방증이다.
주장을 반박문으로 남기는 대신 **N7 카나리아 테스트**를 넣었다 — 정말로 지원하지 않는
환경이 생기면 그때 실패한다.

### 10.7 최종 실측

| 스위트 | 결과 |
|--------|------|
| test-manifest.sh | 13 PASS / 0 FAIL |
| test-merge-settings.sh | 40 PASS / 0 FAIL |
| test-fragments.sh | 95 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 124 PASS / 0 FAIL |
| **합계** | **352 PASS / 0 FAIL** |

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean.

---

## 11. 최종 사이클 (Codex 12차) 및 종료

리뷰 라운드를 12회 돌렸다. 라운드가 반복된 이유는 **앞 라운드의 수정이 새 표면을
만들었기 때문**이다(인용 → 구분자 → 정규화 → 심볼릭 링크 → 조상 링크 → 삭제 경로 →
백업 소유권). 12차 지적 3건을 마지막 사이클로 처리하고 종료했다.

### 11.1 백업 정리는 소유한 것만 (P1)

이름(`<file>.bak.N`)만 보고 지우면 사용자가 같은 이름으로 만들어 둔 파일이 사라진다
(실측: 사용자 백업 5건 중 2건 삭제). 설치기가 만든 백업 경로를 소유 색인에 적고
**그 목록 안에서만** 상한을 적용한다.

- 관리 파일: `<manifest 디렉토리>/.manifest-backups`
- settings: `<settings-manifest 디렉토리>/.settings-backups`

색인을 못 쓰면(생성 실패·디렉토리 등) **아무것도 지우지 않는다**(fail-closed).
"전부 우리 것" 으로 되돌아가는 폴백이 곧 사용자 백업 삭제 경로였다.

### 11.2 백업 색인도 롤백 대상 (P2)

`.settings-backups` 는 병합 중에 생성·수정되는데 저널에 없었다. 뒤 단계가 실패하면
나머지는 복구되고 이 파일만 남아 "바이트 단위 복구" 계약이 깨진다. `rb_track` 추가.

### 11.3 사라진 조각의 settings identity 정리 (P2)

파일 스윕은 `.manifest` 만 훑는다. 그래서 조각 파일이 리포에서 사라져도 그 조각이
이미 병합해 둔 hooks/permissions 는 `settings.json` 에 남아 **계속 실행**됐다.
`sweep_removed_fragments` 가 `.settings-manifest` 의 각 id 에 대해 소스 조각 존재를
확인하고, 사라진 것만 unmerge 한다. 조각 디렉토리 자체가 없으면 판단을 보류한다
(§10.4 와 같은 원칙).

주의: 조각이 없는데 `--with-verify-hooks` 로 **명시 요청**하면 하드 실패가 정답이다
(요청한 것을 조용히 건너뛰지 않는다). 스윕은 그 플래그 없이 도는 평범한 재설치에서
동작한다 — L39 가 이 구분을 고정한다.

### 11.4 최종 실측 (종료 시점)

| 스위트 | 결과 |
|--------|------|
| test-manifest.sh | 15 PASS / 0 FAIL |
| test-merge-settings.sh | 43 PASS / 0 FAIL |
| test-fragments.sh | 98 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 139 PASS / 0 FAIL |
| **합계** | **375 PASS / 0 FAIL** |

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean ·
스모크 7종(설치·멱등·dry-run 0 writes·node 폴백·강제실패 롤백 바이트 복구·
uninstall 잔여 0·실제 `~/.claude` 불변).

### 11.5 남은 사항

- 커밋/푸시/PR/머지는 수행하지 않았다 — 사용자 판단 사항.
- Codex 는 매 라운드 새 엣지 케이스를 낸다(적대적 리뷰어의 성질). 12차 지적까지
  반영했고, 라운드별 지적 수는 4 → 4 → 3 → 2 → 2 → 3 으로 좁아졌다. "0 이 나올
  때까지" 는 수렴이 보장되지 않으므로 여기서 경계를 지었다.
- 기각한 지적 1건: `find -maxdepth` 미지원 주장(3회 반복). 실측 반증 + N7 카나리아.

---

## 12. 마지막 사이클 (8건) 및 종료

리뷰어 확정 8건을 RED → GREEN 으로 처리했다.

| # | 등급 | 내용 | 수정 |
|---|------|------|------|
| 1 | P1 | 백업 슬롯 선택이 **깨진 링크를 빈 자리로** 봐 `cp -p` 가 관리 루트 밖을 씀 | 슬롯 판정에 `-L` 추가 + 쓰기 직전 fail-closed (install/merge 양쪽) |
| 2 | P2 | uninstall 저널이 `.settings-backups` 를 추적하지 않음 | `rb_track "$(msf_backup_index)"` 추가 |
| 3 | P2 | `for id in $ids` 가 공백·글로브 조각 id 를 쪼갬 | 두 루프를 줄 보존 `while read` 로 교체 |
| 4 | P2 | 테스트가 `shasum` 을 직접 호출해 부재 시 **빈 스냅샷** | 이식 가능한 해시 체인(shasum→sha256sum→cksum), 빈 값 금지, L21/L22 죽은 테스트 방지 |
| 5 | P2 | 스냅샷이 내용 해시만 봐 모드·링크·빈 디렉토리 변화를 놓침 | `snapshot_tree` 가 종류·모드·링크 대상·빈 디렉토리까지 기록 |
| 6 | P1 | 백업 소유 색인이 **경로만** 담아, 경로 재사용 시 사용자 파일 삭제 | 색인에 `경로+해시` 기록, 해시 일치할 때만 삭제 |
| 7 | P1 | unmerge 가 일치하는 identity 를 **전부** 제거 | identity 당 1회만 제거(jq/node 동일) + 다른 조각이 아직 소유한 identity 제외 |
| 8 | P2 | 시그널 테스트가 `$PPID` 로 쏴 스위트를 죽일 수 있음 | 런처가 자기 PID 기록 후 `exec` → 그 PID 에만 주입. 포그라운드 실행(배경은 SIG_IGN 상속으로 신호가 무시됨 — 실측) |

### 12.1 신규 회귀 테스트

`N9`(백업 경로 재사용) · `H1`(해시 이식성) · `H2`(스냅샷 완전성 4차원) ·
`M17`(settings 백업 경로 재사용) · `M18`/`M18b`(중복·공유 소유분 보존) ·
`L40`(백업 경로의 dangling 링크 2건) · `L41`(uninstall 색인 롤백) ·
`L42`(공백·글로브 조각 id 3건) · `L8S-SURVIVED`(스위트 생존).

### 12.2 최종 실측

| 스위트 | 결과 |
|--------|------|
| test-manifest.sh | 22 PASS / 0 FAIL |
| test-merge-settings.sh | 46 PASS / 0 FAIL |
| test-fragments.sh | 98 PASS / 0 FAIL |
| test-install.sh | 80 PASS / 0 FAIL |
| test-lifecycle.sh | 147 PASS / 0 FAIL (연속 3회 동일) |
| **합계** | **393 PASS / 0 FAIL** |

품질 게이트: `bash -n` 15/15 · `jq empty` 6/6 · `git diff --check` clean ·
스모크 7종(설치·멱등·dry-run 0 writes·node 폴백·강제실패 롤백 바이트 복구·
uninstall 잔여 0·실제 `~/.claude` 불변).
