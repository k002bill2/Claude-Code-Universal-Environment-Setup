# Complex DAG Example

복잡한 의존성 그래프를 가진 CI/CD 파이프라인 예시입니다.

## 시나리오

풀스택 모노레포 프로젝트의 CI/CD 파이프라인:
- 공유 라이브러리
- 프론트엔드 (React)
- 백엔드 (Node.js)
- E2E 테스트
- 스테이징/프로덕션 배포

## DAG 구조

```
                    install
                       │
            ┌──────────┼──────────┐
            ↓          ↓          ↓
      build-shared   lint      security-scan
            │          │
      ┌─────┴─────┐    │
      ↓           ↓    │
build-frontend  build-backend
      │           │    │
      ├───────────┼────┘
      ↓           ↓
test-frontend  test-backend
      │           │
      └─────┬─────┘
            ↓
        test-e2e
            │
     ┌──────┴──────┐
     ↓             ↓
deploy-staging   (on failure)
     │           notify-failure
     ↓
 smoke-test
     │
     ↓
deploy-production
     │
     ↓
  cleanup
```

## 완전한 DAG 정의

```yaml
dag:
  name: "fullstack-monorepo-pipeline"
  description: "풀스택 모노레포 CI/CD 파이프라인"

  defaults:
    timeout: 300000
    on_failure: abort
    retry:
      max: 2
      delay: 5000

  nodes:
    # ============================================
    # Phase 1: 초기화
    # ============================================
    - id: install
      command: "npm ci"
      timeout: 180000

    # ============================================
    # Phase 2: 병렬 검사 및 빌드
    # ============================================
    - id: lint
      command: "npm run lint"
      depends_on: [install]
      on_failure: continue  # 린트 실패해도 계속

    - id: security-scan
      command: "npm audit --audit-level=high"
      depends_on: [install]
      on_failure: continue

    - id: build-shared
      command: "npm run build --workspace=packages/shared"
      depends_on: [install]

    # ============================================
    # Phase 3: 프론트엔드/백엔드 빌드
    # ============================================
    - id: build-frontend
      command: "npm run build --workspace=packages/frontend"
      depends_on: [build-shared]
      env:
        NODE_ENV: production
        VITE_API_URL: "{{api_url}}"

    - id: build-backend
      command: "npm run build --workspace=packages/backend"
      depends_on: [build-shared]
      env:
        NODE_ENV: production

    # ============================================
    # Phase 4: 유닛 테스트
    # ============================================
    - id: test-frontend
      command: "npm run test --workspace=packages/frontend -- --coverage"
      depends_on: [build-frontend, lint]
      condition: "build-frontend.success"
      timeout: 600000

    - id: test-backend
      command: "npm run test --workspace=packages/backend -- --coverage"
      depends_on: [build-backend, lint]
      condition: "build-backend.success"
      timeout: 600000

    # ============================================
    # Phase 5: E2E 테스트
    # ============================================
    - id: test-e2e
      command: "npm run test:e2e"
      depends_on: [test-frontend, test-backend]
      condition: "test-frontend.success AND test-backend.success"
      timeout: 900000
      retry:
        max: 3
        delay: 10000

    # ============================================
    # Phase 6: 배포
    # ============================================
    - id: deploy-staging
      command: "npm run deploy:staging"
      depends_on: [test-e2e, security-scan]
      condition: |
        test-e2e.success AND
        (security-scan.success OR security-scan.exit_code == 0)
      env:
        DEPLOY_ENV: staging

    - id: smoke-test
      command: "npm run test:smoke -- --env=staging"
      depends_on: [deploy-staging]
      condition: "deploy-staging.success"
      timeout: 120000

    - id: deploy-production
      command: "npm run deploy:production"
      depends_on: [smoke-test]
      condition: "smoke-test.success"
      requires_approval: true
      env:
        DEPLOY_ENV: production

    # ============================================
    # Phase 7: 에러 핸들링 및 정리
    # ============================================
    - id: notify-failure
      command: "npm run notify:slack -- --status=failed --channel=#alerts"
      depends_on: [test-frontend, test-backend, test-e2e, deploy-staging, deploy-production]
      condition: |
        test-frontend.failed OR
        test-backend.failed OR
        test-e2e.failed OR
        deploy-staging.failed OR
        deploy-production.failed

    - id: cleanup
      command: "npm run cleanup:artifacts"
      depends_on: [deploy-production, notify-failure]
      condition: "deploy-production.completed OR notify-failure.completed"
      on_failure: continue
```

## 실행 순서 (토폴로지컬 정렬 결과)

| Level | Nodes | 실행 방식 | 예상 시간 |
|-------|-------|----------|----------|
| 0 | install | 순차 | 3분 |
| 1 | lint, security-scan, build-shared | 병렬 | 2분 |
| 2 | build-frontend, build-backend | 병렬 | 3분 |
| 3 | test-frontend, test-backend | 병렬 | 5분 |
| 4 | test-e2e | 순차 | 10분 |
| 5 | deploy-staging | 순차 | 2분 |
| 6 | smoke-test | 순차 | 1분 |
| 7 | deploy-production | 순차 (승인 필요) | 3분 |
| 8 | cleanup | 순차 | 30초 |

**총 예상 시간:** ~30분 (병렬 실행 시)

## CLI 실행

### 전체 파이프라인 실행

```bash
"fullstack-monorepo-pipeline DAG 실행해줘"
```

### 부분 실행

```bash
# 테스트까지만
"test-e2e까지만 DAG 실행해줘"

# 배포만
"deploy-staging부터 DAG 실행해줘"
```

### 드라이 런

```bash
"fullstack-monorepo-pipeline DAG 실행 계획 보여줘"
```

출력 예시:
```
DAG Execution Plan: fullstack-monorepo-pipeline
================================================

Total Nodes: 12
Estimated Time: ~30 minutes

Execution Order:
  Level 0: [install]
  Level 1: [lint, security-scan, build-shared]
  Level 2: [build-frontend, build-backend]
  Level 3: [test-frontend, test-backend]
  Level 4: [test-e2e]
  Level 5: [deploy-staging]
  Level 6: [smoke-test]
  Level 7: [deploy-production] (requires approval)
  Level 8: [cleanup]

Conditional Nodes:
  - test-frontend: depends on build-frontend.success
  - test-backend: depends on build-backend.success
  - test-e2e: depends on test-frontend.success AND test-backend.success
  - deploy-staging: depends on test-e2e.success AND security-scan check
  - notify-failure: on any failure
```

## 모니터링 출력

```
DAG Progress: fullstack-monorepo-pipeline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current Level: 3 / 8
Completed: 6 / 12 nodes

[✓] install          (45s)
[✓] lint             (12s)
[✓] security-scan    (8s)
[✓] build-shared     (25s)
[✓] build-frontend   (45s)
[✓] build-backend    (38s)
[▶] test-frontend    (running: 2m 15s)
[▶] test-backend     (running: 1m 52s)
[ ] test-e2e         (waiting)
[ ] deploy-staging   (waiting)
[ ] smoke-test       (waiting)
[ ] deploy-production (waiting, requires approval)

Estimated Remaining: ~18 minutes
```

## 실패 시나리오

### 테스트 실패 시

```yaml
# test-backend가 실패하면:
# 1. test-e2e는 스킵됨 (조건 미충족)
# 2. deploy-staging은 스킵됨
# 3. notify-failure가 실행됨
# 4. cleanup이 실행됨
```

### 부분 복구

```bash
# test-backend 수정 후 재실행
"test-backend부터 DAG 재실행해줘"
```

## 환경별 변형

### 개발 환경

```yaml
dag:
  name: "dev-pipeline"
  # 배포 단계 제외
  exclude_nodes:
    - deploy-staging
    - smoke-test
    - deploy-production
```

### PR 검증

```yaml
dag:
  name: "pr-check"
  # E2E 테스트 제외 (시간 절약)
  exclude_nodes:
    - test-e2e
    - deploy-*
```

## 체크포인트 및 복구

```yaml
checkpoint:
  enabled: true
  storage: ".temp/dag_checkpoints/"

  save:
    after: each_node
    data:
      - node_id
      - status
      - output
      - duration

  restore:
    from: "latest"
    # 또는
    from_timestamp: "2024-01-05T10:00:00Z"
```
