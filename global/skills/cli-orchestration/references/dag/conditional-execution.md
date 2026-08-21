# Conditional Execution

DAG 워크플로우에서 조건부 실행을 위한 표현식 정의 및 평가 방법입니다.

## 조건 표현식 문법

### 기본 구조

```yaml
condition: "<expression>"
```

### 지원 연산자

| 연산자 | 설명 | 예시 |
|--------|------|------|
| `AND` | 논리 AND | `a.success AND b.success` |
| `OR` | 논리 OR | `a.success OR b.success` |
| `NOT` | 논리 NOT | `NOT a.failed` |
| `==` | 같음 | `a.exit_code == 0` |
| `!=` | 같지 않음 | `a.exit_code != 1` |
| `<`, `>` | 비교 | `a.duration < 60000` |
| `<=`, `>=` | 비교 | `a.exit_code >= 0` |

### 괄호

복잡한 조건은 괄호로 그룹화합니다.

```yaml
condition: "(a.success AND b.success) OR c.skipped"
```

## 노드 상태 참조

### 상태 속성

각 노드는 실행 후 다음 상태를 갖습니다:

| 속성 | 타입 | 설명 |
|------|------|------|
| `success` | bool | 성공 여부 (exit_code == 0) |
| `failed` | bool | 실패 여부 (exit_code != 0) |
| `skipped` | bool | 스킵 여부 |
| `exit_code` | number | 종료 코드 |
| `duration` | number | 실행 시간 (ms) |
| `completed` | bool | 완료 여부 (성공/실패 무관) |

### 참조 문법

```yaml
# 노드 ID.속성
lint.success
typecheck.exit_code
test.duration
```

## 조건 유형

### 1. 성공 조건

이전 노드가 성공했을 때만 실행합니다.

```yaml
# 기본 성공 조건
- id: build
  depends_on: [test]
  condition: "test.success"

# 복수 노드 모두 성공
- id: deploy
  depends_on: [lint, typecheck, test]
  condition: "lint.success AND typecheck.success AND test.success"
```

### 2. 실패 조건

이전 노드가 실패했을 때 실행합니다 (에러 핸들링용).

```yaml
# 실패 시 알림
- id: notify-failure
  depends_on: [deploy]
  condition: "deploy.failed"

# 실패 시 롤백
- id: rollback
  depends_on: [deploy]
  condition: "deploy.failed AND deploy.exit_code != 130"  # SIGINT 제외
```

### 3. 선택적 의존성

일부 노드 실패해도 계속 진행합니다.

```yaml
# lint 실패해도 계속 (경고만)
- id: test
  depends_on: [lint, typecheck]
  condition: "typecheck.success"  # lint는 조건에서 제외
```

### 4. 조건부 분기

조건에 따라 다른 경로로 분기합니다.

```yaml
nodes:
  - id: test

  # 테스트 성공 시 배포
  - id: deploy
    depends_on: [test]
    condition: "test.success"

  # 테스트 실패 시 디버그 리포트
  - id: debug-report
    depends_on: [test]
    condition: "test.failed"
```

### 5. 최종 노드 (Always)

성공/실패 무관하게 항상 실행합니다.

```yaml
# 정리 작업 - 항상 실행
- id: cleanup
  depends_on: [deploy]
  condition: "deploy.completed"  # 성공/실패 무관

# 알림 - 항상 실행
- id: notification
  depends_on: [deploy, cleanup]
  condition: "deploy.completed AND cleanup.completed"
```

## 고급 표현식

### Exit Code 기반 조건

```yaml
# 특정 exit code 처리
- id: retry-handler
  depends_on: [api-call]
  condition: "api-call.exit_code == 429"  # Rate limit

# 범위 조건
- id: error-handler
  depends_on: [process]
  condition: "process.exit_code >= 1 AND process.exit_code <= 10"
```

### 시간 기반 조건

```yaml
# 빠른 실행 시 스킵
- id: detailed-test
  depends_on: [quick-test]
  condition: "quick-test.success AND quick-test.duration < 30000"

# 느린 실행 시 알림
- id: performance-alert
  depends_on: [build]
  condition: "build.success AND build.duration > 300000"
```

### 복합 조건

```yaml
# 복잡한 조건 조합
- id: deploy-production
  depends_on: [test-unit, test-e2e, security-scan]
  condition: |
    (test-unit.success AND test-e2e.success AND security-scan.success)
    OR
    (test-unit.success AND test-e2e.skipped AND security-scan.exit_code == 0)
```

## 조건 평가 순서

1. 의존하는 모든 노드 실행 완료 대기
2. 조건 표현식 평가
3. 결과에 따라:
   - `true`: 노드 실행
   - `false`: 노드 스킵 (`skipped: true`)

## 스킵된 노드 처리

스킵된 노드를 의존하는 노드의 동작:

```yaml
nodes:
  - id: optional-lint
    condition: "install.duration < 10000"  # 조건에 따라 스킵 가능

  - id: test
    depends_on: [optional-lint]
    # 기본: optional-lint가 스킵되면 test도 스킵

  - id: test-always
    depends_on: [optional-lint]
    condition: "optional-lint.success OR optional-lint.skipped"
    # optional-lint 스킵되어도 실행
```

## 오류 처리

### 잘못된 조건 표현식

```yaml
# 잘못된 예시
condition: "unknwon_node.success"  # 오류: 존재하지 않는 노드
condition: "test.unknwon_prop"      # 오류: 존재하지 않는 속성
condition: "test.success &&"        # 오류: 문법 오류
```

### 순환 조건 방지

```yaml
# 잘못된 예시 - 상호 의존 조건
- id: a
  condition: "b.success"

- id: b
  condition: "a.success"  # 교착 상태
```

## 예시: 완전한 조건부 파이프라인

```yaml
dag:
  name: "conditional-pipeline"

  nodes:
    # Phase 1: Setup
    - id: install
      command: "npm ci"

    # Phase 2: Quality (병렬, 선택적)
    - id: lint
      command: "npm run lint"
      depends_on: [install]
      on_failure: continue

    - id: typecheck
      command: "npm run typecheck"
      depends_on: [install]

    # Phase 3: Test (조건부)
    - id: test-unit
      command: "npm run test:unit"
      depends_on: [lint, typecheck]
      condition: "typecheck.success"  # typecheck 필수, lint 선택

    - id: test-e2e
      command: "npm run test:e2e"
      depends_on: [lint, typecheck]
      condition: "typecheck.success"

    # Phase 4: Build (모든 테스트 성공 시)
    - id: build
      command: "npm run build"
      depends_on: [test-unit, test-e2e]
      condition: "test-unit.success AND test-e2e.success"

    # Phase 5: Deploy (조건부 분기)
    - id: deploy-staging
      command: "npm run deploy:staging"
      depends_on: [build]
      condition: "build.success"

    - id: deploy-prod
      command: "npm run deploy:prod"
      depends_on: [deploy-staging]
      condition: "deploy-staging.success"
      requires_approval: true

    # Error handling
    - id: notify-failure
      command: "npm run notify:slack -- --status=failed"
      depends_on: [test-unit, test-e2e, build, deploy-staging]
      condition: |
        test-unit.failed OR test-e2e.failed OR
        build.failed OR deploy-staging.failed

    # Cleanup (항상)
    - id: cleanup
      command: "npm run cleanup"
      depends_on: [deploy-prod, deploy-staging, notify-failure]
      condition: |
        deploy-prod.completed OR deploy-staging.completed OR notify-failure.completed
```
