# In-Session Claude ↔ Codex 교차리뷰 게이트 — 구현 계획

> **SUPERSEDED (2026-09-09):** 이 문서의 배치 모델(프로젝트-로컬 `.claude/` 설치, 저장소 내
> self-ignore 상태)은 폐기됐다. 정본은 `docs/plans/2026-09-09-global-in-session-cross-review.md`
> (글로벌 opt-in 배포 프로필)이다. 아키텍처·상태 enum·스키마·게이트 규칙은 그 문서로 그대로
> 승계됐으므로, 이 문서는 배치 결정의 이력으로만 남긴다.

- 작성일: 2026-09-09 (KST)
- 상태: **구현 계획 확정 / rollout HOLD** (전역 활성화·live provider smoke 미수행)
- 상위 결정: `~/.hermes/profiles/jarvis/cron/output/2026-09-09-buzz-cross-review-final-discussion.md`
- 이전 설계: `~/.hermes/plans/2026-09-08_001830-in-session-cross-review-loop.md`

---

## 1. 근거

작성 agent 가 "완료" 를 선언하는 시점에, **같은 worktree 의 실제 소스를 반대편 provider 가
읽고 검토한 결과** 가 작성 세션 안으로 되돌아와야 한다. 지금까지의 시도는 두 가지에서 실패했다.

1. **Hook/scheduler 주도 리뷰** — 훅이 리뷰를 *실행* 하면 리뷰 결과가 작성 세션의 컨텍스트로
   돌아오지 않는다. 훅 출력은 세션 종료 경계에서 나오므로 "수정 → 재검토" 루프를 만들 수 없다.
2. **릴레이(Buzz) 기반 디스패치** — 전역 순서·원자적 claim 이 없어 `REVIEW_CLAIM` 방식은 TOCTOU
   이고, 표시명↔pubkey 가 1:N (실측 표시명 4 × pubkey 2) 이라 "한 리뷰어" 를 보장하지 못한다.

따라서 primary 는 **author session 내부의 동기 교차리뷰 루프**다. 훅은 리뷰를 호출하지 않고,
"세션 내 리뷰를 거치지 않은 diff 로 종료했다" 는 사실만 기록하는 보조 safety net 이다.

---

## 2. 범위 / 비범위

### 범위 (이번 구현)

| 산출물 | 역할 |
|---|---|
| `project/hooks/review-state.sh` | source 전용 공용 라이브러리 (상태·diff 동결·지문·엄격 파서) |
| `project/hooks/run-codex-review.sh` | Claude author → **Codex reviewer** 어댑터 |
| `project/hooks/run-claude-review.sh` | Codex author → **Claude reviewer** 어댑터 |
| `project/hooks/codex-with-review.sh` | Codex author 세션 래퍼 (완료 전 동기 리뷰 지시 주입) |
| `project/hooks/claude-review-current-diff.sh` | Codex author 가 부르는 얇은 front-end |
| `project/hooks/review-stop-guard.sh` | 좁은 Stop 훅 — 기록 전용 safety net |
| `project/settings-fragments/cross-review-gate.json` | **opt-in** Stop 배선 조각 |
| `install.sh` (최소 변경) | `--with-cross-review` 플래그. 소스 아티팩트 설치 + 명시 opt-in 배선 |
| `docs/codex-advisor-worker-bundle/install.sh` (최소 변경) | opt-in 안내 문구만 |
| `docs/cross-review-gate.md` | 운용 문서 |
| `tests/test-in-session-cross-review.sh` | 전용 테스트 스위트 |

### 비범위 (이번에 하지 않음)

- relay lock / `REVIEW_CLAIM` / Buzz 연동 — **구현하지 않는다**.
- 전역(`~/.claude`) 활성화, 실제 사용자 HOME 변경 — **하지 않는다**. temp HOME fixture 만 검증.
- live provider smoke (실제 Codex/Claude 호출) — **PENDING**. §8 참조.
- reviewer 가 소스를 수정하는 자동 remediation — 금지.
- 자동 재시도 / fail-open — 없음. 모든 실패는 fail-closed 상태값으로 남는다.
- commit / push / PR / merge / deploy.

---

## 3. 아키텍처

```text
author(Claude|Codex) 완료 후보 선언
  → 수정 중지 + diff 동결(sha256)
  → oversize/duplicate/attempt 게이트
  → 반대 provider reviewer 를 read-only 동기 실행
  → reviewer 전/후 tree 지문 비교 (write 탐지)
  → 결과 JSON 엄격 파싱 (schema + SHA 바인딩)
  → P0/P1 있으면: author 수정 → 같은 reviewer 1회 재리뷰
     P2/P3 뿐이면: 재리뷰 없이 종료(P2P3_CLOSED)
  → 그 외 모든 이상: BLOCKED_* (HITL)
```

Stop 훅(`review-stop-guard.sh`) 은 위 흐름에 **참여하지 않는다**. 종료 시점에
`현재 diff sha == 마지막으로 검증된 sha` 인지만 보고 아니면 `BLOCKED_UNREVIEWED` 를 상태에 기록하고
advisory 를 출력한 뒤 **항상 `exit 0`** 한다.

> **차단(`decision: block`)을 쓰지 않는 이유:** 확정 문서 §6 이 "차단" 과 "세션 종료 거부" 를
> 분리하라고 명시했고, Stop 훅이 세션을 되살리면 그 자체가 P0 재진입 경로다. fail-closed 는
> exit code 가 아니라 **상태값**으로 산다.

### 역할·provider 매핑 (고정)

| author | reviewer | 진입점 |
|---|---|---|
| `claude` | `codex` | `run-codex-review.sh` |
| `codex` | `claude` | `claude-review-current-diff.sh` → `run-claude-review.sh` |

author == reviewer 는 usage error(exit 2). 자기검토 불가.

---

## 4. 상태 모델

### 4.1 저장 위치 (worktree-local, self-ignoring)

```
<worktree>/.claude/cross-review/
  .gitignore                              # 내용: "*"  ← 스스로를 Git 에서 지운다
  tasks/<task_id>/
    state.tsv                             # key<TAB>value
    frozen/<sha>.diff                     # 동결된 diff 원본
    results/<sha>.<reviewer>.json         # reviewer 원문 결과 (엄격 검증 후 보관)
    claims/<sha>.<reviewer>               # 중복 호출 마커 (내용 없음)
```

> 프로젝트 `.gitignore` 를 편집하지 않는다. 상태 디렉터리가 자기 자신을 무시하므로
> 어떤 프로젝트에 설치돼도 리뷰 1 사이클 후 `git status --porcelain` 이 비어 있다.
> 이는 §6 의 tree 지문이 상태 파일 때문에 자기 자신을 "mutation" 으로 오탐하지 않게 하는
> 조건이기도 하다.

### 4.2 `task_id`

`--task-id` 로 명시하거나, 미지정 시 **결정적 fallback**:

```
task_id = sha256( realpath(worktree) + "\n" + scope + "\n" + base_ref )[0:16]
```

세션 id 는 plain wrapper 에서 접근 불가하므로 쓰지 않는다. `task_id` 는 **SHA 가 바뀌어도
불변** 이어야 한다 — attempt cap 이 여기에 걸리기 때문이다 (§5).

### 4.3 `state.tsv` 키

| key | 값 |
|---|---|
| `schema_version` | `1` |
| `task_id` | 위 정의 |
| `worktree` | 절대 realpath |
| `scope` | `working-tree` \| `branch` |
| `base_ref` | branch scope 의 base, 아니면 `-` |
| `phase` | §4.4 enum |
| `diff_sha256` | 마지막으로 **동결** 된 diff 의 sha256 |
| `reviewed_sha` | 마지막으로 **유효 검증을 통과** 한 diff 의 sha256 (없으면 `-`) |
| `reviewer` | `codex` \| `claude` \| `-` |
| `attempt` | 이 task 에서 소비한 모델 리뷰 호출 수 (정수) |
| `reason` | 짧은 슬러그. **자유 산문 금지** (§7) |
| `updated_at` | ISO8601 UTC |

쓰기는 항상 **전체 재작성 + atomic mv**. 부분 갱신(in-place sed)은 하지 않는다.

### 4.4 `phase` enum

| phase | 의미 | 후속 |
|---|---|---|
| `PENDING` | 등록만 됨 | 리뷰 실행 |
| `IN_REVIEW` | diff 동결·reviewer 실행 중 | — |
| `PASS` | P0/P1 0건 | 진행 가능 |
| `P2P3_CLOSED` | P2/P3 만 존재 → 재리뷰 없이 종료 | 진행 가능 |
| `CHANGES_REQUESTED` | P0/P1 존재 | author 수정 → 같은 reviewer 1회 재리뷰 |
| `BLOCKED_OVERSIZE` | files>30 또는 bytes>50KiB | 세션 분할 또는 명시 승인 |
| `BLOCKED_STALE` | 결과 JSON 의 sha ≠ 동결 sha | 재동결 후 재리뷰 |
| `BLOCKED_DUPLICATE` | 동일 `(sha, reviewer)` 재호출 | 수정 없이 재리뷰 시도 → HITL |
| `BLOCKED_ATTEMPTS` | task 당 리뷰 호출 2회 초과 | HITL |
| `BLOCKED_MUTATION` | reviewer 실행 전후 tree 지문 불일치 | HITL (read-only 위반) |
| `BLOCKED_ERROR` | missing/malformed 결과, timeout, provider 오류 | HITL |
| `BLOCKED_UNREVIEWED` | Stop 훅이 미검토 diff 로 종료 감지 | HITL |

`BLOCKED_*` 는 **전부 fail-closed**. 어떤 경로에서도 PASS 로 승격되지 않는다.

---

## 5. 게이트 규칙

### 5.1 중복 차단과 시도 상한은 **서로 다른 키**

| 규칙 | 키 | 한도 |
|---|---|---|
| 중복 호출 거부 | `(task_id, diff_sha256, reviewer)` | 1 |
| 시도 상한 | `task_id` (SHA 를 가로질러) | 2 |

정상 P0/P1 수정 후 재리뷰는 **새 SHA** 에서 일어나므로 중복 규칙에 걸리지 않는다. 반대로 시도
상한을 `(sha, reviewer)` 에 걸면 수정할 때마다 새 SHA 가 생겨 상한이 영원히 발화하지 않는다.
두 규칙을 반드시 분리한다.

### 5.2 P2/P3 종결

결과에 P0/P1 이 하나도 없고 P2/P3 만 있으면 `P2P3_CLOSED` 로 종결하고 **재리뷰하지 않는다**.
남은 지적은 호출자가 보고서/PR 본문에 남긴다.

### 5.3 Oversize

```
files > 30  OR  bytes > 51200  →  BLOCKED_OVERSIZE (모델 호출 0회)
```

`CROSS_REVIEW_ALLOW_OVERSIZE=1` 로 사람이 명시 승인해야만 통과한다. 자동 승격 없음.

### 5.4 훅 no-op 조건

- stdin JSON 의 `stop_hook_active == true`
- `CROSS_REVIEW_ROLE == reviewer` (reviewer 자식 프로세스가 게이트를 다시 부르는 것 차단)
- git 저장소 아님 / 상태 디렉터리 없음 / 변경 없음

---

## 6. reviewer 격리

### 6.1 명령 계약 (설치된 CLI 의 `--help` 로 실측한 플래그만 사용)

**Codex reviewer** — 스키마 강제를 CLI 가 한다:

```
codex exec \
  --cd <worktree> \
  --sandbox read-only \
  --output-schema <schema.json> \
  --output-last-message <raw.json> \
  --color never \
  -
```

**Claude reviewer** — `--restricted` + 도구 화이트리스트로 write 수단 자체를 제거한다:

```
claude -p \
  --restricted \
  --tools "Read,Grep,Glob" \
  --strict-mcp-config \
  --permission-mode manual \
  --permission-prompts none \
  --no-session-persistence \
  --output-format json \
  --add-dir <worktree>
```

> **비대칭인 이유:** `--tools` 는 *도구 이름* 단위이지 경로 단위가 아니다. Claude reviewer 에게
> `Write` 를 주면 결과 파일만이 아니라 worktree 어디에나 쓸 수 있어 read-only 계약이 깨진다.
> 그래서 Claude 쪽은 **모델이 파일을 쓰지 않는다**. `--output-format json` 의 `.result` 문자열을
> 래퍼가 받아 (선택적 코드펜스만 벗긴 뒤) 엄격 파싱하고, 래퍼가 결과 파일을 쓴다.
> Codex 쪽은 `--output-schema`/`--output-last-message` 를 **CLI 가** 쓰므로 모델 write 권한이
> 필요 없다.

### 6.2 tree 지문 (write 탐지)

reviewer 실행 **직전/직후** 에 같은 함수로 지문을 만들어 비교한다. 불일치 → `BLOCKED_MUTATION`.

지문 구성 (`git diff` 하나만으로는 staged 변경·신규 untracked 파일을 놓친다):

```
sha256(
  git rev-parse HEAD          +
  git status --porcelain      +
  git diff                    +
  git diff --cached           +
  각 untracked 파일의 sha256
)
```

추가로 reviewer 전후 `git diff --check` 를 실행해 whitespace 오류 유입을 잡는다.
상태 디렉터리는 §4.1 의 self-ignore 덕분에 이 지문에서 자동 제외된다.

---

## 7. 결과 JSON 스키마 (v1)

```json
{
  "schema_version": 1,
  "task_id": "a1b2c3d4e5f60718",
  "diff_sha256": "<64 hex>",
  "reviewer": "codex",
  "verdict": "PASS",
  "findings": [
    { "severity": "P1", "title": "…", "file": "path", "detail": "…" }
  ]
}
```

### 7.1 엄격 검증 규칙 — 하나라도 어기면 `BLOCKED_*`

| # | 규칙 | 위반 시 |
|---|---|---|
| 1 | 최상위가 JSON object 로 파싱됨 | `BLOCKED_ERROR` |
| 2 | `schema_version == 1` | `BLOCKED_ERROR` |
| 3 | `task_id` == 기대값 | `BLOCKED_ERROR` |
| 4 | `diff_sha256` == 동결 sha | **`BLOCKED_STALE`** |
| 5 | `reviewer` == 기대 reviewer (반대 provider) | `BLOCKED_ERROR` |
| 6 | `verdict ∈ {PASS, CHANGES_REQUESTED}` | `BLOCKED_ERROR` |
| 7 | `findings` 는 배열, 각 `severity ∈ {P0,P1,P2,P3}` | `BLOCKED_ERROR` |
| 8 | `verdict == PASS` ⟺ P0/P1 0건 (모순 금지) | `BLOCKED_ERROR` |

**산문에서 PASS 를 추론하지 않는다.** "looks good", "no issues found" 같은 텍스트는 결과가
아니다. 유효 JSON + 스키마 + enum 이 전부다. 결과 파일 부재 = `BLOCKED_ERROR` (PASS 아님).

### 7.2 영속 상태에 남기지 않는 것

`state.tsv` 에는 시크릿, 전체 프롬프트, raw 소스, provider stdout 원문을 **쓰지 않는다**.
`reason` 은 짧은 슬러그(`schema_invalid`, `sha_mismatch`, `timeout`, `oversize` …)만 허용한다.
reviewer 원문은 `results/*.json` 에만 남고, 그 디렉터리는 Git 에서 무시된다.

---

## 8. 명령 계약 (호출자 관점)

### 8.1 공통 인자

```
--worktree <dir>          기본: PWD
--scope working-tree|branch   기본: working-tree
--base <ref>              scope=branch 일 때 필수
--task-id <id>            기본: §4.2 결정적 fallback
--author claude|codex     필수
```

`--scope` 는 기본값에 의존하지 말고 매번 정한다. `working-tree` 는 커밋된 변경을 보지 못하고,
`branch --base <ref>` 는 미커밋을 보지 못한다.

### 8.2 종료 코드

| code | 의미 |
|---|---|
| `0` | `PASS` 또는 `P2P3_CLOSED` — 진행 가능 |
| `10` | `CHANGES_REQUESTED` — P0/P1 수정 후 1회 재리뷰 |
| `20` | `BLOCKED_*` — 중단, 사람 판단 필요 |
| `2` | usage error (인자 오류, author==reviewer 등) |

stdout 에는 사람이 읽는 요약 + 결과 JSON 경로를 낸다. `review-stop-guard.sh` 만 예외적으로
**항상 `exit 0`**.

### 8.3 환경변수

| 이름 | 기본 | 용도 |
|---|---|---|
| `CROSS_REVIEW_ROLE` | (미설정) | `reviewer` 면 게이트·훅 no-op |
| `CROSS_REVIEW_TIMEOUT` | `900` | reviewer 실행 상한(초) |
| `CROSS_REVIEW_ALLOW_OVERSIZE` | (미설정) | `1` 이면 oversize 명시 승인 |
| `CROSS_REVIEW_CLAUDE_BIN` | `claude` | 어댑터 바이너리 (fixture 주입용) |
| `CROSS_REVIEW_CODEX_BIN` | `codex` | 어댑터 바이너리 (fixture 주입용) |
| `CROSS_REVIEW_MAX_FILES` | `30` | oversize 파일 수 상한 |
| `CROSS_REVIEW_MAX_BYTES` | `51200` | oversize 바이트 상한 |

---

## 9. 설치 계약

- `project/hooks/*.sh` 는 기존 `install_project_hooks()` 가 **파일만** 설치한다 (배선과 무관).
  새 스크립트 6종도 같은 경로를 그대로 탄다 — 설치기 변경 없음.
- `project/settings-fragments/cross-review-gate.json` 은 **`--with-cross-review` 명시 시에만**
  조각 파일 설치 + `settings.json` 병합.
- `--full` / 기본 설치는 **절대** 이 게이트를 배선하지 않는다.
  `tests/test-install.sh` 의 A9 (`--full` 에 `hooks.Stop` 부재) 가 이 불변식의 감시자다.
- `--with-verify-hooks` 와 `--with-cross-review` 를 함께 주면 `hooks.Stop` 에 두 엔트리가
  공존해야 한다 (조각 병합의 배열 누적 계약).
- 실제 `$HOME` 은 건드리지 않는다. 검증은 temp HOME fixture + `--dry-run` 으로만.

---

## 10. 테스트 매트릭스

| ID | 시나리오 | 통과 기준 |
|---|---|---|
| X1 | Codex reviewer argv | `--sandbox read-only` + `--output-schema` + `--cd <worktree>` 가 실제 argv 에 존재 |
| X2 | Claude reviewer argv | `--restricted`, `--tools Read,Grep,Glob`, `--permission-mode manual`, `--permission-prompts none` 존재. write 계열 도구 부재 |
| X3 | 정상 PASS | phase=`PASS`, exit 0, attempt=1 |
| X4 | P0/P1 → 재리뷰 1회 | 1차 exit 10 / phase=`CHANGES_REQUESTED`, 수정 후 2차 PASS, attempt=2 |
| X5 | attempt cap | 같은 task 에서 3번째 리뷰 호출 → `BLOCKED_ATTEMPTS`, 모델 호출 0회 |
| X6 | duplicate `(sha, reviewer)` | 수정 없이 재호출 → `BLOCKED_DUPLICATE`, 모델 호출 0회 |
| X7 | stale SHA | 결과 JSON 의 sha 가 동결 sha 와 다름 → `BLOCKED_STALE`, PASS 아님 |
| X8 | 결과 파일 없음 | `BLOCKED_ERROR` (fail closed) |
| X9 | malformed JSON | `BLOCKED_ERROR` |
| X10 | 산문 PASS | `"Looks good, no issues"` 만 반환 → `BLOCKED_ERROR` (PASS 추론 금지) |
| X11 | verdict/findings 모순 | `verdict=PASS` + P0 finding → `BLOCKED_ERROR` |
| X12 | P2/P3 only | `P2P3_CLOSED`, exit 0, 재리뷰 호출 0회 |
| X13 | oversize files | 31 파일 → `BLOCKED_OVERSIZE`, 모델 호출 0회 |
| X14 | oversize bytes | >50KiB → `BLOCKED_OVERSIZE` |
| X15 | oversize 승인 | `CROSS_REVIEW_ALLOW_OVERSIZE=1` → 통과 |
| X16 | timeout | reviewer 가 상한 초과 → `BLOCKED_ERROR`, PASS 아님 |
| X17 | reviewer mutation | fake reviewer 가 파일 수정 → `BLOCKED_MUTATION` |
| X18 | stop hook 재진입 | `stop_hook_active=true` → reviewer 호출 0회, exit 0 |
| X19 | reviewer role no-op | `CROSS_REVIEW_ROLE=reviewer` → 훅 no-op |
| X20 | stop guard 기록 | 미검토 diff 로 종료 → `BLOCKED_UNREVIEWED` 기록 + exit 0 (차단 아님) |
| X21 | stop guard 통과 | `reviewed_sha == 현재 sha` → 기록 없음, exit 0 |
| X22 | 자기검토 금지 | `--author claude` 로 Claude reviewer 호출 → exit 2 |
| X23 | state gitignore | 리뷰 1 사이클 후 `git status --porcelain` 비어 있음 |
| X24 | 시크릿 미영속 | reviewer stdout 의 토큰 문자열이 `state.tsv` 에 없음 |
| X25 | 기본 설치 미배선 | `--dry-run --full` 후 settings 에 `review-stop-guard` 부재 |
| X26 | opt-in 배선 | `--with-cross-review` 시 `hooks.Stop` 에 배선됨 |
| X27 | Stop 조각 공존 | `--with-verify-hooks --with-cross-review` → Stop 엔트리 2종 공존 |
| X28 | `bash -n` | 신규 shell 6종 문법 통과 |

기존 스위트(`tests/test-*.sh`) 전체도 회귀 없이 통과해야 한다.

---

## 11. Rollout HOLD

이 계획은 **구현까지만** 진행하고 다음은 사람 승인 전까지 하지 않는다.

1. **전역 활성화 금지** — `~/.claude/settings.json` 에 `--with-cross-review` 를 적용하지 않는다.
2. **live provider smoke = `PENDING`** — 실제 `codex exec` / `claude -p` 호출로 end-to-end 를
   돌리지 않았다. 어댑터의 플래그는 설치된 CLI 의 `--help`(1차 출처)로 확인했고, 계약은 fake
   fixture 로 검증했다. 실제 런타임 동작(특히 `--restricted` + `--permission-prompts none` 조합의
   무인 종료, `--output-schema` 준수율)은 미검증이다.
3. **enable/config mutation, 외부 메시지, commit/push/merge 는 STOP/HITL.**
4. 파일럿은 10~20 task 규모로 호출 수·소요·모델 사용량을 실측한 뒤에만 확대한다.
