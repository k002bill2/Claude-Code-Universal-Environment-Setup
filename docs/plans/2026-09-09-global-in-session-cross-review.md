# 글로벌 In-Session Claude ↔ Codex 교차리뷰 — 배포형 구현 계획

- 작성일: 2026-09-09 (KST)
- 상태: **구현 완료 / 전역 활성화 완료 / 양 provider live smoke 통과 (2026-09-11)**
- 대체 대상: `docs/plans/2026-09-09-in-session-cross-review.md` (프로젝트-로컬 배치본)
- 상위 결정: `~/.hermes/profiles/jarvis/cron/output/2026-09-09-buzz-cross-review-final-discussion.md`

> **이 문서가 정본이다.** 이전 계획과 아키텍처(§3~§8)는 동일하고, **배치 모델만** 바뀐다:
> 프로젝트-로컬 `.claude/` 설치 → **글로벌 opt-in 배포 프로필**.

---

## 1. 이전 계획에서 바뀐 것 — 배치 모델

| 항목 | 이전(로컬) | 현재(글로벌 opt-in) |
|---|---|---|
| 스크립트 소스 | `project/hooks/*.sh` | `global/cross-review/*.sh` |
| 스크립트 설치 위치 | `<project>/.claude/hooks/` | `~/.claude/hooks/cross-review/` |
| settings 조각 소스 | `project/settings-fragments/cross-review-gate.json` | `global/settings-fragments/cross-review.json` |
| settings 배선 대상 | `<project>/.claude/settings.json` | `~/.claude/settings.json` |
| 리뷰 상태 | `<worktree>/.claude/cross-review/` (self-ignore) | `~/.claude/state/cross-review/<sha256(realpath)>/` |
| 설치 트리거 | `--with-cross-review` (프로젝트) | `--with-cross-review` (글로벌, 기본·`--full` 모두 미배선) |

### 왜 옮겼나

1. **대상 저장소 무오염.** 상태를 저장소 안에 두면 (a) 리뷰 행위 자체가 diff 를 바꾸고,
   (b) §6.2 tree 지문이 자기 상태 파일을 reviewer mutation 으로 오탐하며,
   (c) 남의 프로젝트 `.gitignore` 를 편집해야 한다. 이전 계획은 이를 "상태 디렉터리가
   자기 자신을 무시한다(`.gitignore` 내용 `*`)"로 우회했지만, 그것은 **저장소에 파일을
   쓰지 않는다**는 요구를 만족시키지 못한다 — 무시될 뿐 존재한다.
2. **한 번 설치, 모든 저장소.** 게이트는 저장소 속성이 아니라 **작업 습관**이다.
   프로젝트마다 재설치하면 설치되지 않은 저장소가 조용한 사각지대가 된다.
3. **Stop 훅 배선의 단일 지점.** 글로벌 `settings.json` 한 곳만 관리하면 opt-in/uninstall
   경계가 명확하다.

---

## 2. 비목표 (이번에 하지 않는다)

- **실제 `$HOME` 에 대한 설치 실행 — 하지 않는다.** 검증은 temp HOME fixture 로만.
- **전역 활성화 — 하지 않는다.** `~/.claude/settings.json` 에 배선하지 않는다.
- **live provider smoke — PENDING.** 실제 `codex exec` / `claude -p` 미호출 (§9).
- relay lock / `REVIEW_CLAIM` / Buzz 연동 / 스케줄러 — 구현하지 않는다.
- 저장소-로컬 `.claude/review-runs` 등 대상 저장소 내 상태·로그 — 두지 않는다.
- Stop 훅이 리뷰를 **실행**하는 것 — 하지 않는다. 훅은 guard-only (§3).
- reviewer 의 소스 자동 수정(remediation) — 금지.
- 자동 재시도 / fail-open — 없음. 모든 실패는 fail-closed 상태값.
- commit / push / PR / merge / deploy / 외부 메시지.
- 미확인 Claude CLI 권한 플래그 발명 — 설치된 CLI 의 `--help` 로 실측한 것만 쓴다.

---

## 3. 아키텍처 (이전 계획과 동일 — 변경 없음)

primary 는 **author 세션 내부의 동기 교차리뷰**다. author 가 완료 후보를 선언하면
반대편 provider 를 read-only 로 직접 부르고, 그 결과가 같은 세션 컨텍스트로 돌아온다.

```text
author(Claude|Codex) 완료 후보 선언
  → 수정 중지 + diff 동결(sha256)
  → oversize / duplicate / attempt 게이트  (모델 호출 0회로 차단)
  → 반대 provider reviewer 를 read-only 동기 실행
  → reviewer 전/후 tree 지문 비교 (write 탐지)
  → 결과 JSON 엄격 파싱 (schema + SHA 바인딩)
  → P0/P1 있으면: author 수정 → 같은 reviewer 1회 재리뷰
     P2/P3 뿐이면: 재리뷰 없이 종료(P2P3_CLOSED)
  → 그 외 모든 이상: BLOCKED_* (HITL)
```

### Stop 훅은 guard-only

`review-stop-guard.sh` 는 위 흐름에 **참여하지 않는다**. 리뷰를 실행하지 않고,
`stop_hook_active` / `CROSS_REVIEW_ROLE` 를 먼저 확인해 no-op 조건을 거른 뒤,
`현재 diff sha == reviewed_sha` 인지만 보고 불일치면 `BLOCKED_UNREVIEWED` 를 상태에
기록하고 advisory 를 출력한 뒤 **항상 `exit 0`** 한다.

> **`decision: block` 을 쓰지 않는 이유:** Stop 훅이 세션을 되살리면 그 자체가 재진입
> 경로(P0)다. fail-closed 는 exit code 가 아니라 **상태값**으로 산다.

### 역할·provider 매핑 (고정)

| author | reviewer | 진입점 |
|---|---|---|
| `claude` | `codex` | `run-codex-review.sh` |
| `codex` | `claude` | `claude-review-current-diff.sh` → `run-claude-review.sh` |

author == reviewer 는 usage error(exit 2). 자기검토 불가.

---

## 4. 상태 모델 (배치 변경)

### 4.1 저장 위치 — 글로벌, worktree realpath 로 샤딩

```
~/.claude/state/cross-review/            (mode 700)
  <sha256(realpath(worktree))>/          (mode 700)
    worktree.path                        # 역참조용 (사람이 읽는 용도)
    tasks/<task_id>/
      state.tsv                          # key<TAB>value
      frozen/<sha>.diff                  # 동결된 diff 원본
      results/<sha>.<reviewer>.json      # reviewer 원문 결과 (엄격 검증 후 보관)
      claims/<sha>.<reviewer>            # 중복 호출 마커 (내용 없음)
```

**보존 정책 (전문 미영속).** `frozen/<sha>.diff` 와 `prompt.txt` 는 리뷰 대상 **소스 전문**을
담는다. 실행이 끝나면 성공·차단 어느 경로로 끝났든 **항상 삭제**한다 — `rs_review_main` 이
얇은 래퍼가 되어 `rs_review_run` 의 모든 return 을 감싸고 한 곳에서 purge 한다. oversize 차단은
동결 **뒤** 일어나므로, 이 단일 purge 지점이 없으면 가장 큰 diff 가 남는 경로가 생긴다.

provider stdout 원문 봉투(`results/*.envelope`)도 마찬가지다 — 어댑터가 **모든 결말에서**
지우고(정상·비정상 종료 모두), 타임아웃으로 어댑터가 강제 종료된 경우를 위해 purge 가 한 번 더
훑는다(이중 안전망). 삭제는 전부 `rs_path_safe`(관리 루트 접두 + 경로 성분 전체가 링크 아님)를
통과한 **일반 파일**에만, 항목 수 상한 아래에서 이뤄진다 — 글로브 `rm` 은 `frozen/` 이 바깥을
가리키는 링크일 때 관리 루트 밖을 지운다.

**쓰기 경로가 먼저다(삭제 하드닝만으로는 부족).** task 하위에 미리 심어둔 링크가 있으면
`mv`·`>` 가 그대로 링크를 따라가 **동결 diff·프롬프트(소스 전문)를 관리 루트 밖으로 흘리고**
바깥 피해자 파일을 덮어쓴다. 그래서 freeze/prompt/result 쓰기 **이전에**:

- `rs_ensure_safe_dir` — `frozen/`·`results/`·`claims/`·task 디렉터리를 신뢰 가능한 실디렉터리로
  확보한다. 링크가 자리를 막고 있으면 **링크만 끊고**(대상 파일은 건드리지 않는다) 다시 만든다.
- `rs_safe_out_path` — 출력 **파일** 경로(`prompt.txt`·`schema.json`·`results/*.json`·
  `frozen/*.diff`·`claims/*`·`state.tsv`)가 링크이거나 루트 밖이면 **거부**하고
  `BLOCKED_ERROR(unsafe_write_path)` 로 끝낸다. 자동 복구하지 않는다.

디렉터리는 복구, 파일은 거부 — 비대칭인 이유는 디렉터리 링크를 끊는 것은 무해하지만,
출력 파일 링크를 조용히 끊으면 "덮어쓸 뻔한 대상"이 무엇이었는지 사라지기 때문이다.

`results/*.json` 은 감사 기록으로 남기되 `CROSS_REVIEW_MAX_RESULT_BYTES`(기본 256KiB) 를 넘으면
**저장하지 않고** `BLOCKED_ERROR(result_oversize)` 로 차단한다. task 디렉터리는
`CROSS_REVIEW_KEEP_TASKS`(기본 20) 개까지만 유지한다. 삭제 전 경로가
`<home>/state/cross-review/` 아래인지 반드시 검사한다 (설치기의 `managed_path_safe` 와 같은 취지).

> 알려진 한계: 삭제된 worktree 의 shard 디렉터리는 남는다. purge 후 잔량이 작아 배경 GC 를
> 두지 않는다 — 파괴적 백그라운드 스윕을 새로 만드는 위험이 이득보다 크다.

루트 결정 우선순위: `CROSS_REVIEW_HOME` > `CLAUDE_CONFIG_DIR` > `~/.claude`.
`CROSS_REVIEW_HOME` 은 테스트 fixture 주입 경로다 — 이것이 있어야 실제 `$HOME` 을
건드리지 않고 검증할 수 있다.

**대상 저장소에는 어떤 파일도 쓰지 않는다.** 리뷰 1 사이클 후 대상 저장소의
`git status --porcelain` 이 비어 있고, `<repo>/.claude/cross-review` 도 생기지 않는다.

### 4.2 `task_id`

`--task-id` 로 명시하거나, 미지정 시 결정적 fallback:

```
task_id = sha256( realpath(worktree) + "\n" + scope + "\n" + base_ref )[0:16]
```

`task_id` 는 **SHA 가 바뀌어도 불변**이어야 한다 — attempt cap 이 여기 걸린다 (§5.1).

### 4.3 `state.tsv` 키

| key | 값 |
|---|---|
| `schema_version` | `1` |
| `task_id` | §4.2 |
| `worktree` | 절대 realpath |
| `scope` | `working-tree` \| `branch` |
| `base_ref` | branch scope 의 base, 아니면 `-` |
| `phase` | §4.4 enum |
| `diff_sha256` | 마지막으로 **동결**된 diff 의 sha256 |
| `reviewed_sha` | 마지막으로 **유효 검증을 통과**한 diff 의 sha256 (없으면 `-`) |
| `reviewer` | `codex` \| `claude` \| `-` |
| `attempt` | 이 task 에서 소비한 모델 리뷰 호출 수 (정수) |
| `reason` | 짧은 슬러그. **자유 산문 금지** (§7.2) |
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
| `BLOCKED_DUPLICATE` | 동일 `(sha, reviewer)` 재호출 | HITL |
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

정상 P0/P1 수정 후 재리뷰는 **새 SHA** 라 중복 규칙에 걸리지 않는다. 반대로 시도 상한을
`(sha, reviewer)` 에 걸면 수정할 때마다 새 SHA 가 생겨 상한이 영영 발화하지 않는다.

### 5.2 P2/P3 종결

P0/P1 이 0건이고 P2/P3 만 있으면 `P2P3_CLOSED` 로 종결, **재리뷰하지 않는다**.
남은 지적은 호출자가 보고서/PR 본문에 남긴다.

### 5.3 Oversize (fail-closed)

```
files > 30  OR  bytes > 51200  →  BLOCKED_OVERSIZE (모델 호출 0회)
```

`CROSS_REVIEW_ALLOW_OVERSIZE=1` 로 사람이 명시 승인해야만 통과. 자동 승격 없음.

### 5.4 훅 no-op 조건

- stdin JSON 의 `stop_hook_active == true`
- `CROSS_REVIEW_ROLE == reviewer` (reviewer 자식 프로세스의 재진입 차단)
- git 저장소 아님 / 변경 없음

---

## 6. reviewer 격리

### 6.1 명령 계약

> 아래 플래그는 **이전 세션**에서 설치된 CLI 의 `--help`(1차 출처)로 실측해 확정한 것을
> 그대로 승계한다. 이번 세션에서 CLI 를 다시 호출해 재확인하지 않았고, 알 수 없는
> 권한 플래그를 새로 발명하지 않았다. 런타임 동작은 §9 에서 PENDING 이다.

**Codex reviewer** — 스키마 강제를 CLI 가 한다:

```
codex exec --cd <worktree> --sandbox read-only \
  --ignore-user-config --ignore-rules --ephemeral \
  --output-schema <schema.json> --output-last-message <raw.json> --color never -
```

`--ignore-user-config` 는 `~/.codex/config.toml` 을 읽지 않으므로 **MCP 서버가 하나도 로드되지
않는다** (사용자 설정에 MCP 서버가 10개 넘게 있어도 reviewer 는 전부 없이 돈다).
`--ignore-rules` 는 저장소·사용자 execpolicy `.rules` 를, `--ephemeral` 은 세션 파일 영속을
막는다. 세 플래그 모두 `codex exec --help`(codex-cli 0.153.4)로 실측 확인했다.

> **부작용:** `--ignore-user-config` 는 model/profile 설정도 함께 뺀다 — reviewer 는 CLI 기본
> 모델로 돈다. 리뷰 품질·비용에 영향이 있으므로 사용자가 알아야 한다. auth 는 `CODEX_HOME` 을
> 계속 쓴다(help 문구 명시).
>
> **MCP 격리는 양쪽 대칭이다(수단만 다름):** Codex 는 `--ignore-user-config` 로 config.toml
> 자체를 읽지 않아 거기 정의된 MCP 서버가 전부 빠지고, Claude 는 `--strict-mcp-config` 로
> "`--mcp-config` 로 준 것만" 쓰는데 아무것도 주지 않으므로 0개다
> (`claude --help`: "Only use MCP servers from --mcp-config, ignoring all other MCP configurations").
>
> **비대칭(의도):** 이 격리는 **reviewer 호출에만** 적용한다. author 래퍼
> `codex-with-review.sh` 는 사용자의 평소 설정으로 돌아야 하므로 붙이지 않는다.
>
> **네트워크는 주장하지 않는다.** `--sandbox read-only` 가 제약하는 것은 *모델이 실행하는 셸*
> 이다. 그 이상의 네트워크 경계는 `--help` 로 뒷받침할 수 없으므로 §12 의 한계로 남긴다.

**Claude reviewer** — `--restricted` + 도구 화이트리스트로 write 수단을 제거한다:

```
claude -p --restricted --tools "Read,Grep,Glob" --strict-mcp-config \
  --permission-mode manual --permission-prompts none \
  --no-session-persistence --output-format json --add-dir <worktree>
```

> **비대칭인 이유:** `--tools` 는 *도구 이름* 단위이지 경로 단위가 아니다. Claude reviewer 에게
> `Write` 를 주면 결과 파일만이 아니라 worktree 어디에나 쓸 수 있다. 그래서 Claude 쪽은
> **모델이 파일을 쓰지 않고**, `--output-format json` 의 `.result` 문자열을 래퍼가 받아
> 엄격 파싱하고 래퍼가 결과 파일을 쓴다. Codex 쪽은 `--output-schema`/`--output-last-message`
> 를 **CLI 가** 쓰므로 모델 write 권한이 필요 없다.

### 6.2 tree 지문 (write 탐지)

reviewer 실행 **직전/직후** 에 같은 함수로 지문을 만들어 비교한다. 불일치 → `BLOCKED_MUTATION`.

```
sha256( git rev-parse HEAD + git status --porcelain + git diff
        + git diff --cached + 각 untracked 파일의 sha256 )
```

`git diff` 하나만으로는 staged 변경·신규 untracked 파일을 놓친다. 추가로 reviewer 전후
`git diff --check` 로 whitespace 오류 유입을 잡는다. 상태가 **저장소 밖**(§4.1)에 있으므로
지문이 자기 상태 파일을 mutation 으로 오탐하지 않는다.

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

### 7.1 엄격 검증 — 하나라도 어기면 `BLOCKED_*`

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

**산문에서 PASS 를 추론하지 않는다.** "looks good", "no issues found" 는 결과가 아니다.
결과 파일 부재 = `BLOCKED_ERROR` (PASS 아님).

### 7.2 영속 상태에 남기지 않는 것

`state.tsv` 에 시크릿·전체 프롬프트·raw 소스·provider stdout 원문을 **쓰지 않는다**.
`reason` 은 짧은 슬러그(`schema_invalid`, `sha_mismatch`, `timeout`, `oversize` …)만.
reviewer 원문은 **영속하지 않는다** — 실행 중 run 디렉터리 안에만 있고 끝나면 사라진다(§7.3.1).

### 7.3 실행 아티팩트 생애주기 (안전 생애주기)

이 절이 §10 의 X38·X41·X43·X44 가 검증하는 계약이다. 목표는 두 가지다:
**(a) 지속되어선 안 되는 것이 어떤 결말에도 디스크에 남지 않는다**,
**(b) 지워야 하는 것을 지우는 행위가 관리 루트 밖을 해치지 않는다.**

#### 7.3.1 아티팩트 목록과 수명

`<task>` = `<home>/state/cross-review/<sha256(worktree)>/tasks/<task_id>`
`<run>`  = `<task>/run.<32-hex>` — 리뷰 1회당 하나. **이름은 난수**이고 `mkdirat` 로
만든다(기존 항목·링크가 있으면 EEXIST 로 실패한다 → 사전 심기 불가).

| 아티팩트 | 경로 | 내용 | 수명 |
|---|---|---|---|
| 상태 | `<task>/state.tsv` | 슬러그·sha 만 (§7.2) | 영속 |
| 클레임 | `<task>/claims/<sha>.<reviewer>` | 빈 파일 (O_EXCL 로 획득) | 영속 |
| 동결 diff | `<run>/pending.diff` | **소스 전문** | run 디렉터리와 함께 소멸 |
| 결과 JSON | — | — | **파일이 된 적이 없다** (stdout 파이프 → 셸 변수) |
| 프롬프트 | — | — | **파일이 된 적이 없다** (stdin 파이프) |
| 출력 스키마 | — | — | **파일이 된 적이 없다** (`/dev/fd`) |
| provider 원문 | — | — | **파일이 된 적이 없다** (파이프) |

**결과 JSON 은 디스크에 존재하지 않는다.** 예전에는 `<task>/results/<sha>.<reviewer>.json` 에
남겼는데 두 가지가 문제였다: (a) provider 산문(그리고 그것이 diff 에서 복사해 온 소스·
시크릿)이 홈 디렉터리에 쌓인다, (b) 경로가 `(sha, reviewer)` 로 **예측 가능**해서 같은
내용의 저장소로 sha 를 알아내면 링크를 **사전에 심을** 수 있었고, SIGKILL 로 정리에
도달하지 못하면 그 자리에 원문이 남았다. run 디렉터리 안으로 옮겨도 **부족했다**: 쓰기와 purge 사이에 SIGKILL 이
나면 회수가 "같은 task 의 다음 실행" 에 의존하므로, 그 task 가 다시 돌지 않으면 산문이
**영영** 남는다. 그래서 지금은 아예 파일로 만들지 않는다 — provider 출력은 stdout
파이프로 와서 호출자의 셸 변수에만 머물고, 분류·출력 후 프로세스와 함께 사라진다.
캡처는 `head -c` 로 유계라 무한 출력이 메모리를 채우지도 못한다. 지적사항은 stdout 으로
저자에게 전달되고, 상태에는 슬러그와 sha 만 남는다.

#### 7.3.2 provider 는 관리 루트 안의 **어떤 경로도 이름으로 열지 않는다**

이것이 이 절의 불변식이다. provider 에게 관리 루트 안의 경로를 하나라도 넘기면,
그 경로는 **provider 가 직접 해석**하므로 우리 쪽 pinned-fd 설계가 통째로 우회된다:
실행 중에 run 디렉터리를 링크로 바꿔치기하면 쓰기가 관리 루트 밖으로 나가고, 읽기는
공격자 내용으로 바뀌고, 출력 스키마는 "아무거나 통과" 로 교체된다.

| 무엇 | 예전 (경로) | 지금 |
|---|---|---|
| 프롬프트 | `<run>/prompt.txt` 경로 | **stdin 파이프** |
| 출력 스키마 | `<run>/schema.json` 경로 | Codex: `/dev/fd/5` · Claude: 프롬프트 본문에 포함 |
| provider 원문 | Claude `<out>.envelope` 파일 / Codex `<run>/last.json` 경로 | 양쪽 다 **파이프** (Codex 는 `--output-last-message /dev/fd/4`) |
| 결과 JSON | provider 가 경로로 생성 | **우리가** safe-fs 로 생성 |

`/dev/fd/N` 은 우리 파이프에 붙은 서술자이고 `/dev` 는 사용자가 바꿔칠 수 없으므로
조상 스왑으로 재지향되지 않는다. provider 원문은 이름이 붙은 적이 없어 어떤 신호로
죽어도 디스크에 남을 수 없다 — 나중에 지우는 안전망은 SIGKILL 창을 원리적으로 닫지
못하므로, 애초에 파일로 받지 않는 것이 유일한 해법이다.

**스트리밍 중 상한.** 결과 크기 제한은 `safe-fs write <max>` 가 **쓰는 도중** 끊고
부분 파일을 지운다. 프로세스가 끝난 뒤 크기를 재는 방식은 이미 초과 바이트가 디스크에
다 올라간 뒤라 상한이 아니었다. 초과는 `BLOCKED_ERROR(result_oversize)` 로 구분된다.

**async stdin 함정.** job control 이 꺼진 셸에서 `cmd &` 는 자식 stdin 을 `/dev/null`
로 바꾼다. 프롬프트를 stdin 으로 넘기는 구조에서 `rs_run_with_timeout` 의 `"$@" <&0 &`
에서 `<&0` 을 빼면 provider 가 **빈 프롬프트**를 받고도 조용히 돈다(실측). X45 가 감시자다.

#### 7.3.3 관리 루트 안의 모든 쓰기·삭제는 **pinned FD** 로 한다

`rs_path_safe` 같은 경로명 검사는 TOCTOU 를 닫지 못한다. 검사와 실제 연산 사이에
조상 디렉터리가 링크로 바뀌면 연산이 링크 너머로 간다. bash 에는
`openat`/`unlinkat`/`O_NOFOLLOW` 가 없으므로 **순수 bash 로는 이 창을 닫을 수 없다.**

이것은 이론적 위험이 아니다. 경합 테스트(X43)에서 실측으로 두 가지가 확인됐다:

- **쓰기**: `mv tmp <task>/state.tsv` 가 관리 루트 **밖** 피해자 디렉터리에
  `state.tsv` 를 실제로 만들었다.
- **삭제**: 조상이 링크로 바뀐 뒤의 `rm -rf <task>/run.<hex>` 는 링크 너머 항목을 지운다.

그래서 관리 루트 하위의 **모든 생성·쓰기·교체·삭제**를 `global/cross-review/safe-fs.py`
에 위임한다. 이 헬퍼는 루트에서 시작해 경로 성분마다 `O_NOFOLLOW|O_DIRECTORY` 로 열어
내려가고, 마지막 연산을 그렇게 고정된 **부모 디렉터리 fd 기준**으로 수행한다
(`mkdirat`/`openat(O_CREAT|O_EXCL|O_NOFOLLOW)`/`renameat`/`unlinkat`).

> **핵심: 검사와 사용이 같은 syscall 이라 "검사 후 스왑" 창이 존재하지 않는다.**
> 스왑이 walk 보다 먼저면 그 성분을 여는 순간 실패하고, walk 보다 나중이면 이미 실제
> inode 에 fd 가 걸려 있어 영향이 없다. 어느 쪽도 링크 너머로 재지향되지 않는다.

**root 는 신뢰 접두부다.** 헬퍼에 넘기는 root 는 `<home>`(`~/.claude` 등)이고, 관리
경계인 `state`·`cross-review`·샤드·task·run 은 **전부 O_NOFOLLOW 검사 대상**이다.
예전에는 root 를 `<home>/state/cross-review` 로 잡아서 `state`·`cross-review` 자체가
링크여도 그냥 따라갔다 — 관리 경계 안인데 검사에서 빠져 있었다. 모드도 경로 `chmod` 가
아니라 pinned fd 의 `fchmod` 로 준다(경로 chmod 는 링크를 따라가 남의 디렉터리 모드를 바꾼다).

**의존성과 fail-closed.** 이 헬퍼는 `python3` 를 쓴다(`CROSS_REVIEW_PYTHON` 으로 재정의
가능 — **실행 가능한지 확인**한 뒤 쓴다. 값만 보고 믿으면 잘못된 경로에서 "가능" 이라
답하고 모든 연산만 조용히 실패해 사유 없는 exit 20 이 된다). `python3` 나 헬퍼가 없으면
게이트는 **안전하지 않은 bash 경로로 되돌아가지 않고 사유를 밝히며 `BLOCKED_ERROR` 로
끝난다.** Stop 가드는 항상 `exit 0` 이지만, 상태를 기록하지 못하면 **advisory 를 반드시
출력하고 기록 불가를 명시한다** — 예전에는 `|| exit 0` 이 advisory 앞에 있어 python3 가
없으면 훅이 완전히 침묵했다(fail-open). 설치기는 `global/cross-review/*.sh` 와 함께
`*.py` 를 배포한다 — `.sh` 만 배포하면 설치된 게이트가 모든 리뷰를 BLOCKED 로 끝낸다.

**링크는 거부이지 복구가 아니다.** 출력 자리에 링크가 놓여 있으면 따라가지도, 지우지도
않고 `BLOCKED_ERROR` 로 멈춘다(`exit 20`, provider 미호출). 예전에는 링크 디렉터리를
`rm -f` 로 끊고 실디렉터리로 "복구" 했는데, 그 복구 자체가 경로명 검사에 기반한 파괴적
동작이라 조상이 바뀌면 엉뚱한 링크를 지운다.

#### 7.3.4 대상 저장소가 리뷰어 쪽에서 명령을 실행시킬 수 없다

리뷰 대상 저장소는 공격자 통제 입력이다. `.git/config` 와 `.gitattributes` 로 diff
파이프라인에 **임의 명령 실행**을 심을 수 있다: `diff.external`, `[diff "x"] command`,
`.gitattributes` 의 `diff=x` + `textconv`, `core.fsmonitor`. 그래서 모든 diff·status
호출을 `rs_git` / `rs_git_diff` 로 통과시켜 이것들을 명시적으로 무력화한다
(`-c diff.external=`, `-c core.fsmonitor=false`, `-c core.hooksPath=/dev/null`,
`-c core.attributesFile=/dev/null`, `--no-ext-diff`, `--no-textconv`).
저장소 내 `.gitattributes` 는 `attributesFile` 로 끌 수 없으므로 **실행 자체**를 끈다.

#### 7.3.5 수집·기록 오류를 삼키지 않는다

- **diff 수집**: 예전에는 모든 git 실패를 `|| :` 로 흡수해서, 존재하지 않는 `--base` 나
  깨진 저장소가 **빈 diff 로 조용히 PASS** 됐다(빈 diff 는 지적할 것이 없으니 PASS 다).
  지금은 base 를 먼저 `rev-parse --verify` 로 확인하고, `git diff` 의 rc 는 0/1 만
  정상으로 보고 그 밖은 실패로 올린다.
- **특이한 파일명**: untracked 열거를 `-z`(NUL 구분) + `sort -z` 로 한다. 줄 단위로 읽으면
  개행이 든 파일명을 git 이 인용해 내보내 항목을 빠뜨리거나 쪼갠다. tree 지문도 같다.
  열거 성공을 sentinel 로 확인해, 중간에 깨진 열거를 "변경 없음" 으로 오인하지 않는다.
- **클레임·상태 기록**: 중복 판정과 클레임 획득을 `O_EXCL` 생성 **하나로** 한다 — 예전에는
  `[ -f ]` 검사와 생성이 떨어져 있어 동시에 뜬 두 호출이 둘 다 통과할 수 있었다.
  `state.tsv` 기록 실패와 attempt 전이 실패는 **provider 호출을 막는다**(예전엔 무시).
  진행 중인 task 는 prune 대상에서 제외한다.

#### 7.3.6 task 범위 직렬화 — OS 권고 잠금(flock)

`attempt` 는 read → (게이트·클레임) → write 로 갈라져 있다. 클레임은 `(sha, reviewer)`
키라 **reviewer 가 다른** 두 호출은 서로 다른 클레임을 얻어 둘 다 통과하고 각자 `1` 을
쓴다 — 증가분이 유실되고 상한이 우회된다(사보타주로 재현: **provider 2회 / attempt=1**).

**직접 만든 잠금은 버렸다.** 디렉터리 뮤텍스 + 나이 기반 stale 회수로 시작했지만, 그것은
원자적 compare-and-swap 이 아니라 이중 소유자를 만든다. `rename` 으로 인수를 원자화해도
같았다 — 경합을 주입해 실측한 결과, 뒤늦은 경쟁자가 **새 소유자가 방금 만든 잠금을 그대로
옮겨가** 승자가 2명이 됐다. 검증한 대상과 인수하는 대상이 다를 수 있다는 것이 본질이고,
사용자 공간에서 CAS 없이 닫히지 않는다.

그래서 `flock(LOCK_EX|LOCK_NB)` 을 쓴다. 커널이 소유권을 관리하고 프로세스가 죽으면
**자동 해제**되므로 나이 판정·인수·이중 소유자 문제가 통째로 사라진다.

**잠금은 리뷰 프로세스가 직접 든다 (상주 헬퍼 없음).** 처음에는 `safe-fs.py lockhold`
상주 헬퍼가 잠금을 쥐고 리뷰 셸은 그 stdout 파이프만 들었다. 그 구조에서는 헬퍼가 리뷰보다
**먼저 죽는 순간** 커널이 잠금을 놓는데 리뷰는 그것을 모른 채 상태를 계속 고친다 — 그 사이
다른 실행이 같은 task 의 claims·pending·attempt 를 동시에 바꿀 수 있다. 헬퍼 PID 를
폴링해도 그 창은 닫히지 않고, PID 재사용이라는 새 구멍이 생긴다.

flock 은 **열린 파일 기술(OFD)** 에 걸린다. 그래서 리뷰 셸이 `exec 9>>`(take 는 fd 8)로
잠금 파일을 열고, `safe-fs.py flockfd <root> <rel> 9` 가 **그 fd 를 물려받아** 잠근다.
`flockfd` 가 끝나도 셸이 fd 를 들고 있는 한 잠금은 유지되고, 놓는 방법은 fd 를 닫는 것뿐이며,
셸이 어떤 신호로 죽어도 커널이 해제한다 — **잠금의 수명 = 리뷰 프로세스의 수명**이고 감시할
보조 프로세스도 죽일 PID 도 없다 (실측: macOS/bash 3.2, X58).

**`exec` 리다이렉션은 셸 전체에 영구 적용된다.** `exec 9>>f 2>/dev/null` 로 쓰면 fd 9 와 함께
**stderr 도 영구히** /dev/null 로 간다 — 잠금 획득 이후의 모든 진단이 조용히 사라진다(실측으로
잡았다: 정리 실패 메시지가 사라지고 종료코드만 20 이었다). 중괄호 그룹 `{ exec 9>>f; } 2>/dev/null`
으로 범위를 가둔다. X64 가 이 회귀의 감시자다.

셸 리다이렉션은 링크를 따라가므로 두 단계로 막는다: (1) `safe-fs.py touch` 가 O_NOFOLLOW 로
잠금 파일을 먼저 안전하게 만들고, (2) `flockfd` 가 안전 walk 로 연 파일과 호출자 fd 의
`(dev, ino)` 를 대조해 **다르면 잠그지 않는다**. 잠금 경로가 링크면 획득 자체가 거부된다.

**잠금은 가장 먼저 잡는다.** 예전에는 게이트 직전에 잡아 prune·sweep·run 생성·freeze 가
전부 잠금 밖이었다. 그래서 두 번째 호출이 첫 번째의 **살아있는 run 디렉터리를 삭제**할 수
있었고, 그 뒤 프롬프트의 diff 읽기가 관용돼 **빈 diff 를 리뷰시키고 실제 sha 로 PASS** 가
났다. 보호 대상에 손대기 전에 잡지 않는 잠금은 잠금이 아니다. `rs_prune_tasks` 는 다른
task 의 잠금을 **실제로 잡아 보고**, 잡히지 않으면 활성으로 보아 건드리지 않는다.
동결 diff 읽기는 `|| :` 관용을 걷고 **하드 실패**로 바꿨다(`prompt_incomplete`).

**attempt 는 예약이지 확정이 아니다.** 확정을 provider 시작 전에 하면, 그 사이에 죽었을 때
모델을 한 번도 부르지 않고 용량만 소진되고 클레임까지 남아 같은 sha 재시도도 막힌다.
그래서 예약은 `<task>/pending` 에 적고, 확정은 provider 가 **실제로 돌아온 뒤** 한다.
죽으면 잠금은 커널이 놓고, 다음 실행이 잠금을 쥔 채 `pending` 을 보고 클레임을 되돌린다.
불변식: **`attempt` == 실제로 완료된 provider 호출 횟수**.

#### 7.3.7 결과 계약은 **로컬에서 전수 검증**한다

Codex 의 `--output-schema` 는 신뢰 근거가 아니다(Claude 어댑터엔 그 기능이 없고, 스키마
자체가 교체될 수 있다). 그래서 `rs_classify_result` 가 선언된 계약을 전부 본다:
정확히 하나의 JSON object(`jq -s`, `length != 1` → ERROR), 최상위·`findings` 항목 모두
**필수 필드 존재 + 타입 + 미지 필드 금지**, `severity` 열거, `verdict ⟺ P0/P1 0건`.
Claude 에게는 프롬프트 본문에 같은 JSON Schema 를 함께 준다.

#### 7.3.8 이름공간 제한 (심층 방어, 2차)

실제 보증은 §7.3.3 이 진다. 그 **위에** 얹는 2차 방어로, 삭제 대상의 basename 을 자기가
만든 고정 형식으로 제한한다 — 헬퍼가 잘못 불리거나 우회되더라도 지워지는 이름이 사용자의
기존 자산을 가리킬 수 없게 한다.

- `run\.[0-9a-f]{32}` — run 디렉터리 (시작 스윕과 종료 정리)
- `[0-9a-f]{64}\.(claude|codex)\.json` — 결과 파일
- task 디렉터리(`rs_prune_tasks`)는 이름이 `--task-id` 라 사용자·공격자가 고를 수 있다.
  그래서 이름이 아니라 **내용**으로 좁힌다: 일반 파일 `state.tsv` 가 있을 때만 지운다.

**공격자가 이름을 고를 수 있는 글로브 삭제를 하지 않는다.** 옛 `rs_safe_purge_dir`
(`frozen/*`)과 봉투 스윕(`results/*.envelope`)은 공격자가 심은 이름을 그대로 지웠고,
봉투 스윕은 1000개 상한 때문에 항목이 그보다 많으면 대상을 **건너뛰는** 정확성 결함까지
있었다. 둘 다 제거했다. 남은 스윕(`run.*`)은 자기 이름공간만 훑으므로 상한이 없다.

**잔여 위험**: §11.4 그대로. 같은 사용자로 도는 프로세스는 여전히 상태를 고쳐 `PASS` 를
위조할 수 있고, 리뷰 중인 diff 를 읽을 수 있다. 이 절이 닫는 것은 그보다 좁고 구체적이다:
**게이트 자신이 관리 루트 밖으로 쓰기·삭제를 증폭시키는 경로**와 **provider 원문의 영속화**.

---

## 8. 명령 계약 (호출자 관점)

### 8.1 공통 인자

```
--worktree <dir>              기본: PWD
--scope working-tree|branch   기본: working-tree
--base <ref>                  scope=branch 일 때 필수
--task-id <id>                기본: §4.2 결정적 fallback
--author claude|codex         필수
```

`--scope` 는 기본값에 의존하지 말고 매번 정한다: `working-tree` 는 커밋된 변경을 못 보고,
`branch --base <ref>` 는 미커밋을 못 본다.

### 8.2 종료 코드

| code | 의미 |
|---|---|
| `0` | `PASS` 또는 `P2P3_CLOSED` — 진행 가능 |
| `10` | `CHANGES_REQUESTED` — P0/P1 수정 후 1회 재리뷰 |
| `20` | `BLOCKED_*` — 중단, 사람 판단 필요 |
| `2` | usage error (인자 오류, author==reviewer 등) |

`review-stop-guard.sh` 만 예외적으로 **항상 `exit 0`**.

### 8.3 환경변수

| 이름 | 기본 | 용도 |
|---|---|---|
| `CROSS_REVIEW_HOME` | (미설정) | 상태 루트 오버라이드 (**fixture 격리 필수**) |
| `CROSS_REVIEW_ROLE` | (미설정) | `reviewer` 면 게이트·훅 no-op |
| `CROSS_REVIEW_TIMEOUT` | `900` | reviewer 실행 상한(초) |
| `CROSS_REVIEW_ALLOW_OVERSIZE` | (미설정) | `1` 이면 oversize 명시 승인 |
| `CROSS_REVIEW_CLAUDE_BIN` | `claude` | 어댑터 바이너리 (fixture 주입용) |
| `CROSS_REVIEW_CODEX_BIN` | `codex` | 어댑터 바이너리 (fixture 주입용) |
| `CROSS_REVIEW_MAX_FILES` | `30` | oversize 파일 수 상한 |
| `CROSS_REVIEW_MAX_BYTES` | `51200` | oversize 바이트 상한 |
| `CROSS_REVIEW_MAX_RESULT_BYTES` | `262144` | reviewer 결과 원문 상한 (초과 시 미저장 + 차단) |
| `CROSS_REVIEW_KEEP_TASKS` | `20` | shard 당 유지할 task 디렉터리 수 |
| `CROSS_REVIEW_SCOPE` | `working-tree` | **Stop 가드**가 읽는 scope |
| `CROSS_REVIEW_BASE` | (미설정) | **Stop 가드**의 branch base. scope=branch 인데 없으면 fail-closed |
| `CROSS_REVIEW_TASK_ID` | (미설정) | **Stop 가드**가 읽을 task id 강제 지정 |

---

## 9. 배포 계약 (installer)

### 9.1 소유 자산

| 소스 | 설치 위치 | 트리거 |
|---|---|---|
| `global/cross-review/*.sh` | `~/.claude/hooks/cross-review/*.sh` (+`chmod +x`) | `--with-cross-review` |
| `global/settings-fragments/cross-review.json` | `~/.claude/settings-fragments/cross-review.json` | `--with-cross-review` |
| (동 조각의 hook identity) | `~/.claude/settings.json` 의 `hooks.Stop` 에 병합 | `--with-cross-review` |

### 9.2 불변식

1. **기본 설치와 `--full` 은 절대 배선하지 않는다.** `--full` 은 `WITH_CROSS_REVIEW` 를
   건드리지 않으며, 파일조차 설치하지 않는다 (verify-hooks 는 `--full` 시 조각 *파일*은
   설치하는데, 교차리뷰는 그보다 엄격하다 — Stop 훅과 provider 호출 경로를 여는 번들이라
   파일 존재만으로도 오인 활성화의 씨앗이 된다).
2. **기존 Stop 훅과 공존한다.** 조각 병합은 identity 단위 누적이므로, 사용자가 직접 쓴
   Stop 훅과 `--with-verify-hooks` 의 `stop-self-check` 가 그대로 남는다.
3. **번들은 자기 이름공간 안에만 쓴다** (`hooks/cross-review/`). 기존 글로벌 훅과 이름이
   겹치지 않는다.
4. **manifest/sweep 매핑.** 글로벌 scope 에 두 rel 접두를 추가했다:
   `hooks/cross-review/*` → `global/cross-review/`, `settings-fragments/*` →
   `global/settings-fragments/`. 프로젝트 scope 는 `.claude/` 접두를 쓰므로 충돌하지 않는다.
   이 매핑이 없으면 `sweep_removed_assets` 가 해당 rel 을 "관리 접두 아님"으로 보고 건너뛰어,
   소스에서 지워도 설치본이 영원히 남는다.
5. **재설치 점착성(sticky).** `--with-cross-review` 없이 재설치해도 이미 설치된 번들과
   병합된 Stop 엔트리는 **그대로 남는다**. `install_global_cross_review` 는 조기 return 하고,
   `sweep_removed_fragments` 는 소스 조각 파일이 여전히 존재하므로 "배포 중"으로 판정한다.
   → **해제는 `--uninstall` 뿐이다.** 플래그를 빼는 것은 해제가 아니다.
6. **Uninstall 은 소유분만 제거한다.** `uninstall_settings` 가 settings manifest 의
   fragment id 별 identity 만 unmerge 하고, `uninstall_manifest_root` 가 manifest 에 기록된
   파일만 지운다. 사용자가 직접 쓴 Stop 훅·다른 조각의 엔트리는 보존된다.

### 9.3 rollback

설치 중 실패는 기존 `rb_track` 저널이 원상복구한다. 교차리뷰 번들은 별도 rollback 경로를
만들지 않고 기존 `install_managed_file` / `merge_fragment_into` 경로를 그대로 탄다 —
새 경로를 만들면 검증되지 않은 두 번째 복구 코드가 생긴다.

---

## 10. 테스트 매트릭스

| ID | 시나리오 | 통과 기준 |
|---|---|---|
| X0 | 산출물 존재 | `global/cross-review/` 7종 존재 (`*.sh` 6 + `safe-fs.py`) |
| X1 | Codex reviewer argv | `--sandbox read-only` + `--output-schema` + `--cd` 존재, write/우회 플래그 부재 |
| X2 | Claude reviewer argv | `--restricted`, `--tools Read,Grep,Glob`, `--permission-mode manual` 존재. write 계열 도구 부재 |
| X3 | 정상 PASS | phase=`PASS`, exit 0, attempt=1 |
| X4 | P0/P1 → 재리뷰 1회 | 1차 exit 10 / `CHANGES_REQUESTED`, 수정 후 2차 PASS, attempt=2 |
| X5 | attempt cap | 3번째 호출 → `BLOCKED_ATTEMPTS`, 모델 호출 0회 |
| X6 | duplicate `(sha, reviewer)` | 수정 없이 재호출 → `BLOCKED_DUPLICATE`, 모델 호출 0회 |
| X7 | stale SHA | `BLOCKED_STALE` |
| X8 | 결과 파일 없음 | `BLOCKED_ERROR` |
| X9 | malformed JSON | `BLOCKED_ERROR` |
| X10 | 산문 PASS | `BLOCKED_ERROR` (PASS 추론 금지) |
| X11 | verdict/findings 모순 | `BLOCKED_ERROR` |
| X12 | P2/P3 only | `P2P3_CLOSED`, exit 0, 재리뷰 0회 |
| X13 | oversize files | 31 파일 → `BLOCKED_OVERSIZE`, 모델 호출 0회 |
| X14 | oversize bytes | >50KiB → `BLOCKED_OVERSIZE` |
| X15 | oversize 승인 | `CROSS_REVIEW_ALLOW_OVERSIZE=1` → 통과 |
| X16 | timeout | `BLOCKED_*`, PASS 아님 |
| X17 | reviewer mutation | `BLOCKED_MUTATION` |
| X18 | stop hook 재진입 | `stop_hook_active=true` → 호출 0회, 상태 기록 없음, exit 0 |
| X19 | reviewer role no-op | `CROSS_REVIEW_ROLE=reviewer` → 상태 기록 없음 |
| X20 | stop guard 기록 | 미검토 종료 → `BLOCKED_UNREVIEWED` 기록 + exit 0 (차단 아님) |
| X21 | stop guard 통과 | `reviewed_sha == 현재 sha` → PASS 유지 |
| X22 | 자기검토 금지 | author==reviewer → exit 2, 모델 호출 0회 |
| **X23** | **저장소 무오염** | 리뷰 후 대상 repo `git status --porcelain` 비어 있고 `<repo>/.claude/cross-review` 미생성 |
| X24 | 시크릿 미영속 | provider stdout 토큰이 `state.tsv` 에 없음 |
| **X25** | **기본·`--full` 미배선** | 두 경우 모두 settings 에 `cross-review` identity 부재 **+** `~/.claude/hooks/cross-review/` 미생성 |
| **X26** | **opt-in 배포** | temp HOME 에서 `--with-cross-review` → 스크립트 **7종**(`safe-fs.py` 포함) 설치(+실행권한), 조각 파일 설치, Stop 배선 |
| **X27** | **기존 Stop 훅 보존** | 사용자 작성 Stop 훅을 seed → 설치·재설치·uninstall 전 구간에서 byte-identical 생존, uninstall 후엔 cross-review identity 만 사라짐 |
| **X29** | **재설치 멱등** | 같은 HOME 에 2회 설치 → Stop 엔트리 중복 없음, 상태 동일 |
| **X29b** | **점착(sticky) 재설치** | 플래그 **없이** 재설치 → 번들 파일·Stop 배선 모두 유지 (§9.2-5 의 감시자) |
| **X30** | **상태 경로·권한** | 상태가 `<home>/state/cross-review/<sha256>/tasks/<id>` 레이아웃, 디렉터리 mode 700 |
| **X31** | **실 HOME 무오염** | 스위트 종료 시 실제 `~/.claude/state/cross-review` 미생성 |
| **X32** | **보존 정책** | 리뷰 후(PASS·차단 모두) task 디렉터리 **어디에도** `*.diff`·`prompt.txt` 미잔류 (`find` 로 전수 확인 — run 디렉터리로 옮겨 숨는 것을 막는다) |
| **X33** | **결과 크기 상한** | 초과 결과 → `BLOCKED_ERROR(result_oversize)`, 디스크 미저장 |
| **X34** | **예상치 못한 종료코드** | provider rc=42 + 유효해 보이는 결과 → `BLOCKED_ERROR(provider_rc)` |
| **X35** | **타임아웃 고아** | 상한 초과 시 provider 자식까지 종료, worktree **밖** sentinel 미생성 |
| **X36** | **프레이밍 nonce** | BEGIN/END 마커에 32-hex nonce, 실행마다 상이, 내용·파일명 주입이 프레이밍을 끊지 못함 |
| **X37** | **branch scope 가드** | (a) base 없음 → `BLOCKED_ERROR(branch_base_missing)` (b) 정상 branch 리뷰 후 `PASS` 유지 |
| **X38** | **원문 미영속** | provider rc≠0·정상 양쪽에서 `*.envelope` 부재 + 원문 카나리가 상태 루트에 미영속 (§7.3.2) |
| **X39** | **적대적 경로/링크(삭제)** | `frozen/`·`prompt.txt`·task 디렉터리가 링크여도 링크 너머 파일 미삭제 |
| **X40** | **적대적 경로/링크(쓰기)** | 하위 디렉터리·출력 파일이 링크여도 피해자 파일 불변, 소스·프롬프트 미유출, 링크는 **따라가지도 지우지도 않고 거부만**(exit 20), provider 미호출 |
| **X41** | **SIGKILL 중 원문 미영속** | provider 가 원문을 뱉기 시작한 뒤 바깥 어댑터를 `SIGKILL` → 카나리가 `$CROSS_REVIEW_HOME` 어디에도 미도달 (전제: provider 가 실제로 뱉었음을 관리 루트 **밖** sentinel 로 확인) |
| **X42** | **결과 경로 사전 심기 거부** | `results/<sha>.<reviewer>.json` 에 링크를 미리 심어도 O_EXCL open 이 실패 → exit 20, 링크 너머 피해자 불변, 원문 유출 0 |
| **X43** | **조상 스왑 경합** | (a) 삭제 이름공간이 공격자 선택 이름을 받지 않음 (b) 조상 링크 스왑 시 **동일 이름**의 피해자 항목도 삭제되지 않음 (c) 리뷰 중 스왑 스트레스 (d) **검사~쓰기 사이 결정적 스왑**에도 피해자 `state.tsv` 불변 — 사보타주로 RED 확인 (§7.3.3) |
| **X44** | **1000개 초과 스윕** | 정체된 `run.*` 1001개 → 시작 스윕이 **전부** 회수 (상한 우회 없음) |
| **X45** | **provider 경로 개방 제거** | provider **호출 시점**에 관리 트리에 `prompt.txt`/`schema.json`/`last.json` 부재 + 실행 중 run 디렉터리 스왑에도 피해자 불변·소스 미유출 + 프롬프트가 stdin 으로 실제 도달 + 스키마가 `/dev/fd` 로 읽힘 |
| **X46** | **관리 성분 링크 거부** | `<home>/state` 를 링크로 심으면 exit 20, 링크 너머 파일·**모드** 불변, 피해자에 상태 구조 미생성 |
| **X47** | **저장소 통제 git 실행 차단** | `.gitattributes`+`textconv`/`diff.external`/`core.fsmonitor` 로 심은 sentinel 미실행, 그래도 diff 는 정상 수집 |
| **X48** | **원문 미영속 전 경로** | PASS·nonzero·타임아웃 전부에서 카나리 부재 + task 디렉터리에 `*.json` 부재; 스트리밍 상한 초과 → `result_oversize` |
| **X49** | **결과 계약 전수 강제** | 최상위 미지 필드·P3 필수 필드 누락·finding 미지 필드·JSON 2개·타입 오류 전부 `BLOCKED_ERROR`; Claude 프롬프트에 스키마 포함 |
| **X50** | **수집 오류·특이 파일명** | 존재하지 않는 `--base` → `BLOCKED_ERROR`(빈 diff PASS 아님); 개행 든 untracked 파일명이 동결 diff 에 포함 |
| **X51** | **원자적 클레임·기록 실패 차단** | 선점된 클레임 → `BLOCKED_DUPLICATE` + provider 미호출; `python3` 부재 → exit 20 + 사유 출력 + provider 미호출 |
| **X52** | **Stop 가드 임시파일·열화** | ambient tmp 에 원문 미잔류; `python3` 부재에도 advisory 출력 + 기록 불가 명시(침묵 아님), exit 0 유지 |
| **X53** | **결과 본문 미영속(H1)** | 분류~purge 창(state.tsv 교체 시점)에 관리 트리를 훑어 결과 카나리 부재 — 종료 후 검사만으로는 purge 가 가려서 못 잡는다 |
| **X54** | **task 범위 직렬화(H2)** | 잠금 점유 중 → `task_locked` + provider 미호출; reviewer 다른 동시 호출에서 **attempt == provider 호출 횟수** 유지 |
| **X55** | **잠금 상호배제·자동해제** | 보유 중 두 번째 획득 거부; 보유 프로세스 SIGKILL 후 잠금 자동 해제(영구 데드락 없음) |
| **X56** | **잠금 순서·빈 diff 차단** | 살아있는 잠금 중 남의 run 아티팩트 미삭제 + provider 미호출; 동결 diff 소실 시 PASS 하지 않음 |
| **X57** | **예약/확정 분리와 복구** | provider 미호출이면 attempt 미확정; 중단된 예약은 다음 실행이 롤백해 같은 sha 재리뷰 가능; **대조군**(pending 없는 클레임)은 그대로 차단 |
| **X58** | **잠금 소유권(R5-P1-3)** | 잠금을 대신 쥔 상주 프로세스 0개(수명 = 리뷰 프로세스), 보유 중 재획득 거부, 해제 후 재획득 가능, 잠금 경로가 링크면 획득 거부(피해자 불변), 보유 프로세스 SIGKILL 시 커널이 해제 |
| **X59** | **prune 잠금 보유(R4-P1-2)** | `rs_lock_take` 보유 중 타 실행 획득 실패, `rs_lock_untake` 후 해제; 삭제 경로가 보유형 잠금을 사용(호출부 결속) |
| **X60** | **예약 실패 차단(R4-P1-3)** | pending 쓰기 실패 → `pending_write_failed` + provider 미호출 + **클레임 롤백**(사보타주 제거 후 같은 sha 재리뷰 가능); 해제 실패 → `pending_clear_failed` |
| **X61** | **unborn 스테이지 diff(R5-P1-1)** | HEAD 없는 저장소에서 **스테이지만 된** 첫 커밋 내용·경로가 동결 diff 에 포함(빈 diff PASS 아님) |
| **X62** | **종결 기록 실패 차단(R5-P1-2)** | 종결 상태를 못 쓰면 exit 20 + 사유 출력 + **PASS 문구 없음** (reviewed_sha 없이 통과 금지) |
| **X63** | **reviewer cwd 고정(R6-P1-1)** | 다른 디렉토리에서 호출해도 Claude reviewer 가 **대상 워크트리**에서 실행됨 (`--add-dir` 은 cwd 를 바꾸지 않는다) |
| **X64** | **정리 실패 차단(R6-P2-2)** | run 디렉토리를 삭제 불가로 만들면 exit≠0 + 정리 실패를 **stderr 로 알림** (잠금 획득 후 stderr 가 살아 있음을 함께 감시) |
| **X65** | **잠금 fd 결속(R6-P1-2)** | fd 가 그 경로의 그 파일이 아니면 flock 거부 (사전·사후 (dev,ino) 대조) |
| **X66** | **대상 index 불변(R7-P1)** | stat 만 낡은 추적 파일이 있어도 리뷰 전후 `.git/index` 해시 불변 (`--no-optional-locks` + `diff.autoRefreshIndex=false`) |
| **X67** | **동결 스트리밍 상한(R8-P1-1)** | 상한 초과 시 safe-fs 가 exit 2 + 부분 파일 삭제; 큰 diff 는 **쓰기 중** 중단돼 `BLOCKED_OVERSIZE`(전량 기록 후 사후 거절 아님), `ALLOW_OVERSIZE=1` 대조군은 통과 |
| **X68** | **jq 요구(R8-P1-2)** | jq 없는 PATH 에서 `--with-cross-review` 설치 거부(훅 미배포) + Stop 가드가 무동작을 **경고**하며 exit 0 유지 |
| X28 | 문법 | shell 6종 `bash -n` + `safe-fs.py` 파이썬 문법 통과 |

굵은 항목이 이번 배치 변경으로 **의미가 달라진** 케이스다. 기존 스위트(`tests/test-*.sh`)
전체도 회귀 없이 통과해야 한다.

---

## 11. 위협 모델의 한계 (명시)

**이것은 협력적 워크플로 게이트이지, 적대적 보안 경계가 아니다.** 구체적으로:

1. **우회가 설계상 가능하다.** Stop 가드는 **항상 `exit 0`** 이다(§3). author 가 reviewer 를
   한 번도 부르지 않고 세션을 끝내도 막히지 않는다 — 상태에 `BLOCKED_UNREVIEWED` 가 남을 뿐이다.
   이것은 결함이 아니라 선택이다(훅이 세션을 되살리면 그 자체가 재진입 경로다).
2. **reviewer 는 LLM 이다.** 판단은 diff 내용에 의해 유도될 수 있다. nonce 프레이밍(§7)은
   구분자 위조의 문턱을 올릴 뿐 프롬프트 인젝션을 **닫지 못한다**. 스키마·SHA 바인딩이
   막는 것은 "형식이 틀린/오래된 결과를 PASS 로 오인하는 것"이지, "그럴듯하게 틀린 리뷰"가 아니다.
3. **read-only 격리는 CLI 에 의존한다.** `--sandbox read-only`·`--restricted`·도구 화이트리스트가
   실제로 강제하는 범위는 provider CLI 의 구현이다. tree 지문(§6.2)은 **사후 탐지**이지 예방이 아니다.
   네트워크 경계는 주장하지 않는다.
4. **잠금 파일 열기에는 셸이 닫을 수 없는 창이 있다.** 셸 리다이렉션(`exec 9>>`)은
   `O_NOFOLLOW` 를 쓸 수 없다. 그래서 (1) safe-fs 로 안전 생성 → (2) `nolink` 확인 →
   (3) 셸이 열기 → (4) `flockfd` 가 (dev,ino) 대조, 순서로 창을 좁힌다. (2)~(3) 사이에
   같은 사용자가 링크를 심으면 **링크가 가리킨 경로에 빈 파일이 생길 수 있다**(append
   오픈; 우리는 쓰지 않는다). 잠금 자체는 (4)에서 거부된다. 그 사용자는 그 파일을
   직접 만들 수도 있으므로 권한 상승은 없다. 완전 차단은 드라이버를 한 프로세스로
   (Python) 옮겨야 하며, 그것은 §8 어댑터 계약의 재작성이다.
5. **`--uninstall` 은 동일 identity 중복을 구분하지 못한다.** 사용자가 설치본과
   **바이트 단위로 같은** Stop 훅 항목을 따로 추가하면, 제거는 identity 기준이라 어느
   쪽이 남는지 구분되지 않는다(공용 병합 엔진의 성질이며 모든 조각에 해당한다).
   실질 영향은 "삭제된 스크립트를 가리키는 항목이 남는 것"이고, 명령이 **다른** 사용자
   훅은 그대로 보존된다(X27). 이 게이트가 도입한 결함이 아니라 병합 엔진의 알려진 한계다.
6. **잠금은 같은 사용자의 경로 스왑까지는 막지 않는다.** 잠금은 리뷰 프로세스의 fd 에
   걸리고 획득 시 `(dev, ino)` 대조로 바꿔치기를 거부한다(§7.3.6). 다만 획득 **이후**
   같은 사용자가 잠금 경로를 다른 파일로 바꾸면, 우리는 원래 inode 를, 다음 실행은 새
   inode 를 잠가 상호배제가 무너진다. 상태 루트가 700 이라 그 행위자는 이미 상태를 직접
   고칠 수 있는 같은 사용자이며(아래 5), 이 게이트가 방어하는 대상이 아니다.
7. **상태는 신뢰 경계가 아니다.** `~/.claude/state/cross-review/` 는 owner-only(700)지만, 그 사용자로
   실행되는 어떤 프로세스도 상태를 고쳐 `PASS` 를 위조할 수 있다.

즉 이 게이트가 방어하는 것은 **실수와 성급한 완료 선언**이지, 자기 코드를 통과시키려고 적극적으로
게이트를 속이는 행위자가 아니다.

---

## 12. Rollout HOLD

구현까지만 진행하고, 다음은 사람 승인 전까지 하지 않는다.

1. ~~**전역 활성화 금지**~~ → **2026-09-11 사용자 승인으로 활성화 완료.** 실제 `$HOME` 에
   `--global-only --with-cross-review` 적용. 검증: 스크립트 7종 설치(실행권한), 기존 Stop 훅
   4개 전원 보존 + cross-review 1개 추가(4→5), 가드 advisory 동작 117ms·exit 0,
   상태 디렉터리 700, 대상 저장소 무오염. 백업: `~/.claude/settings.json.bak.1`.
2. ~~**live provider smoke = `PENDING`**~~ → **2026-09-11 통과.** 실 `codex exec` 로
   end-to-end 를 돌렸다(14초, `CHANGES_REQUESTED`, P0 2건 검출, `attempt=1`·`reviewed_sha`
   기록, run 아티팩트·원문 0건 잔류).

   **그 과정에서 계약이 하나 깨져 있었음을 확인하고 고쳤다.** codex-cli 0.153.4 는
   `/dev/fd/N` 을 **읽지도 쓰지도 못한다** — `--output-schema /dev/fd/5` 와
   `--output-last-message /dev/fd/4` 둘 다 `Bad file descriptor (os error 9)` 로 실패한다
   (fd 4 가 파이프가 아니라 일반 파일이어도 동일). 예고한 대로 fail closed 로 끝났을 뿐
   조용한 PASS 는 없었다. 대체 계약:
   - 출력 스키마 → 스크립트 옆의 **정적 자산** `result-schema.json` (관리 상태 트리 아님)
   - 결과 → `--json` 이벤트 스트림의 마지막 `agent_message` 를 `.item.text` 로 추출

   **Claude 어댑터도 같은 날 통과했고, 여기서도 계약이 깨져 있었다.** `--output-format json`
   의 봉투는 단일 객체가 아니라 **이벤트 배열**이다(claude 2.1.267: `system/init` ·
   `rate_limit_event` · `assistant` · `result/success`). `.result` 만 보던 필터가 배열에서
   빈 문자열을 내 **모든 Claude 리뷰가 BLOCKED_ERROR** 로 끝났다. 배열의 마지막
   `type=="result"`(그리고 `is_error != true`)에서 `.result` 를 뽑도록 고쳤고, 옛 CLI 의
   객체 형태도 계속 받는다. 실측: exit 10 / `CHANGES_REQUESTED`, 18초, P0·P1 검출.

3. **enable/config mutation, 외부 메시지, commit/push/merge 는 STOP/HITL.**
4. 파일럿은 10~20 task 규모로 호출 수·소요·모델 사용량을 실측한 뒤에만 확대한다.
