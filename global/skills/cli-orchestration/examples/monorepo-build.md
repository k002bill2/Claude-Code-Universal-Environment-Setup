# Monorepo Build Example

모노레포 구조의 프로젝트를 효율적으로 빌드하는 예시입니다.

## 프로젝트 구조

```
my-monorepo/
├── package.json           # 루트 패키지 (workspaces 설정)
├── packages/
│   ├── shared/            # 공유 라이브러리 (의존성 없음)
│   │   ├── package.json
│   │   └── src/
│   ├── ui-components/     # UI 컴포넌트 (shared 의존)
│   │   ├── package.json
│   │   └── src/
│   ├── frontend/          # 프론트엔드 앱 (shared, ui-components 의존)
│   │   ├── package.json
│   │   └── src/
│   └── backend/           # 백엔드 서버 (shared 의존)
│       ├── package.json
│       └── src/
└── apps/
    └── mobile/            # 모바일 앱 (shared 의존)
        ├── package.json
        └── src/
```

## 의존성 그래프

```
                shared
               /   |   \
              /    |    \
    ui-components  |   backend
            \      |      |
             \     |      |
           frontend     mobile
```

## 빌드 설정

### 1. 프로젝트 레지스트리

```yaml
multi_project:
  name: "monorepo-build"
  description: "모노레포 전체 빌드"

  projects:
    - name: "shared"
      path: "./packages/shared"
      dependencies: []
      commands:
        build: "npm run build"
        test: "npm test"

    - name: "ui-components"
      path: "./packages/ui-components"
      dependencies: ["shared"]
      commands:
        build: "npm run build"
        test: "npm test"

    - name: "frontend"
      path: "./packages/frontend"
      dependencies: ["shared", "ui-components"]
      commands:
        build: "npm run build"
        test: "npm test"

    - name: "backend"
      path: "./packages/backend"
      dependencies: ["shared"]
      commands:
        build: "npm run build"
        test: "npm test"

    - name: "mobile"
      path: "./apps/mobile"
      dependencies: ["shared"]
      commands:
        build: "npm run build"
        test: "npm test"
```

### 2. 빌드 실행 전략

```yaml
execution:
  pattern: "dependency"
  max_concurrent: 3
  fail_fast: true

  # 의존성 기반 실행 순서
  # Phase 1: shared (의존성 없음)
  # Phase 2: ui-components, backend, mobile (shared 의존)
  # Phase 3: frontend (ui-components 의존)
```

## 실행 예시

### 전체 빌드

**요청:**
```
"모노레포 전체 빌드해줘"
```

**실행 순서:**

```
Phase 1: 기반 패키지
─────────────────────
[1] shared 빌드 시작
    └─ npm run build
    └─ 완료 (5.2s)

Phase 2: 중간 패키지 (병렬)
─────────────────────
[2] ui-components 빌드 시작 ─┬─ 병렬 실행
[3] backend 빌드 시작       ─┤
[4] mobile 빌드 시작        ─┘
    └─ 모두 완료 (18.7s)

Phase 3: 최종 패키지
─────────────────────
[5] frontend 빌드 시작
    └─ npm run build
    └─ 완료 (25.3s)

총 소요시간: 49.2s
순차 실행 예상: 78.5s
병렬화 효율: 37% 단축
```

### 선택적 빌드

**요청:**
```
"frontend만 빌드해줘 (의존성 포함)"
```

**실행:**
```
의존성 분석: frontend → ui-components → shared

Phase 1: shared 빌드
Phase 2: ui-components 빌드
Phase 3: frontend 빌드
```

### 변경된 패키지만 빌드

**요청:**
```
"변경된 패키지만 빌드해줘"
```

**실행:**
```
1. git diff로 변경된 파일 감지
2. 영향받는 패키지 식별
3. 의존성 그래프 기반 빌드 순서 결정
4. 변경된 패키지 + 영향받는 패키지만 빌드
```

## Claude Code 실행 패턴

### 1. 의존성 분석

```markdown
모노레포 의존성 분석:

1. 모든 package.json 읽기
2. dependencies/peerDependencies 분석
3. 의존성 그래프 구축
4. 토폴로지컬 정렬로 빌드 순서 결정
```

### 2. 병렬 빌드 실행

```markdown
Phase 2 병렬 빌드 (ui-components, backend, mobile):

동시에 3개 Bash 명령 실행:
1. cd packages/ui-components && npm run build
2. cd packages/backend && npm run build
3. cd apps/mobile && npm run build

TaskOutput으로 결과 수집
```

### 3. 결과 리포트

```markdown
## 모노레포 빌드 결과

**프로젝트**: my-monorepo
**패턴**: dependency (의존성 기반)

### 빌드 순서 및 결과

| Phase | 패키지 | 상태 | 소요시간 | 비고 |
|-------|--------|------|----------|------|
| 1 | shared | ✅ | 5.2s | 의존성 없음 |
| 2 | ui-components | ✅ | 12.3s | shared 이후 |
| 2 | backend | ✅ | 8.7s | shared 이후 |
| 2 | mobile | ✅ | 18.7s | shared 이후 |
| 3 | frontend | ✅ | 25.3s | ui-components 이후 |

### 성능 분석

- **총 소요시간**: 49.2초
- **순차 실행 예상**: 70.2초
- **병렬화 효율**: 30% 시간 단축
- **병목 지점**: mobile (Phase 2에서 가장 오래 걸림)

### 아티팩트
- `packages/shared/dist/` - 1.2MB
- `packages/ui-components/dist/` - 3.4MB
- `packages/frontend/dist/` - 15.7MB
- `packages/backend/dist/` - 8.2MB
- `apps/mobile/dist/` - 22.1MB
```

## 최적화 팁

### 1. 캐시 활용

```yaml
caching:
  enabled: true
  strategy: "content-hash"

  cache_dirs:
    - "node_modules/.cache"
    - ".tsbuildinfo"
    - "dist/.cache"
```

### 2. 증분 빌드

```yaml
incremental_build:
  enabled: true
  check_method: "file_hash"

  skip_if_unchanged:
    - "src/**/*"
    - "package.json"
    - "tsconfig.json"
```

### 3. 워커 스레드

```yaml
parallel_compilation:
  typescript:
    workers: 4
  webpack:
    parallel: true
    workers: 4
```

## 문제 해결

### 순환 의존성 감지

```markdown
순환 의존성 발견 시:

1. 의존성 그래프에서 사이클 감지
2. 관련 패키지 목록 출력
3. 해결 방안 제시:
   - 공통 모듈 분리
   - 의존성 방향 재설계
   - 인터페이스 추출
```

### 빌드 실패 복구

```markdown
특정 패키지 빌드 실패 시:

1. 실패한 패키지 로그 분석
2. 의존하는 패키지들 빌드 스킵 처리
3. 복구 옵션 제시:
   - 실패한 패키지만 재빌드
   - 의존성 체인 전체 재빌드
   - 스킵하고 계속
```
