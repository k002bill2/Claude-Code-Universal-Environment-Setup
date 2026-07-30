<!-- 출처: docs/Claude code system setup/CLAUDE.md 템플릿.md -->
# CLAUDE.md

## Project Overview

**[프로젝트명]** - [한 줄 설명]

| Layer | Stack |
|-------|-------|
| Frontend | [React 19, TypeScript, Tailwind, Vite] |
| Backend | [FastAPI, PostgreSQL, Redis] |
| Deploy | [Docker, AWS] |

## Quick Start

```bash
# 설치
npm install

# 개발서버
npm run dev          # Frontend (localhost:3000)
cd backend && uvicorn app:app --reload  # Backend (localhost:8000)

# 인프라
docker compose up -d  # DB, Redis
```

## Testing

```bash
npm test                    # 전체 테스트
npm run test:coverage       # 커버리지
npx tsc --noEmit            # 타입체크
npm run lint                # 린트
```

## Environment Variables

```bash
DATABASE_URL=postgresql://...
REDIS_URL=redis://localhost:6379
API_KEY=...                  # [어디서 발급]
```

## Architectural Decisions

- [프로젝트 특유의 패턴이나 결정 — Claude가 코드만 봐서는 모르는 것]
- [예: "React Router 대신 커스텀 useNavigationStore로 라우팅"]
- [예: "Service Layer 패턴 — 비즈니스 로직은 services/에 분리"]

## Gotchas

- [Claude가 반복적으로 틀리는 것]
- [예: "Metro 재시작 필요 — .env 변경 후"]
- [예: "asyncpg prepared statement 캐시 충돌 주의"]
