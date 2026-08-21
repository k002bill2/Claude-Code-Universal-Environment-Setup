# DAG Workflow Schema

DAG(Directed Acyclic Graph) 기반 워크플로우의 YAML 스키마 정의입니다.

## 기본 구조

```yaml
dag:
  name: string            # 워크플로우 이름 (선택)
  description: string     # 설명 (선택)

  # 전역 설정
  defaults:
    timeout: number       # 기본 타임아웃 (ms)
    on_failure: string    # 기본 실패 전략
    retry:
      max: number         # 기본 재시도 횟수
      delay: number       # 재시도 간격 (ms)

  # 노드 정의
  nodes:
    - id: string          # 고유 식별자 (필수)
      command: string     # 실행할 명령어 (필수)
      depends_on: [string]   # 의존하는 노드 ID 목록
      condition: string      # 조건부 실행 표현식
      on_failure: string     # 실패 시 동작
      timeout: number        # 타임아웃 (ms)
      retry:
        max: number          # 재시도 횟수
        delay: number        # 재시도 간격
      requires_approval: bool # 승인 필요 여부
      env: object            # 환경 변수
      working_dir: string    # 작업 디렉토리
```

## Node 속성 상세

### id (필수)

노드의 고유 식별자입니다.

```yaml
- id: install
- id: lint
- id: test-unit
```

**규칙:**
- 알파벳, 숫자, 하이픈, 언더스코어만 허용
- 대소문자 구분
- 워크플로우 내에서 고유해야 함

### command (필수)

실행할 CLI 명령어입니다.

```yaml
- id: install
  command: "npm ci"

- id: build
  command: "npm run build"

- id: docker
  command: "docker build -t myapp:latest ."
```

### depends_on

이 노드가 의존하는 다른 노드들의 ID 목록입니다.

```yaml
# 단일 의존성
- id: lint
  depends_on: [install]

# 복수 의존성
- id: test
  depends_on: [lint, typecheck]

# 의존성 없음 (루트 노드)
- id: install
  # depends_on 생략
```

### condition

조건부 실행을 위한 표현식입니다.

```yaml
# 이전 노드 성공 시에만 실행
- id: test
  depends_on: [lint, typecheck]
  condition: "lint.success AND typecheck.success"

# exit code 기반 조건
- id: deploy
  condition: "test.exit_code == 0"

# 복합 조건
- id: notify
  condition: "build.success OR (build.failed AND retry.exhausted)"
```

**지원 표현식:** `./conditional-execution.md` 참조

### on_failure

노드 실패 시 동작을 정의합니다.

| 값 | 설명 |
|----|------|
| `abort` | 전체 워크플로우 중단 |
| `continue` | 다음 노드로 계속 진행 |
| `retry` | 재시도 후 실패 시 abort |
| `rollback` | 이전 상태로 복원 시도 |

```yaml
- id: lint
  on_failure: continue  # 린트 실패해도 계속

- id: test
  on_failure: abort     # 테스트 실패 시 중단

- id: deploy
  on_failure: rollback  # 배포 실패 시 롤백
```

### timeout

명령어 실행 타임아웃 (밀리초)입니다.

```yaml
- id: install
  timeout: 180000  # 3분

- id: test
  timeout: 600000  # 10분
```

**기본값:** 300000 (5분)

### retry

재시도 설정입니다.

```yaml
- id: deploy
  retry:
    max: 3       # 최대 3회 재시도
    delay: 5000  # 5초 간격

- id: network-call
  retry:
    max: 5
    delay: 2000
    backoff: exponential  # 지수 백오프 (선택)
```

### requires_approval

실행 전 사용자 승인이 필요한지 여부입니다.

```yaml
- id: deploy-prod
  requires_approval: true

- id: deploy-staging
  requires_approval: false
```

### env

노드별 환경 변수입니다.

```yaml
- id: build
  command: "npm run build"
  env:
    NODE_ENV: production
    API_URL: https://api.example.com
```

### working_dir

명령어를 실행할 디렉토리입니다.

```yaml
- id: frontend-build
  command: "npm run build"
  working_dir: "./packages/frontend"

- id: backend-build
  command: "npm run build"
  working_dir: "./packages/backend"
```

## 완전한 예시

```yaml
dag:
  name: "ci-pipeline"
  description: "CI/CD 파이프라인"

  defaults:
    timeout: 300000
    on_failure: abort
    retry:
      max: 2
      delay: 3000

  nodes:
    - id: install
      command: "npm ci"
      timeout: 180000

    - id: lint
      command: "npm run lint"
      depends_on: [install]
      on_failure: continue

    - id: typecheck
      command: "npm run typecheck"
      depends_on: [install]

    - id: test-unit
      command: "npm run test:unit"
      depends_on: [lint, typecheck]
      condition: "typecheck.success"
      timeout: 600000

    - id: test-e2e
      command: "npm run test:e2e"
      depends_on: [lint, typecheck]
      condition: "typecheck.success"
      timeout: 900000

    - id: build
      command: "npm run build"
      depends_on: [test-unit, test-e2e]
      condition: "test-unit.success AND test-e2e.success"
      env:
        NODE_ENV: production

    - id: deploy-staging
      command: "npm run deploy:staging"
      depends_on: [build]

    - id: deploy-prod
      command: "npm run deploy:prod"
      depends_on: [deploy-staging]
      requires_approval: true
      retry:
        max: 3
        delay: 10000
```

## 그래프 시각화

위 예시의 DAG 구조:

```
        install
        /     \
      lint   typecheck
        \     /    \
      test-unit  test-e2e
           \      /
            build
              |
        deploy-staging
              |
        deploy-prod
```

## 유효성 검사

DAG 정의 시 다음을 자동 검증합니다:

1. **순환 의존성 검사**: 순환 참조가 없어야 함
2. **존재하지 않는 노드 참조**: depends_on에 유효한 노드만 참조
3. **중복 ID 검사**: 모든 노드 ID가 고유해야 함
4. **필수 필드 검사**: id, command 필수

```yaml
# 잘못된 예시 - 순환 의존성
nodes:
  - id: a
    depends_on: [b]
  - id: b
    depends_on: [a]  # 오류: 순환 의존성
```
