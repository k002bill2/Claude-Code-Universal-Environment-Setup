# HANDOFF — 글로벌 교차리뷰 게이트 보안 하드닝 (2026-09-10)

> **이 문서는 실제 실행 출력만 근거로 쓴다.** 통과했다고 적힌 것은 전부 이 워크트리에서
> 포그라운드로 돌려 확인한 값이다. 미검증인 것은 미검증이라고 적었다.

## 0. 한 줄 요약

교차리뷰 게이트를 **12라운드**의 독립 Codex 검토로 하드닝했다. 이전 핸드오프가 남긴 미해결
**F1·F2·F3 은 전부 닫혔고**(§4 참조 — 설계 갈래 A/B 대신 제3안으로 해결), 라운드 7~12 가 새로 찾은 P1 9건·P2 3건도 닫았다. **남은 것은 provider live smoke(H3) 하나**이며 그것은
Rollout HOLD 가 금지한 실행이라 사람 승인 없이는 닫을 수 없다.

> **갱신 이력**: 2026-09-10 세션 2 (라운드 7~~11). 이전 판(세션 1, 라운드 1~~6)의 §4
> "미해결 blocker" 는 더 이상 유효하지 않다 — 아래 §4 가 그 결말을 기록한다.

## 1. 작업 범위와 금지사항 (그대로 유지할 것)

- 작업 위치: `/Users/younghwankang/orca/workspaces/Claude-Code-Universal-Environment-Setup/in-session-cross-review`
- **금지**: `~/.codex`·자격증명·원격 Git 수정, **provider live smoke**, 워크트리 밖 쓰기.
- 2026-09-11 사용자 승인으로 해제된 항목: commit(`89fab45`), 전역 활성화
(`install.sh --global-only --with-cross-review` 적용 완료). push 는 아직 하지 않았다.
- 계약 문서: `docs/plans/2026-09-09-global-in-session-cross-review.md` (§7.3 이 보안 생애주기,
§10 이 테스트 매트릭스, §12 가 Rollout HOLD).

## 2. 현재 상태 (실측 — 2026-09-10 세션 2)

```
bash tests/test-in-session-cross-review.sh   → PASS 304 / FAIL 0 / SKIP 0
bash tests/test-install.sh                   → PASS  92 / FAIL 0
bash tests/test-lifecycle.sh                 → PASS 149 / FAIL 0
bash tests/test-fragments.sh                 → PASS  99 / FAIL 0
bash tests/test-manifest.sh                  → PASS  22 / FAIL 0
bash tests/test-merge-settings.sh            → PASS  46 / FAIL 0
bash scripts/sync-from-live.sh --dry-run     → 변경 0건 (repo↔live 드리프트 없음)
bash -n (cross-review 6종 + 스위트) · python3 ast.parse safe-fs.py → 전부 ok
~/.claude/state/cross-review                 → 미생성 (실 HOME 무오염, X31)
```

**사보타주(RED) 검증**: 이 세션의 모든 수정은 방어를 되돌려 해당 테스트가 RED 가 되는지
확인했다 — 라운드 7 3건(X58·X59·X60), 라운드 8 3건(X61·X62·잠금), 라운드 9 4건
(X54·X63·X64 + X65 는 사전·사후 대조 동시 무력화로 별도 확인).

커밋하지 않았다(핸드오프 §1 금지사항 유지). 파일은 intent-to-add(`AM`/ `A`) 상태다.

## 3. 닫힌 것 (재작업 금지 — 회귀 테스트가 지키고 있다)


| 항목                  | 내용                                                                     | 감시 테스트      |
| ------------------- | ---------------------------------------------------------------------- | ----------- |
| provider 원문 영속      | 봉투·result.json 을 전부 제거, stdout 파이프 → 셸 변수로만 흐름                         | X41·X48·X53 |
| 결과 경로 사전 심기         | 예측 가능한 영속 경로 자체를 없앰                                                    | X42         |
| 쓰기·삭제 TOCTOU        | 관리 루트 하위 전 연산을 `safe-fs.py`(성분별 `O_NOFOLLOW` + pinned 부모 fd)로 위임       | X43·X46     |
| 관리 성분 링크            | root 를 신뢰 홈 접두부로 두어 `state`·`cross-review` 자체도 검사, 경로 chmod → `fchmod` | X46         |
| 저장소 통제 git 실행       | `diff.external`/`textconv`/`fsmonitor` 무력화                             | X47         |
| 결과 계약               | `jq -s` 로 전수 검증(정확히 1객체·필수·타입·미지 필드 금지)                                | X49         |
| 수집 오류·특이 파일명        | base 검증, rc 0/1 만 정상, `-z` 열거 + sentinel                               | X50         |
| 1000개 상한 스윕         | 유계 스윕 제거, 이름공간 한정 무제한 스윕                                               | X44         |
| 빈 diff 에 PASS       | 동결 diff 읽기 하드 실패(`prompt_incomplete`)                                  | X56         |
| Stop 가드 ambient tmp | mktemp 제거, 스트림 해시                                                      | X52         |


## 4. 이전 미해결의 결말 (F1·F2·F3 닫힘) + 남은 것

### 4.1 설계 갈래 A/B 대신 제3안

이전 판은 "(A) 동시성 지원 포기 / (B) 드라이버를 Python 으로 재작성" 중 사람이 고르라고
했고, 그 전제는 **"셸이 flock 서술자를 직접 쥘 수 없다"** 였다. 그 전제가 틀렸다(실측):

- flock 은 **열린 파일 기술(OFD)** 에 걸린다. 셸이 `exec 9>>lock` 으로 열고, `safe-fs.py flockfd <root> <rel> 9` 가 **그 fd 를 상속받아** 잠그면, python 이 끝나도 잠금은 셸의
fd 에 남는다. 놓는 방법은 fd 를 닫는 것뿐이고 셸이 죽으면 커널이 해제한다.
- 즉 **잠금 수명 = 리뷰 프로세스 수명**. 상주 헬퍼도, 감시할 PID 도, `kill` 도 없다.
- 재작성 없이 동시성 보장을 유지했다. 계약 문서 §7.3.6 에 설계와 실측 근거를 적었다.

### 4.2 닫힌 항목


| #      | 결말                                                                                                          | 감시 테스트 |
| ------ | ----------------------------------------------------------------------------------------------------------- | ------ |
| **F1** | prune 이 남의 잠금을 **쥔 채로** 삭제한다(`rs_lock_take`/`rs_lock_untake`). 잡았다 놓는 옛 probe 는 순수 질의용으로만 남겼다               | X59    |
| **F2** | 상주 헬퍼(`lockhold`) 를 제거하고 OFD 소유로 전환 (§4.1)                                                                  | X58    |
| **F3** | `rs_set_pending`/`rs_clear_pending` 이 실패를 전파. 예약 기록 실패 시 **방금 만든 클레임도 롤백**한다 — 롤백 없이 차단만 하면 그 sha 가 영구히 막힌다 | X60    |


### 4.3 라운드 8~12 가 새로 찾아 닫은 것


| 심각도     | 내용                                                                                                                                                                                             | 감시 테스트 |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| P1      | unborn 저장소에서 `git diff` 가 **스테이지된 첫 커밋을 통째로 누락** → 빈 diff 를 리뷰하고 실제 sha 로 PASS. 빈 트리 비교로 교체                                                                                                    | X61    |
| P1      | 종결 상태 기록 실패를 삼켜 **reviewed_sha 없이 PASS** 를 알림(Stop 가드가 볼 근거가 없다)                                                                                                                               | X62    |
| P1      | Claude reviewer 가 **호출자의 cwd** 를 상속 — `--add-dir` 은 접근 경로를 더할 뿐 cwd 를 바꾸지 않는다                                                                                                                  | X63    |
| P1      | 잠금 fd ↔ 경로 (dev,ino) 결속 (사전 + **flock 이후 재대조**)                                                                                                                                                | X65    |
| P2      | 잠금 경합에서 거절된 쪽이 **잠금 소유자의 state.tsv 를 덮어씀** → 출력으로만 알리도록 변경                                                                                                                                     | X54    |
| P2      | run 아티팩트 정리 실패를 삼켜 동결 diff 가 전역 상태에 잔류하는데 PASS                                                                                                                                                 | X64    |
| P1      | `git status`·`git diff` 가 **대상 저장소의 `.git/index` 를 다시 쓴다**(stat 갱신). 읽기 전용 검증이 저장소를 변형했고 porcelain 비교는 그것을 보지 못한다. `--no-optional-locks` + `diff.autoRefreshIndex=false` — **두 스위치 모두** 필요(실측) | X66    |
| P1      | 동결 diff 를 **전량 전역 상태에 쓴 뒤** 크기 게이트가 거절 — 거절될 리뷰가 디스크를 임의 크기만큼 차지(실측 171KB). 쓰기 중 상한(safe-fs 스트리밍 cap)으로 이동                                                                                     | X67    |
| P1      | 설치 전제는 "jq 또는 node" 인데 게이트는 jq 를 실제로 요구 — node 만 있는 환경에서 opt-in 이 **조용히 무동작**(Stop advisory 없음 + 모든 리뷰 BLOCKED). 설치 거부 + 가드 경고                                                                 | X68    |
| P1 | 잠금 fd 를 셸이 열기 전 `nolink` 확인 추가 — 링크 창 축소 (§4.4) | X58 |
| P2      | `os.write` 짧은 쓰기를 무시해 잘린 동결 diff 의 해시로 PASS 가능 → `_write_all` 루프 (전용 테스트 없음: 정규 파일에서 짧은 쓰기를 결정적으로 유발할 수 없다 — 코드 검토로 대체)                                                                        | —      |
| (자체 발견) | `exec 9>>f 2>/dev/null` 이 **셸 전체 stderr 를 영구히 죽인다** — 잠금 획득 이후 모든 진단이 사라졌다. `{ exec …; } 2>/dev/null` 로 범위 한정                                                                                  | X64    |


### 4.4 반영하지 않고 **문서로 종결**한 지적 (라운드 12)

| 심각도 | 내용 | 왜 고치지 않았나 |
|---|---|---|
| P1 | 잠금 파일을 셸이 열 때(`exec 9>>`) 링크를 따라갈 수 있다 — `touch` 와 열기 사이에 링크가 심기면 **링크가 가리킨 경로에 빈 파일이 생길 수 있다** | 셸 리다이렉션은 `O_NOFOLLOW` 를 못 쓴다. 열기 직전 `nolink` 확인 + 연 뒤 (dev,ino) 대조로 창을 좁혔고 잠금 자체는 거부된다. 같은 사용자가 그 파일을 직접 만들 수도 있어 **권한 상승은 없다**. 완전 차단은 드라이버를 Python 한 프로세스로 옮기는 재작성 — 계약 §11-4 |
| P1 | `--uninstall` 이 **바이트 단위로 동일한** 사용자 Stop 훅과 설치본을 구분하지 못한다 | identity 기반 제거는 **공용 병합 엔진**의 성질이라 모든 조각(pm2·verify·skill-overrides)에 동일하며 이 게이트가 만든 결함이 아니다. 명령이 다른 사용자 훅은 보존된다(X27). occurrence 추적은 병합 엔진 별도 작업 — 계약 §11-5 |

### 4.5 남은 미해결 — **H3 (live smoke)** 하나


| #      | 위치                                             | 내용                                                                                                                                                                                                                                                        |
| ------ | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **H3** | `run-codex-review.sh` / `run-claude-review.sh` | Codex `--output-schema /dev/fd/5` · `--output-last-message /dev/fd/4`, Claude `--restricted` + stdin 프롬프트가 **실 CLI 미검증**. 코드 결함이 아니라 검증 갭이며, Rollout HOLD 가 금지한 provider 실행이 있어야 닫힌다. 비호환 시 전부 BLOCKED(fail closed — 조용한 PASS 아님). 대안: `--json` stdout 파싱 |


#### 4.5.1 H3 스모크 절차 (다음 세션이 그대로 따를 것)

**전제 — 이것부터 확인한다.** Rollout HOLD(§12)가 금지한 provider 실행이므로 **사용자가
명시적으로 승인한 뒤에만** 시작한다. 승인 없이는 아래를 실행하지 않는다.

**격리 (실 환경 보호 — 이번 하드닝의 요지가 여기서 깨지면 안 된다).**

```bash
SB="$(mktemp -d)"; export HOME="$SB/home"; export CROSS_REVIEW_HOME="$SB/crhome"
mkdir -p "$HOME" "$CROSS_REVIEW_HOME"
unset CLAUDE_CONFIG_DIR
# 리뷰 대상은 **일회용 저장소**를 쓴다. 실제 작업 저장소를 대상으로 돌리지 않는다.
R="$(mktemp -d "$SB/repo.XXXX")"; git -C "$R" init -q
git -C "$R" config user.email t@t.local; git -C "$R" config user.name tester
printf 'base\n' > "$R/a.txt"; git -C "$R" add -A
git -C "$R" -c commit.gpgsign=false commit -qm init
printf 'changed\n' > "$R/a.txt"
```

끝난 뒤 `rm -rf "$SB"`, 그리고 `ls -d ~/.claude/state/cross-review` 가 **없음**인지 확인한다.

**실행 (한 번에 하나씩, 출력 전문을 남긴다).**

```bash
CROSS_REVIEW_TIMEOUT=180 bash global/cross-review/run-codex-review.sh \
    --worktree "$R" --author claude --task-id smoke-codex ; echo "exit=$?"
CROSS_REVIEW_TIMEOUT=180 bash global/cross-review/run-claude-review.sh \
    --worktree "$R" --author codex  --task-id smoke-claude ; echo "exit=$?"
```

**통과 기준 — 전부 만족해야 H3 가 닫힌다.**

1. `exit=0` 이고 `phase=PASS`(또는 지적이 있으면 `CHANGES_REQUESTED`/`P2P3_CLOSED`).
   `BLOCKED_ERROR(schema_invalid)` 는 **실패**다 — `/dev/fd` 를 못 읽었다는 뜻이다.
2. Codex: 출력 스키마를 `/dev/fd/5` 로 읽고 최종 메시지를 `/dev/fd/4` 로 썼다.
   → 결과가 비어 있지 않고 스키마 검증을 통과했으면 입증된 것이다.
3. Claude: 프롬프트가 **stdin** 으로 전달됐다. `--restricted` + `--permission-prompts none`
   조합이 **무인으로 종료**한다(멈춰서 입력을 기다리면 실패).
4. 타임아웃 경로: `CROSS_REVIEW_TIMEOUT=5` 로 재실행 → `BLOCKED_ERROR(provider_timeout)`,
   고아 프로세스 없음(`pgrep -f 'safe-fs.py|codex exec|claude -p'` 가 0).
5. 관리 트리에 잔류물 없음: `find "$CROSS_REVIEW_HOME" -type f \( -name 'prompt.txt' \
   -o -name 'schema.json' -o -name 'last.json' -o -name '*.diff' \)` 가 **빈 결과**.

**실패 시 대안 (이미 정해져 있다).** Codex 가 `/dev/fd` 를 못 열면 `--json`(stdout JSONL)
파싱으로 전환한다. 그 경우 최종 메시지 이벤트의 형태를 실측으로 확정한 뒤 필터를 쓰고,
필터가 빈 결과를 내면 **BLOCKED 로 끝나야 한다**(조용한 PASS 금지).

**닫을 때 갱신할 곳.** 계약 문서 §12-2 의 `live provider smoke = PENDING` 항목과 두 어댑터의
"live smoke 미검증" 주석. 실측 CLI 버전(`codex --version`, `claude --version`)을 함께 적는다.

## 5. 작업 방식 — 반드시 지킬 것

이 세션에서 **테스트가 초록인데 아무것도 검증하지 않던 사례가 4건** 나왔다. 그래서:

1. **사보타주 검증이 의무다.** 수정마다 방어를 되돌려 해당 테스트가 **RED 가 되는지 확인**하고
 복원한다. 이 세션에서 15건을 그렇게 검증했다(S1–S15).
2. **스트레스 테스트를 탐지력으로 믿지 말 것.** 12-way 동시 실행이 셸 기동 지터로 자연
 직렬화되어 실제 결함을 놓쳤다. **경합 주입**(래퍼 인터프리터로 특정 지점에서 상대를
 끼워 넣기)이 유일하게 결정적으로 잡았다 — 그 방식으로 rename 설계의 이중 소유자를 발견했다.
 패턴 예: `CROSS_REVIEW_PYTHON` 을 래퍼로 바꿔 특정 op 직후 경쟁자를 실행.
3. **purge 이후에 훑는 검사는 공허하다.** 아티팩트 존재 여부는 **그 아티팩트가 살아 있는
 시점**(provider 호출 시점, state.tsv 교체 시점)에 확인해야 한다.
4. **대조군을 둘 것.** X57 은 "pending 없는 클레임은 그대로 차단"이라는 대조군을 넣고서야
 롤백 제거를 탐지했다.
5. 스위트는 **포그라운드로** 돌린다(백그라운드는 신호 상속 때문에 가짜 실패를 만든다).
6. 사보타주 후 **복원 확인까지** 한 명령에 넣을 것. 이 세션에서 백그라운드로 밀린 명령이
 복원 전에 죽어 사보타주가 잔존한 적이 있다.

## 6. 참고

- 독립 검토 실행: `SCRIPT=$(ls ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1)`
→ `node "$SCRIPT" adversarial-review --background --scope working-tree "<focus>"`,
`status --all` / `result <job>` 로 폴링. 커밋 전이므로 scope 는 `working-tree` 다.
- 라운드 상한(CLAUDE.md 는 3): 이미 **12라운드**다. 라운드 12 에서 멈췄다 — 남은 지적이 (a) 셸의 구조적 한계라 완화+명시로 종결했거나 (b) 이 diff 밖(공용 병합 엔진)이기 때문이다. 매 라운드가 서로 다른 실제 결함을 찾고 있어
사용자 승인 아래 초과했다. 다음 세션도 **먼저 사용자에게 알리고** 진행할 것.
- `install.sh` 는 `global/cross-review/*.sh` 와 함께 `***.py` 도 배포**한다. `.sh` 만 배포하면
설치된 게이트가 모든 리뷰를 BLOCKED 로 끝낸다(X26 이 감시자).
- 

