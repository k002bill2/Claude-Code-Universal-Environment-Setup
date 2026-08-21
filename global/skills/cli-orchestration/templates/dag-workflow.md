# DAG Workflow Template

복잡한 의존성 그래프 기반 워크플로우 템플릿입니다.

## 템플릿 정의

```yaml
dag:
  name: "{{workflow_name}}"
  description: "{{description}}"

  defaults:
    timeout: {{default_timeout | 300000}}
    on_failure: {{default_failure_strategy | "abort"}}
    retry:
      max: {{default_retry_max | 2}}
      delay: {{default_retry_delay | 5000}}

  nodes:
    {{#each nodes}}
    - id: {{this.id}}
      command: "{{this.command}}"
      {{#if this.depends_on}}
      depends_on: [{{this.depends_on}}]
      {{/if}}
      {{#if this.condition}}
      condition: "{{this.condition}}"
      {{/if}}
      {{#if this.on_failure}}
      on_failure: {{this.on_failure}}
      {{/if}}
      {{#if this.timeout}}
      timeout: {{this.timeout}}
      {{/if}}
      {{#if this.retry}}
      retry:
        max: {{this.retry.max}}
        delay: {{this.retry.delay}}
      {{/if}}
      {{#if this.requires_approval}}
      requires_approval: {{this.requires_approval}}
      {{/if}}
    {{/each}}
```

## 사용 예시

### 1. 기본 CI 파이프라인

```yaml
dag:
  name: "ci-pipeline"
  description: "기본 CI 파이프라인"

  nodes:
    - id: install
      command: "npm ci"

    - id: lint
      command: "npm run lint"
      depends_on: [install]
      on_failure: continue

    - id: typecheck
      command: "npm run typecheck"
      depends_on: [install]

    - id: test
      command: "npm test"
      depends_on: [lint, typecheck]
      condition: "typecheck.success"
      timeout: 600000

    - id: build
      command: "npm run build"
      depends_on: [test]
      condition: "test.success"
```

### 2. 풀스택 빌드 파이프라인

```yaml
dag:
  name: "fullstack-build"
  description: "프론트엔드/백엔드 병렬 빌드"

  nodes:
    # 공통 설치
    - id: install-shared
      command: "npm ci --workspace=packages/shared"

    - id: build-shared
      command: "npm run build --workspace=packages/shared"
      depends_on: [install-shared]

    # 프론트엔드
    - id: install-frontend
      command: "npm ci --workspace=packages/frontend"
      depends_on: [build-shared]

    - id: lint-frontend
      command: "npm run lint --workspace=packages/frontend"
      depends_on: [install-frontend]

    - id: test-frontend
      command: "npm test --workspace=packages/frontend"
      depends_on: [lint-frontend]

    - id: build-frontend
      command: "npm run build --workspace=packages/frontend"
      depends_on: [test-frontend]
      condition: "test-frontend.success"

    # 백엔드
    - id: install-backend
      command: "npm ci --workspace=packages/backend"
      depends_on: [build-shared]

    - id: lint-backend
      command: "npm run lint --workspace=packages/backend"
      depends_on: [install-backend]

    - id: test-backend
      command: "npm test --workspace=packages/backend"
      depends_on: [lint-backend]

    - id: build-backend
      command: "npm run build --workspace=packages/backend"
      depends_on: [test-backend]
      condition: "test-backend.success"

    # 통합
    - id: integration-test
      command: "npm run test:e2e"
      depends_on: [build-frontend, build-backend]
      condition: "build-frontend.success AND build-backend.success"
      timeout: 900000
```

### 3. 조건부 배포 파이프라인

```yaml
dag:
  name: "conditional-deploy"
  description: "조건부 배포 파이프라인"

  nodes:
    - id: test
      command: "npm test -- --coverage"
      timeout: 600000

    - id: coverage-check
      command: "npm run coverage:check"
      depends_on: [test]
      condition: "test.success"

    - id: build
      command: "npm run build"
      depends_on: [coverage-check]
      condition: "coverage-check.success"

    # 성공 경로
    - id: deploy-staging
      command: "npm run deploy:staging"
      depends_on: [build]
      condition: "build.success"

    - id: smoke-test
      command: "npm run test:smoke"
      depends_on: [deploy-staging]
      condition: "deploy-staging.success"

    - id: deploy-production
      command: "npm run deploy:production"
      depends_on: [smoke-test]
      condition: "smoke-test.success"
      requires_approval: true

    # 실패 경로
    - id: notify-failure
      command: "npm run notify:failure"
      depends_on: [test, coverage-check, build]
      condition: "test.failed OR coverage-check.failed OR build.failed"

    # 항상 실행
    - id: cleanup
      command: "npm run cleanup"
      depends_on: [deploy-production, notify-failure]
      condition: "deploy-production.completed OR notify-failure.completed"
```

## 실행 방법

### CLI에서 실행

```bash
# 전체 DAG 실행
"dag-workflow 실행해줘"

# 특정 노드부터 실행
"test 노드부터 DAG 실행해줘"

# 특정 노드만 실행
"lint 노드만 실행해줘"
```

### 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--dry-run` | 실제 실행 없이 계획만 출력 | false |
| `--from-node` | 특정 노드부터 시작 | 첫 노드 |
| `--max-parallel` | 최대 병렬 실행 수 | 5 |
| `--verbose` | 상세 로그 출력 | false |

## 그래프 시각화

DAG 구조를 시각화하여 확인할 수 있습니다:

```
            install
               │
         ┌─────┴─────┐
         ↓           ↓
       lint      typecheck
         │           │
         └─────┬─────┘
               ↓
             test
               │
               ↓
             build
               │
         ┌─────┴─────┐
         ↓           ↓
   deploy-staging  notify-failure
         │
         ↓
    smoke-test
         │
         ↓
  deploy-production
```

## 모니터링

실행 중 진행 상황을 추적합니다:

```yaml
monitoring:
  display:
    - current_node
    - completed_nodes
    - pending_nodes
    - running_time
    - estimated_remaining

  format: |
    DAG Progress: {{completed}}/{{total}} ({{percentage}}%)
    Current: {{current_node}}
    Running: {{running_nodes}}
    Next: {{next_nodes}}
```

## 오류 복구

### 체크포인트에서 재시작

```yaml
checkpoint:
  enabled: true
  save_after: each_node

  restart:
    from: "last_successful"
    # 또는
    from_node: "build"
```

### 수동 개입

```yaml
on_error:
  pause: true
  prompt: "오류 발생. 계속하시겠습니까?"
  options:
    - retry: "현재 노드 재시도"
    - skip: "현재 노드 스킵하고 계속"
    - abort: "워크플로우 중단"
```
