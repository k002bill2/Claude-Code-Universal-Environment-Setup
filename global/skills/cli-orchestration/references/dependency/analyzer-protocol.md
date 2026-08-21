# Dependency Analyzer Protocol

프로젝트 의존성을 자동으로 분석하고 최적의 빌드 순서를 결정하는 프로토콜입니다.

## 분석 범위

### 지원 패키지 매니저

| 매니저 | 파일 | 언어 |
|--------|------|------|
| npm/pnpm/yarn | package.json | JavaScript/TypeScript |
| pip/poetry/uv | pyproject.toml, requirements.txt | Python |
| cargo | Cargo.toml | Rust |
| go mod | go.mod | Go |
| maven/gradle | pom.xml, build.gradle | Java |

### 분석 대상

```yaml
analysis_targets:
  # 패키지 의존성
  package_dependencies:
    - production
    - development
    - peer

  # 워크스페이스 의존성
  workspace_dependencies:
    - internal_packages
    - shared_libraries

  # 빌드 의존성
  build_dependencies:
    - build_tools
    - transpilers
    - bundlers
```

## 의존성 그래프 생성

### 노드 타입

```yaml
node_types:
  ROOT:
    description: "프로젝트 루트"
    color: "blue"

  PACKAGE:
    description: "워크스페이스 패키지"
    color: "green"

  EXTERNAL:
    description: "외부 의존성"
    color: "gray"

  CIRCULAR:
    description: "순환 의존성 (경고)"
    color: "red"
```

### 엣지 타입

```yaml
edge_types:
  DEPENDS_ON:
    description: "A가 B에 의존"
    style: "solid"

  DEV_DEPENDS:
    description: "개발 의존성"
    style: "dashed"

  PEER_DEPENDS:
    description: "피어 의존성"
    style: "dotted"

  BUILDS_BEFORE:
    description: "빌드 순서 제약"
    style: "bold"
```

## 분석 알고리즘

### 1. 파일 수집

```yaml
file_collection:
  strategy: "recursive_glob"

  patterns:
    - "package.json"
    - "**/package.json"
    - "pyproject.toml"
    - "**/pyproject.toml"

  exclude:
    - "node_modules"
    - ".venv"
    - "dist"
    - "build"
```

### 2. 의존성 파싱

```yaml
parsing:
  # 각 파일 타입별 파서 적용
  parsers:
    - file: "package.json"
      parser: "npm_parser"
    - file: "pyproject.toml"
      parser: "poetry_parser"

  # 버전 해석
  version_resolution:
    strategy: "semver"
    allow_ranges: true
```

### 3. 그래프 구성

```yaml
graph_construction:
  algorithm: "directed_acyclic_graph"

  # 순환 감지
  cycle_detection:
    enabled: true
    action: "warn_and_break"

  # 고립 노드 처리
  orphan_handling:
    action: "include_as_independent"
```

### 4. 위상 정렬

```yaml
topological_sort:
  algorithm: "kahn"  # 또는 "dfs"

  # 우선순위 규칙
  priority_rules:
    - "shared_libraries_first"
    - "fewer_dependents_first"
    - "alphabetical_tiebreak"
```

## 빌드 순서 결정

### 레벨 기반 병렬화

```
Level 0: [shared-utils, config]      # 의존성 없음 - 병렬 가능
         ↓
Level 1: [core-lib]                  # Level 0에 의존
         ↓
Level 2: [api, frontend-common]      # Level 1에 의존 - 병렬 가능
         ↓
Level 3: [web-app, mobile-app]       # Level 2에 의존 - 병렬 가능
```

### 최적화 전략

```yaml
optimization:
  # 크리티컬 패스 최적화
  critical_path:
    enabled: true
    strategy: "prioritize_longest_chain"

  # 리소스 기반 스케줄링
  resource_aware:
    enabled: true
    max_concurrent: 4
    memory_limit: "4GB"

  # 캐시 활용
  cache_optimization:
    enabled: true
    strategy: "build_changed_only"
```

## 출력 형식

### 텍스트 리포트

```
=== Dependency Analysis Report ===

Project: my-monorepo
Packages: 8
External Dependencies: 127

Build Order:
  1. [parallel] shared-utils, config
  2. [sequential] core-lib
  3. [parallel] api, frontend-common
  4. [parallel] web-app, mobile-app, docs

Warnings:
  - Circular dependency detected: api <-> core-lib (dev)
  - Outdated dependency: lodash@4.17.15 (latest: 4.17.21)
```

### JSON 형식

```json
{
  "project": "my-monorepo",
  "analysis_time": "2024-01-30T14:32:15Z",
  "packages": [
    {
      "name": "shared-utils",
      "path": "packages/shared-utils",
      "dependencies": [],
      "build_level": 0
    }
  ],
  "build_order": [
    { "level": 0, "packages": ["shared-utils", "config"], "parallel": true },
    { "level": 1, "packages": ["core-lib"], "parallel": false }
  ],
  "warnings": [],
  "metrics": {
    "max_depth": 4,
    "avg_dependencies": 3.2,
    "parallelization_potential": 0.75
  }
}
```

## 변경 감지

### 영향 범위 분석

```yaml
change_detection:
  # 변경된 파일 기반
  file_changes:
    - "packages/core-lib/src/index.ts"

  # 영향받는 패키지 계산
  impact_analysis:
    direct: ["core-lib"]
    indirect: ["api", "frontend-common", "web-app", "mobile-app"]

  # 빌드 범위 결정
  build_scope:
    strategy: "affected_only"  # 또는 "full_rebuild"
```

### 인크리멘탈 빌드

```yaml
incremental:
  enabled: true

  # 해시 기반 변경 감지
  hash_strategy:
    files: ["src/**/*", "package.json"]
    algorithm: "xxhash"

  # 캐시 위치
  cache:
    directory: ".cache/builds"
    max_age: "7d"
```

## 문제 진단

### 순환 의존성

```yaml
circular_dependency:
  detection: true

  resolution_suggestions:
    - "의존성 역전 원칙 적용"
    - "공통 인터페이스 분리"
    - "lazy loading 활용"

  visualization:
    enabled: true
    highlight_cycles: true
```

### 버전 충돌

```yaml
version_conflict:
  detection: true

  resolution_strategies:
    - "use_highest_version"
    - "use_peer_version"
    - "manual_resolution"

  report_format: |
    Conflict: lodash
      - api requires ^4.17.20
      - core-lib requires ^4.17.15
      Suggested: Use 4.17.21
```
