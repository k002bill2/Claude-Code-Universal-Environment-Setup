---
tags:
  - claude
  - setup
---

# Dev Docs 시스템 구축 가이드
#claude-code #dev-docs #context-management

> 최종 업데이트: 2026-07-15
> Claude Code: v2.1.210 | Opus 4.8 / Fable 5 / Sonnet 5 (1M 컨텍스트) / Haiku 4.5

> 💡 **Claude = 극도로 자신감 넘치는 주니어 개발자 with 심각한 건망증**
>
> 이 시스템으로 Claude가 길을 잃지 않게 관리!

## 🎯 왜 필요한가?

### 1M 컨텍스트 시대에도 Dev Docs가 필요한 이유

**"1M 컨텍스트면 충분하지 않나요?"**

아닙니다. 컨텍스트 크기가 커져도:
- **Auto-compaction**은 여전히 발생 (긴 세션에서 불가피)
- **새 세션**에서는 이전 맥락이 완전히 사라짐
- **큰 컨텍스트 ≠ 좋은 방향성** (정보가 많을수록 핵심을 놓칠 수 있음)
- **메모리 시스템은 세션 간 영속 정보용**, Dev Docs는 **대규모 작업의 상세 계획/진행용**

### Dev Docs vs 네이티브 Memory 역할 구분

> ※ 2026-06-16 갱신: 영속/선호/프로젝트 사실은 **네이티브 Memory 시스템**으로 위임하고,
> Dev Docs는 **단일 대규모 작업의 상세 plan/context/tasks 체크리스트**로 역할을 축소한다.
>
> 네이티브 Memory는 `~/.claude/projects/*/memory/` 에 파일 단위로 영속된다 —
> `MEMORY.md`(인덱스) + 개별 `.md` 파일, 각 항목은 **type: user / feedback / project / reference**.

| 용도 | Dev Docs | 네이티브 Memory |
|------|----------|-------------|
| **범위** | 단일 대규모 작업 한정 | 프로젝트/사용자 전반 (영속/선호/사실) |
| **수명** | 작업 완료 시 아카이빙 | 영구 (갱신 가능) |
| **상세도** | 상세 plan/context/tasks 체크리스트 | 핵심 결정사항, 선호도, 사실 |
| **관리** | 수동 (명령어/Hook) | 자동 + 수동 |
| **위치** | dev/active/ | ~/.claude/projects/*/memory/ (MEMORY.md 인덱스 + 개별 .md) |

> **Plan 모드 / TodoWrite 와의 관계**: Plan 모드로 접근법을 먼저 확정하고,
> TodoWrite는 **세션 내 단기 체크리스트**(현재 작업 진행 추적)로 쓴다.
> Dev Docs는 그보다 한 단계 위 — **세션을 넘어 이어지는 대규모 작업의 상세 기록**이다.

### 문제점 (여전히 유효)
- Claude가 30분 후 원래 계획 잊어버림
- 갑자기 엉뚱한 방향으로 개발 시작
- Auto-compaction 후 컨텍스트 상실
- "관련 없는 TypeScript 에러들이니 괜찮아요!" 😱

### 해결책: 3-파일 시스템
모든 대규모 작업을 3개 문서로 관리

## 📁 Dev Docs 구조

```
project/
└── dev/
    └── active/
        └── [task-name]/
            ├── [task-name]-plan.md     # 승인된 계획
            ├── [task-name]-context.md  # 핵심 결정사항
            └── [task-name]-tasks.md    # 체크리스트
```

## 📝 각 문서의 역할

### 1. Plan 문서 (계획)
```markdown
# User Dashboard Feature Plan

## Executive Summary
Adding comprehensive user dashboard with order history, favorites,
settings, and activity feed.

## Phase 1: Backend API (Week 1)
### Tasks
- [ ] Create dashboard controller
- [ ] Add order history endpoint
- [ ] Implement favorites system
- [ ] Add activity tracking

### Technical Decisions
- Use Redis for activity caching
- Paginate order history (20 items/page)
- Soft delete for favorites

## Phase 2: Frontend Components (Week 2)
### Tasks
- [ ] Dashboard layout component
- [ ] Order history table
- [ ] Favorites grid
- [ ] Settings form

## Success Metrics
- Page load < 2 seconds
- All endpoints < 200ms response
- 100% test coverage
```

### 2. Context 문서 (상황 기록)
```markdown
# User Dashboard - Context

## Last Updated: 2026-03-18 14:30

## Key Files
- `backend/src/controllers/DashboardController.ts`
- `frontend/src/pages/Dashboard.tsx`
- `shared/types/dashboard.types.ts`

## Important Decisions
- **2026-03-18**: Decided to use Redis for caching
- **2026-03-18**: Favorites limited to 100 items per user
- **2026-03-18**: Using tanstack-table for order history

## Current Issues
- [ ] Performance issue with large order histories
- [x] ~~CORS error on favorites endpoint~~ (Fixed)

## Dependencies
- Redis client upgraded to v4.5
- Added tanstack-table v8.10
- New environment variable: REDIS_CACHE_TTL

## Next Steps
1. Optimize database query for order history
2. Add loading skeletons for better UX
3. Implement real-time activity updates
```

### 3. Tasks 문서 (체크리스트)
```markdown
# User Dashboard - Tasks

## Backend (8/12 complete)
- [x] Create dashboard controller
- [x] Setup Redis connection
- [x] Order history endpoint
- [x] Pagination implementation
- [x] Favorites CRUD operations
- [x] Activity tracking service
- [x] Add authentication middleware
- [x] Write unit tests
- [ ] Performance optimization
- [ ] Rate limiting
- [ ] Caching layer
- [ ] Integration tests

## Frontend (3/10 complete)
- [x] Dashboard layout
- [x] Routing setup
- [x] API client setup
- [ ] Order history component
- [ ] Favorites grid
- [ ] Activity feed
- [ ] Settings panel
- [ ] Loading states
- [ ] Error boundaries
- [ ] E2E tests

## Documentation (0/3 complete)
- [ ] API documentation
- [ ] User guide
- [ ] Deployment notes
```

## 🚀 워크플로우

### Step 1: Planning Mode 시작
```bash
# Claude에게 계획 요청
"I need to implement a user dashboard. Put this into planning mode
and create a comprehensive plan."

# 또는 Plan 에이전트 사용
"Use the Plan agent to design the implementation for user dashboard feature"
```

### Step 2: 계획 검토 및 승인
```bash
# 계획 검토
"This looks good, but let's add real-time notifications"

# 승인 후 Dev Docs 생성
/dev-docs  # Custom command
# 또는
"Create dev docs for this approved plan"
```

### Step 3: 구현 시작
```bash
# Context 부족 시 /compact 활용
/compact

"Let's start implementing Phase 1 of the dashboard feature.
Check the dev docs first."

# Claude가 자동으로 3개 파일 모두 읽고 시작
```

### Step 4: 주기적 업데이트
```bash
# 작업 완료시마다
"Update the tasks file - mark the controller creation as complete"

# Context 부족할 때
/update-dev-docs  # Custom command
# 또는
"Update all dev docs with current progress and next steps"
```

### Step 5: 세션 재시작
```bash
# 새 세션에서 - 메모리가 자동으로 이전 작업 힌트 제공
"Continue working on the dashboard feature"

# Claude가 자동으로 dev docs 읽고 이어서 작업
```

## 🧠 메모리 시스템과의 연계 (신규)

### Dev Docs + Memory 병행 전략

```
Dev Docs (상세, 작업별)          네이티브 Memory (핵심, 영구)
─────────────────────         ──────────────────────────
plan.md: 전체 구현 계획        → project memory:   "Dashboard 기능 구현 중"
context.md: 기술 결정사항      → feedback memory:  "Redis 캐싱 선호"
tasks.md: 상세 체크리스트      → reference memory: "대시보드 API 문서 위치"
                              → user memory:      "사용자 선호 톤/규칙"
```

(네 가지 type: **user / feedback / project / reference** — `~/.claude/projects/*/memory/` 에
`MEMORY.md` 인덱스 + 개별 `.md` 파일로 영속.)

### 메모리로 기록할 것 (세션 간 영속)
- 아키텍처 결정의 이유
- 사용자 선호 패턴
- 외부 자원 위치
- 반복되는 피드백

### Dev Docs로 기록할 것 (작업 한정)
- 상세 구현 계획
- 파일별 변경 내역
- 진행률 체크리스트
- 이슈 트래킹

## 🛠️ Custom Commands 설정

### /dev-docs Command
```markdown
# .claude/commands/dev-docs.md
---
description: Create comprehensive dev docs for approved plan
---

Based on the approved plan, create three development documents:

1. Create `dev/active/[task-name]/[task-name]-plan.md`
   - Copy the full approved plan
   - Add timeline and phases
   - Include success metrics

2. Create `dev/active/[task-name]/[task-name]-context.md`
   - List all relevant files
   - Document key architectural decisions
   - Note any constraints or dependencies
   - Add "Next Steps" section

3. Create `dev/active/[task-name]/[task-name]-tasks.md`
   - Convert plan into detailed checklist
   - Group by component/service
   - Use checkbox format
   - Add estimates if possible

Remember to timestamp everything!
```

### /update-dev-docs Command
```markdown
# .claude/commands/update-dev-docs.md
---
description: Update dev docs before context compaction
---

Update all active dev docs:

1. In context.md:
   - Update "Last Updated" timestamp
   - Add any new decisions made
   - Update "Current Issues" section
   - Revise "Next Steps" based on progress

2. In tasks.md:
   - Mark completed items with [x]
   - Add any new tasks discovered
   - Update completion counts
   - Reorder by priority if needed

3. Add a session summary:
   - What was accomplished
   - Any blockers encountered
   - Critical next actions

Keep updates concise but comprehensive!
```

## ⚙️ PreCompact Hook 활용 (신규)

컨텍스트 압축 *직전*에 Dev Docs 저장을 알리는 Hook:

```json
// .claude/settings.json의 hooks 섹션 (v2.1.210 스키마)
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [{
          "type": "command",
          "command": "echo '⚠️ Context compaction imminent - save progress to dev docs!'"
        }]
      }
    ]
  }
}
```

**참고**: 압축 관련 리마인더는 압축 *직전*에 발화하는 `PreCompact` 이벤트에서 처리합니다.

## 📊 실제 효과 측정

### Before Dev Docs
- 계획 준수율: 40%
- Context 후 작업 재개 성공률: 20%
- 평균 탈선 시간: 45분마다

### After Dev Docs + Memory
- 계획 준수율: 95%
- Context 후 작업 재개 성공률: **95%** (메모리 연계)
- 평균 탈선 시간: 거의 없음

## 💡 Pro Tips

### 1. 작업 크기 제한
```bash
# 너무 큰 작업 X
"Implement the entire application"

# 적절한 크기 ✓
"Implement user dashboard with 4 main components"
```

### 2. 섹션별 구현
```bash
# 한번에 전체 구현 X
"Implement everything in the plan"

# 섹션별로 구현 ✓
"Let's implement Phase 1, tasks 1-3 only"
```

### 3. 정기적 리뷰
```bash
# 매 5-6개 작업마다
"Review the changes we just made using code-reviewer agent"
```

### 4. Context 관리
```bash
# Context 부족 시
/compact

# 또는 수동 저장
"Save progress to dev docs and prepare for compaction"

# Compaction 후
"Continue from dev docs"
```

## 🗂️ 완료된 작업 아카이빙

```bash
# 작업 완료 후
mv dev/active/user-dashboard dev/completed/2026-03/

# 나중에 참조 가능
ls dev/completed/
```

## 🔥 핵심 교훈

1. **계획 없이 시작 = 실패**
2. **Dev Docs = Claude의 상세 기억, Memory = 영구 기억**
3. **작은 단위로 구현 = 품질 보장**
4. **정기적 업데이트 = 연속성 유지**
5. **1M 컨텍스트에서도 Dev Docs는 유효** (구조화된 방향성)

---

*"Documentation is Claude's memory, and memory is everything"*

#dev-docs #context-management #planning #memory