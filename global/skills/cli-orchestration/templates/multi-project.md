# Multi-Project Template

여러 프로젝트/디렉토리에 걸친 CLI 작업을 동시에 관리하기 위한 템플릿입니다.

## 기본 구조

```yaml
multi_project:
  name: "멀티 프로젝트 작업명"
  description: "작업 설명"

  # 프로젝트 레지스트리
  projects:
    - name: "frontend"
      path: "./packages/frontend"
      type: "npm"

    - name: "backend"
      path: "./packages/backend"
      type: "npm"

    - name: "shared"
      path: "./packages/shared"
      type: "npm"

  # 실행 설정
  execution:
    pattern: "parallel"        # parallel | sequential | dependency
    max_concurrent: 3
    fail_fast: false
```

## 프로젝트 레지스트리

### 상세 프로젝트 정의

```yaml
projects:
  - name: "frontend"
    path: "./packages/frontend"
    type: "npm"
    commands:
      dev: "npm run dev"
      build: "npm run build"
      test: "npm test"
      lint: "npm run lint"
    env:
      PORT: 3000
      NODE_ENV: "development"
    dependencies: ["shared"]   # 빌드 의존성

  - name: "backend"
    path: "./packages/backend"
    type: "npm"
    commands:
      dev: "npm run dev"
      build: "npm run build"
      test: "npm test"
    env:
      PORT: 8080
    dependencies: ["shared"]

  - name: "shared"
    path: "./packages/shared"
    type: "npm"
    commands:
      build: "npm run build"
    dependencies: []           # 의존성 없음 (먼저 빌드)
```

## 실행 패턴

### 1. parallel (병렬)

모든 프로젝트에서 동시 실행:

```yaml
execution:
  pattern: "parallel"
  command: "build"
  max_concurrent: 3
```

**실행:**
```
frontend/build  ─┬─→ 완료
backend/build   ─┼─→ 완료
shared/build    ─┴─→ 완료
```

### 2. sequential (순차)

프로젝트 순서대로 실행:

```yaml
execution:
  pattern: "sequential"
  command: "build"
  order: ["shared", "frontend", "backend"]
```

**실행:**
```
shared/build → frontend/build → backend/build
```

### 3. dependency (의존성 기반)

의존성 그래프에 따라 실행:

```yaml
execution:
  pattern: "dependency"
  command: "build"
```

**실행:**
```
shared/build → (frontend/build + backend/build)
```

## 실행 예시

### 1. 모든 프로젝트 빌드

```yaml
multi_project:
  name: "build-all"

  projects:
    - name: "frontend"
      path: "./packages/frontend"
    - name: "backend"
      path: "./packages/backend"
    - name: "shared"
      path: "./packages/shared"

  execution:
    pattern: "dependency"
    command: "npm run build"
```

### 2. 개발 서버 동시 시작

```yaml
multi_project:
  name: "dev-servers"

  projects:
    - name: "frontend"
      path: "./packages/frontend"
      command: "npm run dev"
      env:
        PORT: 3000

    - name: "backend"
      path: "./packages/backend"
      command: "npm run dev"
      env:
        PORT: 8080

  execution:
    pattern: "parallel"
    keep_alive: true           # 서버 계속 실행
```

### 3. 선택적 프로젝트 실행

```yaml
multi_project:
  name: "selective-test"

  filter:
    include: ["frontend", "backend"]
    exclude: ["deprecated-*"]

  execution:
    pattern: "parallel"
    command: "npm test"
```

## 프로젝트 탐지

### 자동 탐지

```yaml
discovery:
  root: "./packages"
  pattern: "*/package.json"    # package.json이 있는 디렉토리
  exclude:
    - "node_modules"
    - ".git"
```

### 모노레포 구조 분석

```yaml
monorepo:
  type: "npm-workspaces"       # npm-workspaces | yarn-workspaces | pnpm
  root_config: "./package.json"
  auto_detect_dependencies: true
```

## Claude Code 구현 패턴

### 프로젝트 탐지

```markdown
모노레포 프로젝트 탐지:

1. Glob("**/package.json")으로 모든 package.json 찾기
2. 각 package.json의 dependencies 분석
3. 의존성 그래프 구축
4. 빌드 순서 결정
```

### 병렬 실행

```markdown
3개 프로젝트 병렬 빌드:

1. cd packages/frontend && npm run build (백그라운드)
2. cd packages/backend && npm run build (백그라운드)
3. cd packages/shared && npm run build (백그라운드)

TaskOutput으로 모든 결과 수집
```

### 포트 관리

```markdown
개발 서버 포트 관리:

1. 사용 중인 포트 확인: lsof -i :3000
2. 충돌 시 자동 포트 할당
3. 각 서버의 URL 리포트
```

### 결과 리포트

```markdown
## 멀티 프로젝트 실행 결과

**작업**: build-all
**패턴**: dependency

### 프로젝트별 결과

| 프로젝트 | 상태 | 소요시간 | 비고 |
|----------|------|----------|------|
| shared | ✅ 성공 | 5.2s | - |
| frontend | ✅ 성공 | 18.3s | shared 이후 실행 |
| backend | ✅ 성공 | 12.7s | shared 이후 실행 |

**총 소요시간**: 23.5s (순차: 36.2s 예상)
**병렬화 효율**: 35% 시간 단축
```

## 에러 처리

### 부분 실패 처리

```yaml
error_handling:
  fail_fast: false             # 하나 실패해도 계속
  collect_errors: true         # 모든 에러 수집
  retry_failed: true           # 실패한 것만 재시도
```

### 에러 리포트

```markdown
## 부분 실패 리포트

**성공**: 2/3 프로젝트

### 실패한 프로젝트

| 프로젝트 | 에러 | 로그 |
|----------|------|------|
| backend | Exit code 1 | `TypeError: Cannot read...` |

### 권장 조치
1. backend 로그 확인: `cat packages/backend/npm-debug.log`
2. 의존성 확인: `cd packages/backend && npm install`
3. 재시도: `npm run build -w packages/backend`
```
