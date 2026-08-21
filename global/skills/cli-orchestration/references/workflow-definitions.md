# Workflow Definitions Reference

YAML 워크플로우 정의 형식에 대한 참조 문서입니다.

## 스키마 개요

```yaml
name: string              # 워크플로우 이름 (필수)
version: string           # 버전 (권장: semver)
description: string       # 설명

ethical_constraints:      # ACE Layer 1 윤리적 제약
  - string

settings:                 # 전역 설정
  max_parallel: number
  fail_fast: boolean
  timeout_default: string
  checkpoint_after: [string]
  working_directory: string

env:                      # 환경 변수
  KEY: value

tasks:                    # 태스크 목록 (필수)
  - id: string            # 고유 ID (필수)
    name: string          # 표시 이름
    command: string       # 실행 명령어 (필수)
    ...

error_strategies:         # 에러 처리 전략
  retry: {...}
  fallback: [...]
  rollback: [...]

notifications:            # 알림 설정
  on_success: [...]
  on_failure: [...]

agent_delegation:         # 에이전트 위임 설정
  enabled: boolean
  mappings: [...]

metadata:                 # 메타데이터
  author: string
  tags: [string]
```

## Task 필드 상세

### 필수 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | string | 고유 식별자 (영문, 숫자, 하이픈) |
| `command` | string | 실행할 CLI 명령어 |

### 선택 필드

| 필드 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `name` | string | id | 표시 이름 |
| `working_directory` | string | . | 작업 디렉토리 |
| `depends_on` | [string] | [] | 의존 태스크 ID 목록 |
| `parallel_group` | string | - | 병렬 실행 그룹 |
| `condition` | string | - | 실행 조건 표현식 |
| `timeout` | string | 300s | 타임아웃 |
| `retry` | number | 0 | 재시도 횟수 |
| `on_failure` | string | abort | 실패 시 동작 |
| `requires_approval` | boolean | false | 사용자 승인 필요 |
| `env` | object | {} | 태스크별 환경 변수 |
| `artifacts` | [string] | [] | 생성되는 아티팩트 |

### 예시

```yaml
tasks:
  - id: build
    name: Build Application
    command: npm run build
    working_directory: $PROJECT_ROOT
    depends_on: [test]
    condition: "test.success"
    timeout: 600s
    retry: 2
    on_failure: abort
    env:
      NODE_ENV: production
    artifacts:
      - dist/
```

## 조건 표현식

### 지원 표현식

| 표현식 | 설명 | 예시 |
|--------|------|------|
| `task.success` | 태스크 성공 여부 | `test.success` |
| `task.exit_code` | 종료 코드 | `test.exit_code == 0` |
| `AND` | 논리 AND | `lint.success AND test.success` |
| `OR` | 논리 OR | `test.success OR test.skipped` |

### 예시

```yaml
# 두 태스크 모두 성공해야 실행
condition: "lint.success AND typecheck.success"

# 하나라도 성공하면 실행
condition: "test-unit.success OR test-integration.success"

# 종료 코드 기반
condition: "lint.exit_code == 0"
```

## 병렬 실행

### parallel_group

같은 `parallel_group`을 가진 태스크는 동시에 실행됩니다.

```yaml
tasks:
  - id: lint
    command: npm run lint
    parallel_group: validation

  - id: typecheck
    command: npm run typecheck
    parallel_group: validation

  - id: format-check
    command: npm run format:check
    parallel_group: validation
```

### 의존성과 병렬 실행

```
install
   │
   ├──► lint ─────────┐
   │                   │
   ├──► typecheck ────┼──► test ──► build
   │                   │
   └──► format-check ─┘
```

## 에러 처리 전략

### retry

```yaml
error_strategies:
  retry:
    max_attempts: 3
    backoff: exponential      # linear, exponential, fixed
    initial_delay: 1s
    max_delay: 30s
```

### fallback

```yaml
error_strategies:
  fallback:
    - task: build
      fallback_command: npm run build:legacy
```

### rollback

```yaml
error_strategies:
  rollback:
    - task: deploy
      rollback_steps:
        - kubectl rollout undo deployment/app
        - slack notify "Rollback completed"
```

## 환경 변수

### 전역 환경 변수

```yaml
env:
  NODE_ENV: production
  CI: true
  API_URL: https://api.example.com
```

### 태스크별 환경 변수

```yaml
tasks:
  - id: test
    command: npm test
    env:
      NODE_ENV: test
      COVERAGE: true
```

### 내장 변수

| 변수 | 설명 |
|------|------|
| `$PROJECT_ROOT` | 프로젝트 루트 디렉토리 |
| `$WORKFLOW_NAME` | 현재 워크플로우 이름 |
| `$TASK_ID` | 현재 태스크 ID |
| `$TIMESTAMP` | 현재 타임스탬프 |

## 체크포인트

```yaml
settings:
  checkpoint_after: [install, build]
```

체크포인트가 생성되면 해당 지점부터 재시작할 수 있습니다:

```bash
/run-workflow my-workflow --resume --checkpoint cp_build_20250131
```

## 알림

```yaml
notifications:
  on_success:
    - type: console
      message: "워크플로우 완료: $WORKFLOW_NAME"

  on_failure:
    - type: console
      message: "실패: $FAILED_TASK"
```

## 에이전트 위임

```yaml
agent_delegation:
  enabled: true
  mappings:
    - task_pattern: "test*"
      agent: test-automation-specialist
    - task_pattern: "build*"
      agent: cli-worker
    - task_pattern: "*"
      agent: Bash
```

## 검증 규칙

1. **ID 유일성**: 모든 태스크 ID는 고유해야 함
2. **순환 의존성 금지**: DAG 형태여야 함
3. **존재하는 의존성**: depends_on에 명시된 태스크가 존재해야 함
4. **조건 문법**: condition 표현식이 유효해야 함
