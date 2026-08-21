# 스마트 의존성 분석 예제

프로젝트 의존성을 자동 분석하고 최적의 빌드 순서를 결정하는 예제입니다.

## 예제 1: 모노레포 의존성 분석

### 요청

```
"모노레포 의존성 분석해줘"
```

### 프로젝트 구조

```
my-monorepo/
├── package.json
├── packages/
│   ├── shared-utils/
│   │   └── package.json
│   ├── core-lib/
│   │   └── package.json  (depends: shared-utils)
│   ├── api/
│   │   └── package.json  (depends: core-lib)
│   ├── frontend-common/
│   │   └── package.json  (depends: core-lib)
│   └── web-app/
│       └── package.json  (depends: frontend-common, api)
```

### 분석 결과

```
╔══════════════════════════════════════════════════════════════╗
║            Dependency Analysis Report                         ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Project: my-monorepo                                         ║
║  Packages: 5 (internal)                                       ║
║  External Dependencies: 47                                    ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Dependency Graph                                             ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  Level 0 ─────────────────────────────────────────────────── ║
║    ┌──────────────────┐                                       ║
║    │  shared-utils    │  (no dependencies)                    ║
║    └────────┬─────────┘                                       ║
║             │                                                 ║
║  Level 1 ───┼────────────────────────────────────────────────║
║             ▼                                                 ║
║    ┌──────────────────┐                                       ║
║    │    core-lib      │                                       ║
║    └────────┬─────────┘                                       ║
║             │                                                 ║
║  Level 2 ───┼────────────────────────────────────────────────║
║        ┌────┴────┐                                            ║
║        ▼         ▼                                            ║
║  ┌──────────┐ ┌─────────────────┐                             ║
║  │   api    │ │ frontend-common │                             ║
║  └────┬─────┘ └────────┬────────┘                             ║
║       │                │                                      ║
║  Level 3──────────────────────────────────────────────────── ║
║       └────────┬───────┘                                      ║
║                ▼                                              ║
║        ┌─────────────┐                                        ║
║        │   web-app   │                                        ║
║        └─────────────┘                                        ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Recommended Build Order                                      ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  Step 1: [PARALLEL] shared-utils                              ║
║  Step 2: [SEQUENTIAL] core-lib (depends: shared-utils)        ║
║  Step 3: [PARALLEL] api, frontend-common (depends: core-lib)  ║
║  Step 4: [SEQUENTIAL] web-app (depends: api, frontend-common) ║
║                                                               ║
║  Parallelization Potential: 40%                               ║
║  Estimated Time Savings: ~35% vs sequential                   ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 2: 변경 영향 분석

### 요청

```
"core-lib를 수정했는데 영향받는 패키지 알려줘"
```

### 분석 결과

```
╔══════════════════════════════════════════════════════════════╗
║            Impact Analysis: core-lib                          ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Changed Package: core-lib                                    ║
║                                                               ║
║  Impact Chain                                                 ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  core-lib (CHANGED)                                           ║
║     │                                                         ║
║     ├──► api (AFFECTED - direct)                              ║
║     │      │                                                  ║
║     │      └──► web-app (AFFECTED - indirect)                 ║
║     │                                                         ║
║     └──► frontend-common (AFFECTED - direct)                  ║
║            │                                                  ║
║            └──► web-app (AFFECTED - indirect)                 ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Affected Packages Summary                                    ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  Direct (2):                                                  ║
║    • api                                                      ║
║    • frontend-common                                          ║
║                                                               ║
║  Indirect (1):                                                ║
║    • web-app                                                  ║
║                                                               ║
║  NOT Affected (1):                                            ║
║    • shared-utils                                             ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Recommended Actions                                          ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  1. Rebuild: core-lib → api → frontend-common → web-app       ║
║  2. Test: Run tests for all affected packages                 ║
║  3. Skip: shared-utils (not affected)                         ║
║                                                               ║
║  Optimized Build Command:                                     ║
║  > npm run build --filter=core-lib...                         ║
║    (builds core-lib and all dependents)                       ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 3: Python + Node 혼합 프로젝트

### 요청

```
"전체 프로젝트 의존성 분석해줘"
```

### 프로젝트 구조

```
hybrid-project/
├── frontend/
│   └── package.json
├── backend/
│   └── pyproject.toml
├── shared/
│   └── package.json
└── ml-service/
    └── pyproject.toml  (depends: backend via API)
```

### 분석 결과

```
╔══════════════════════════════════════════════════════════════╗
║        Multi-Language Dependency Analysis                     ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Languages Detected:                                          ║
║  • JavaScript/TypeScript (npm): frontend, shared              ║
║  • Python (poetry/uv): backend, ml-service                    ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  JavaScript Dependencies                                      ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  shared ─────────────► frontend                               ║
║                                                               ║
║  Build Order: shared → frontend                               ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Python Dependencies                                          ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  backend (API server)                                         ║
║     │                                                         ║
║     └──► ml-service (runtime dependency via API)              ║
║                                                               ║
║  Build Order: backend → ml-service                            ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Cross-Language Integration                                   ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  frontend ─── API calls ───► backend                          ║
║                                                               ║
║  Note: No build-time dependency, only runtime                 ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Recommended Full Build Order                                 ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  Phase 1: [PARALLEL]                                          ║
║    • npm: shared                                              ║
║    • python: backend                                          ║
║                                                               ║
║  Phase 2: [PARALLEL]                                          ║
║    • npm: frontend                                            ║
║    • python: ml-service                                       ║
║                                                               ║
║  Total Parallelization: 50%                                   ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 4: 순환 의존성 감지

### 상황

실수로 순환 의존성이 생긴 경우

### 분석 결과

```
╔══════════════════════════════════════════════════════════════╗
║  ⚠️  CIRCULAR DEPENDENCY DETECTED                             ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Cycle Found:                                                 ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║       ┌─────────────────────────────┐                         ║
║       │                             │                         ║
║       ▼                             │                         ║
║    ┌──────┐      ┌──────┐      ┌────┴───┐                     ║
║    │  A   │ ───► │  B   │ ───► │   C    │                     ║
║    └──────┘      └──────┘      └────────┘                     ║
║       ▲                             │                         ║
║       │                             │                         ║
║       └─────────────────────────────┘                         ║
║                                                               ║
║  Cycle: A → B → C → A                                         ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Details                                                      ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  A (packages/service-a/package.json)                          ║
║    depends on: B                                              ║
║                                                               ║
║  B (packages/service-b/package.json)                          ║
║    depends on: C                                              ║
║                                                               ║
║  C (packages/service-c/package.json)                          ║
║    depends on: A  ← 이 의존성이 순환 원인                      ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Suggested Resolutions                                        ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  Option 1: 의존성 역전                                         ║
║    C가 A에 의존하는 대신, 공통 인터페이스 분리                   ║
║    → packages/shared-interface 생성                           ║
║                                                               ║
║  Option 2: Lazy Loading                                       ║
║    C에서 A를 동적 import로 변경                                ║
║    → require('A')를 런타임에 호출                              ║
║                                                               ║
║  Option 3: 병합                                                ║
║    A와 C가 밀접하게 연관되어 있다면 하나로 병합                  ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 의존성 분석 설정

### 설정 파일 예시

```yaml
# ~/.claude/cli-orchestration/dependency-config.yaml
dependency_analysis:
  # 분석 대상
  include:
    - "package.json"
    - "pyproject.toml"
    - "Cargo.toml"

  # 제외 경로
  exclude:
    - "node_modules"
    - ".venv"
    - "dist"
    - "build"

  # 출력 형식
  output:
    format: "tree"  # tree, matrix, json
    show_external: false
    show_versions: true

  # 경고 설정
  warnings:
    circular_deps: true
    version_conflicts: true
    outdated_deps: false
```
