---
tags:
  - claude
  - setup
---

# CLI Orchestration 설정 가이드
#claude-code #orchestration #multi-agent #cli

> 최종 업데이트: 2026-07-15
> Claude Code: v2.1.210 | 설정: .claude/settings.json
> Models: Opus 4.8 (claude-opus-4-8, 1M 변형 존재) / Fable 5 (claude-fable-5) / Sonnet 5 (claude-sonnet-5, 1M) / Haiku 4.5 (claude-haiku-4-5-20251001)
> ※ 2026-06-16 갱신: 플래그십이 Opus 4.8로 갱신되고 신규 세대 Fable 5 추가. `/fast` 모드는 Opus 4.8/4.7을 작은 모델로 다운그레이드하지 않고 Opus 그대로 빠른 출력으로 실행.

## 🎯 개요

CLI Orchestration은 여러 에이전트를 조율하여 복잡한 작업을 자동화하는 시스템입니다.
Claude Code v2.1.210은 `cli-orchestrator`와 `Primary Coordinator` 내장 에이전트를 제공합니다.

## 📋 내장 오케스트레이션 에이전트

### 1. cli-orchestrator
멀티 목적 CLI 오케스트레이션 에이전트:
- 여러 에이전트를 조율하는 복잡한 작업
- CLI 도구의 순차/병렬 실행 (빌드→테스트→배포)
- 새 프로젝트 자동 부트스트래핑

**사용 시기**: "orchestrate", "pipeline", "bootstrap", "병렬 실행", "여러 에이전트" 등의 키워드

**가용 도구**: Bash, Read, Write, Edit, Glob, Grep, Task, TodoWrite

### 2. Primary Coordinator
멀티 에이전트 워크플로우 조율자:
- 복잡한 작업의 전략적 분해
- 공유 리소스 충돌 해결
- 윤리적 검증 게이트

**사용 시기**: "coordinate", "orchestrate agents", "multi-agent" 등의 키워드

**가용 도구**: Bash, Read, Write, Edit, Glob, Grep, Task, TodoWrite

## 🚀 오케스트레이션 패턴

### 패턴 1: 순차 파이프라인
```bash
# 빌드 → 테스트 → 배포 순차 실행
claude "Orchestrate: build the project, run all tests, then deploy to staging"
```
> ※ 2026-06-16 갱신: 단계가 고정된 결정론적 순차 흐름이라면 이제 Workflow 도구의 `pipeline(items, stage1, stage2, ...)`로 항목별 독립 파이프라인을 명시적으로 표현할 수 있다(아래 "Workflow 도구 vs 커스텀 조율 에이전트" 참조).

### 패턴 2: 병렬 분석
```bash
# 여러 분석을 동시 실행
claude "In parallel:
1. Run security audit on the codebase
2. Analyze performance bottlenecks
3. Check code coverage
Then combine results into a single report"
```
> ※ 2026-06-16 갱신: 결정론적 팬아웃이라면 Workflow 도구의 `parallel(thunks)`로 동시 실행 + 배리어(모두 완료 후 반환, 실패 항목은 null)를 그대로 코드로 표현 가능. 동시 실행은 자동으로 min(16, cpu코어-2)로 캡되고 총 1000 에이전트 상한이 적용된다.

### 패턴 3: 설계→구현→검증
```bash
# 멀티 에이전트 협업
# ※ 2026-06-16 갱신: "네임스페이스 완전 평탄화"는 부정확. 플랫 빌트인 에이전트(general-purpose, Explore, Plan, planner, architect, code-reviewer, security-reviewer 등)와 플러그인 스코프 에이전트(ecc:architect, ecc:python-reviewer 같은 ecc:* 네임스페이스)가 공존함.
claude "Coordinate these agents:
1. Plan agent: Design the API architecture
2. architect: Define data models
3. general-purpose: Implement endpoints
4. test-automation-specialist: Run build and test verification"
```

### 패턴 4: Worktree 격리 병렬 작업
```bash
# 독립적인 작업을 격리된 환경에서 동시 실행
claude "Execute in parallel with worktree isolation:
1. Refactor the auth module
2. Add new payment endpoints
Each should run tests independently before returning"
```
> ※ 2026-06-16 갱신: worktree 격리는 Workflow 도구의 `agent(prompt, { isolation: 'worktree' })` 옵션, 또는 Agent 도구의 `isolation:'worktree'`로 표현한다(에이전트가 자체 git worktree에서 실행되고 미변경 시 자동 정리). 라이프사이클을 직접 다룰 때는 EnterWorktree / ExitWorktree 도구를 사용한다.

## 🧭 Workflow 도구 vs 커스텀 조율 에이전트 (선택 가이드)

> ※ 2026-06-16 신규: 같은 "여러 에이전트 조율"이라도 흐름이 **결정론적**이냐 **대화형 적응**이냐에 따라 도구를 다르게 골라야 한다.

| 상황 | 선택 | 이유 |
|------|------|------|
| 단계/팬아웃이 고정된 결정론적 흐름 (빌드→테스트→배포, N개 항목 동시 분석) | **Workflow 도구** (`parallel` / `pipeline`) | 흐름이 코드로 명시되어 재현 가능, 배리어·동시 실행 캡·실패 처리가 내장 |
| 중간 결과를 보고 다음 단계를 적응적으로 결정하는 대화형 조율 | **cli-orchestrator / Primary Coordinator 에이전트** | 상황 판단·전략적 분해·충돌 해결을 모델이 동적으로 수행 |

### Workflow 도구란

인라인 JS 스크립트로 결정론적 조율을 표현한다. 반드시 순수 리터럴 `export const meta = { name, description, phases }`로 시작하고, 본문에서 아래 전역 함수를 `await`로 직접 사용한다.

- `agent(prompt, opts?)` — 서브에이전트 실행. `opts = { label, phase, schema, model, effort, isolation:'worktree', agentType }`. `schema`를 주면 검증된 객체를 반환한다.
- `parallel(thunks)` — 동시 실행 + 배리어(모두 완료 후 반환). 실패 항목은 `null`.
- `pipeline(items, stage1, stage2, ...)` — 항목별 독립 파이프라인, 단계 간 배리어 없음.
- `phase(title)`, `log(message)`, `args(입력값)`, `budget(토큰 예산)`, `workflow(name, args)`(중첩 1단계).

동시 실행은 자동으로 `min(16, cpu코어-2)`로 캡되고 총 1000 에이전트 상한이 적용된다. 백그라운드 실행 후 완료 알림을 받는다.

```js
// 결정론적 팬아웃: 세 분석을 동시에 돌리고 모두 모인 뒤 합치기
export const meta = {
  name: "codebase-audit",
  description: "보안·성능·커버리지 동시 분석 후 통합",
  phases: ["analyze", "report"],
};

phase("analyze");
const [security, perf, coverage] = await parallel([
  () => agent("Run security audit on the codebase", { label: "security" }),
  () => agent("Analyze performance bottlenecks", { label: "perf" }),
  () => agent("Check test coverage gaps", { label: "coverage" }),
]);

phase("report");
await agent(`Combine these findings into one report:\n${log(security)}`);
```

```js
// 결정론적 파이프라인: 항목마다 설계 → 구현 단계를 독립적으로 진행
export const meta = {
  name: "feature-pipeline",
  description: "기능별 설계→구현 파이프라인",
  phases: ["design", "implement"],
};

await pipeline(
  args().features,
  (f) => agent(`Design the API for ${f}`, { agentType: "architect" }),
  (design) => agent(`Implement endpoints for this design:\n${design}`, {
    isolation: "worktree",
  }),
);
```

> ⚠️ 날조 API 금지: `workflow.pipeline([{task, agent, depends}])`, `.withIsolation().run()`, `workflow.background()` 같은 fluent builder 체인은 **존재하지 않는다**. 위의 전역 함수 시그니처만 사용할 것.

### 조율 에이전트란

`cli-orchestrator` / `Primary Coordinator`는 흐름이 미리 정해지지 않고, 중간 산출물을 보며 다음 행동을 모델이 판단해야 할 때 쓴다. 기존 에이전트에 컨텍스트를 유지한 채 이어서 지시할 때는 `SendMessage`(에이전트 ID/이름 지정)를, 접근법 확정 전·완료 선언 전 검증 게이트로는 `advisor`(파라미터 없이 전체 트랜스크립트를 보는 상위 리뷰어)를 활용한다.

## ⚙️ 설정 방법

### 글로벌 설정 (~/.claude/settings.json)
```json
{
  "permissions": {
    "allow": [
      "Bash(npm *)",
      "Bash(git *)",
      "Bash(docker *)"
    ]
  }
}
```

### 프로젝트 설정 (.claude/settings.json)
```json
{
  "hooks": {
    "SubagentStop": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo 'Agent completed: $AGENT_NAME'"
        }]
      }
    ]
  }
}
```

## 📊 실전 활용 예시

### 프로젝트 부트스트래핑
```bash
claude "Bootstrap a new Next.js 15 project with:
- TypeScript configuration
- Tailwind CSS setup
- ESLint + Prettier
- Vitest for testing
- Playwright for E2E
- GitHub Actions CI/CD
- Docker configuration
- CLAUDE.md with project context"
```

### 릴리스 파이프라인
```bash
claude "Execute release pipeline:
1. Run full test suite
2. Build production bundle
3. Generate changelog from commits
4. Create GitHub release
5. Deploy to staging
6. Run smoke tests
Report results at each step"
```

### 코드베이스 분석
```bash
claude "Analyze the entire codebase:
- Architecture overview (use Explore agent, very thorough)
- Security vulnerabilities (use security-reviewer)
- Performance hotspots (use code-reviewer)
- Test coverage gaps (use test-automation-specialist)
Compile findings into a comprehensive report"
```

## 🔗 참고 자료

- [Parallel Agents Safety Protocol v3.1.0](Parallel%20Agents%20Safety%20Protocol%20v3.1.0.md)
- [Agent Teams 공식 문서](https://code.claude.com/docs/ko/agent-teams)
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)

---

*CLI Orchestration은 복잡한 워크플로우를 자동화하는 강력한 도구입니다.*
*마지막 업데이트: 2026-07-15 | Claude Code v2.1.210 | Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5*

#orchestration #multi-agent #cli #automation