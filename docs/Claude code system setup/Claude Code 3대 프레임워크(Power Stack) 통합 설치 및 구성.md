---
tags:
  - claude
  - setup
---

# 🚀 [가이드] Claude Code 3대 프레임워크(Power Stack) 활용 가이드

> 최종 업데이트: 2026-07-15
> Claude Code: v2.1.210 | Models: Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5
> **중요한 변화**: 이전 버전(2026-03)에서는 수동 설치 가이드였으나, 이후 세 프레임워크는 스킬 형태로 제공되어 **설치되어 있다면** 스킬 호출만으로 사용 가능합니다(즉, 설치 여부 확인이 선행되어야 함 — 아래 경고 참조).

> ⚠️ **설치 여부 먼저 확인**: `superpowers:*` 계열은 이 환경에서 기본 사용 가능하지만, **GSD(`gsd:*`)와 Gstack(`gstack-*`)은 이 환경에 기본 설치되어 있지 않습니다**(현재 available-skills에는 `superpowers:*`만 존재). `/help` 또는 시스템 프롬프트의 available-skills에서 실제 설치 여부를 **먼저** 확인하세요.
> - 미설치 상태에서 `/gsd:new-project`·`/gstack-plan-ceo-review` 등을 첫 스텝으로 실행하면 **명령을 찾지 못해 실패**합니다.
> - GSD/Gstack은 별도(서드파티/선택) 스킬 팩입니다. 없으면 이미 설치된 **superpowers / ecc 오케스트레이션** 또는 **글로벌 Advisor–Worker–Codex** 흐름으로 동일한 기획→구현→검증 파이프라인을 대체할 수 있습니다.

이 가이드는 Claude Code가 **기획(Gstack) ➡️ 컨텍스트 관리(GSD) ➡️ TDD 개발(Superpowers) ➡️ 최종 검증(Gstack)** 의 흐름으로 작업하도록 활용하는 방법을 설명합니다.

> ✅ **기본 `.claude` 셋업은 원샷 설치**: 이 워크플로우가 기대는 최소 `.claude/` 스캐폴딩(커맨드·훅·`settings.json`·`MODELS.md`)은 같은 폴더의 **`./install.sh <target-project-dir>`** 한 번으로 설치됩니다(멱등). 아래 수동 절차는 동등한 대안입니다. 단 **GSD(`gsd:*`)·Gstack(`gstack-*`) 스킬 팩은 install.sh 범위 밖**(별도 서드파티 설치)이라는 점에 유의하세요 — 위 경고 참조.

---

## 1단계: 무엇이 바뀌었나 (2026-03 → 2026-05)

| 항목 | 2026-03 (수동 설치) | 2026-05 (공식 스킬) |
|------|------------------|------------------|
| Gstack | `.gstack/personas/` 디렉토리 생성, 페르소나 .md 파일 직접 작성 | `gstack-*` 스킬 호출 (예: `/gstack-plan-eng-review`) |
| GSD | `.gsd/states/current_state.md` 수동 관리 | `gsd:*` 스킬 호출 (예: `/gsd:new-project`, `/gsd:plan-phase`, `/gsd:execute-phase`) |
| Superpowers | `.superpowers/specs/` 디렉토리에 스펙 직접 작성 | `superpowers:*` 스킬 호출 (예: `/superpowers:brainstorming`, `/superpowers:writing-plans`) |
| CLAUDE.md 업데이트 | 4단계 워크플로우를 수동 명시 | 스킬 description으로 자동 트리거 — CLAUDE.md에는 명시 불필요 |

**결론**: 이전 가이드의 디렉토리 구조와 페르소나 파일 작성은 모두 obsolete. 스킬 호출만으로 동일 워크플로우 작동.

---

## 2단계: 4단계 Power Stack 워크플로우 (스킬 기반)

### Phase 1: 기획 및 설계 (Gstack Mode)

새 기능 또는 큰 변경을 시작할 때 사용.

<!-- 요구: gstack 설치됨. 미설치 시 /gstack-* 는 실패 — superpowers/글로벌 Advisor 흐름으로 대체 -->

```text
/superpowers:brainstorming    # 사용자 의도, 요구사항, 설계 옵션 탐색
/gstack-plan-ceo-review       # CEO 관점 — 10-star product, scope 검증 (gstack 설치 시)
/gstack-plan-eng-review       # 엔지니어링 매니저 관점 — 아키텍처, edge case, 성능
```

**언제 사용**: "기능 추가", "리팩토링", "새 모듈", "디자인 의사결정" 시점.
**산출물**: 명확한 요구사항 + 검증된 계획.

### Phase 2: 작업 분할 및 상태 관리 (GSD Mode)

마일스톤 단위로 작업을 쪼개고, 컨텍스트 압축에 견디는 상태 관리.

<!-- 요구: gsd 설치됨. 미설치 시 /gsd:* 는 실패 — superpowers/글로벌 Advisor 흐름으로 대체 -->

```text
/gsd:new-project              # 새 프로젝트 초기화 (PROJECT.md 생성) (gsd 설치 시)
/gsd:new-milestone            # 마일스톤 사이클 시작
/gsd:add-phase                # 마일스톤에 phase 추가
/gsd:discuss-phase            # phase 컨텍스트 수집 (적응형 질문)
/gsd:plan-phase               # 상세 phase 계획 (PLAN.md 생성, 검증 루프 포함)
/gsd:execute-phase            # phase 내 plan들을 웨이브 기반 병렬 실행
/gsd:progress                 # 진행 상태 확인 및 다음 단계 라우팅
/gsd:resume-work              # 다른 세션에서 이어서 작업 (컨텍스트 복원)
/gsd:pause-work               # 작업 중 일시 정지 + 핸드오프 생성
```

**핵심 원칙**:
- 컨텍스트 75% 도달 전 `/gsd:pause-work`로 상태 저장 → 새 세션에서 `/gsd:resume-work`로 복원
- 마일스톤 종료 시 `/gsd:audit-milestone` → `/gsd:complete-milestone`

### Phase 3: 코드 구현 (Superpowers Mode)

TDD와 병렬 에이전트 실행으로 빠르고 견고하게 구현.

```text
/superpowers:writing-plans                 # 스펙 → 단계별 plan 작성
/superpowers:test-driven-development       # RED → GREEN → IMPROVE 사이클 강제
/superpowers:executing-plans               # plan을 별도 세션에서 실행 (checkpoint 포함)
/superpowers:subagent-driven-development   # 현재 세션 내에서 독립 태스크 병렬 실행
/superpowers:dispatching-parallel-agents   # 2+ 독립 태스크 시 자동 병렬화
/superpowers:using-git-worktrees           # worktree 격리로 메인 작업과 충돌 방지
/superpowers:systematic-debugging          # 버그 발생 시 가설 검증 사이클
```

**도구 차이**:
- `executing-plans` vs `subagent-driven-development`: 전자는 별도 세션(완전 독립 컨텍스트), 후자는 현재 세션 내 서브에이전트
- `dispatching-parallel-agents` vs `using-git-worktrees`: 전자는 일반 병렬, 후자는 파일 충돌 방지가 필요할 때
- Workflow 도구(인라인 JS)로 `agent()`/`parallel()`/`pipeline()`을 묶어 다단계 파이프라인을 결정론적으로 구성 가능

### Phase 4: 최종 검증 (Gstack QA Mode)

릴리스 전 안전성/품질/보안 검증.

```text
/superpowers:verification-before-completion   # 검증 명령 실행 후에만 "완료" 선언
/superpowers:requesting-code-review           # 작업 완료 검토 요청
/gstack-review                                # PR 사전 리뷰 (SQL safety, LLM 경계, side effect)
/gstack-codex                                 # OpenAI Codex CLI로 2차 의견 (review/challenge/consult)
/gstack-cso                                   # 보안 감사 (OWASP, STRIDE, 시크릿 아카이브)
/gstack-qa                                    # 실제 브라우저로 사이트 QA + 버그 자동 수정
/gstack-design-review                         # 디자이너 시각으로 UI 일관성 감사
```

**Safety 모드** (특히 prod 작업 시):
```text
/gstack-careful    # 파괴적 명령(rm -rf, DROP TABLE, force-push) 경고
/gstack-freeze     # 특정 디렉토리만 편집 허용
/gstack-guard      # careful + freeze 결합
```

---

## 3단계: 자주 쓰는 콤보 패턴

### 패턴 A: 새 프로젝트 시작
```
/gsd:new-project → /superpowers:brainstorming → /gstack-plan-ceo-review
→ /gsd:add-phase → /gsd:plan-phase → /gsd:execute-phase
```

### 패턴 B: 버그 수정
```
/superpowers:systematic-debugging → /superpowers:test-driven-development
→ /superpowers:verification-before-completion → /gstack-review
```

### 패턴 C: 큰 리팩토링
```
/superpowers:brainstorming → /gstack-plan-eng-review
→ /superpowers:writing-plans → /superpowers:using-git-worktrees
→ /superpowers:subagent-driven-development → /gstack-codex
```

### 패턴 D: 프로덕션 핫픽스 (최대 안전)
```
/gstack-guard → /superpowers:systematic-debugging
→ /superpowers:test-driven-development → /gstack-review → /gstack-cso
```

---

## 4단계: 컨텍스트 관리 (GSD 핵심 기법)

컨텍스트가 75%를 넘어가면 새 세션으로 분기하는 것이 더 빠릅니다.

```text
1. 현재 작업 저장:    /gsd:pause-work     (핸드오프 마크다운 생성)
2. 새 세션 시작:      (터미널에서 새 claude 실행)
3. 상태 복원:         /gsd:resume-work    (이전 핸드오프 자동 검색 및 로드)
```

`/clear` 명령으로 컨텍스트만 비우고 동일 세션을 유지할 수도 있지만, **장기 작업에는 새 세션 + resume이 더 안정적**입니다.

---

## 5단계: 빠른 진입 — 한 줄 입력으로 시작하기

복잡한 콤보를 기억할 필요 없이, 다음 단일 명령들이 라우터처럼 작동합니다:

| 명령 | 동작 |
|------|------|
| `/gsd:do` | 자유 텍스트를 읽고 적절한 GSD 명령으로 라우팅 |
| `/gsd:next` | 현재 상태에서 가장 적절한 다음 단계 자동 실행 |
| `/gsd:progress` | 진행 상태 보고 + 다음 액션 라우팅 |
| `/gstack-autoplan` | CEO/디자인/엔지니어링/DX 리뷰를 순차 자동 실행 |

**처음 사용자라면**: `/gsd:help` 또는 `/gsd:join-discord`로 커뮤니티 자료 확인.

---

## 부록: 이전 가이드의 수동 설치는 더 이상 필요 없음

이전 버전(2026-03)에서 안내했던:

```bash
mkdir -p .gstack/personas .gsd/states .superpowers/specs
touch .gstack/personas/QA_Lead.md
touch .gstack/personas/Engineer_Manager.md
touch .gsd/states/current_state.md
```

이런 디렉토리/파일 생성은 **현재 불필요**합니다. 위 모든 스킬은 자체적으로 필요한 상태 파일을 관리합니다 (`.planning/`, `dev/active/`, 메모리 시스템 등).

기존 프로젝트에서 이 디렉토리들이 이미 있다면 그대로 두어도 무방 — 단, 신규 워크플로우에서는 참조하지 않습니다.

---

*이 문서는 Claude Code v2.1.210 (2026-07 기준) 환경을 가정합니다. 스킬 목록은 `/help` 또는 시스템 프롬프트에서 항상 최신 상태로 확인하세요.*
