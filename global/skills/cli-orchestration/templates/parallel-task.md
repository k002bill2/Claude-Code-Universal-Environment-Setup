# Parallel Task Template

다중 CLI 명령어를 병렬로 실행하기 위한 템플릿입니다.

## 기본 구조

```yaml
parallel_execution:
  name: "작업 이름"
  description: "작업 설명"

  # 실행 설정
  config:
    max_concurrent: 5          # 최대 동시 실행 수
    fail_fast: true            # 하나 실패 시 전체 중단
    timeout: 300000            # 전체 타임아웃 (ms)
    workspace: ".temp/parallel/"

  # 명령어 그룹
  groups:
    - name: "group_1"
      commands:
        - cmd: "command 1"
          timeout: 60000
          retry: 3
        - cmd: "command 2"
          timeout: 60000

    - name: "group_2"
      depends_on: ["group_1"]  # group_1 완료 후 실행
      commands:
        - cmd: "command 3"
        - cmd: "command 4"
```

## 실행 예시

### 1. 단순 병렬 실행

모든 명령어가 독립적일 때:

```yaml
parallel_execution:
  name: "simple-parallel"
  config:
    max_concurrent: 3

  groups:
    - name: "all"
      commands:
        - cmd: "npm run lint"
        - cmd: "npm run typecheck"
        - cmd: "npm run test"
```

**Claude Code 실행 패턴:**
```
3개 명령어를 동시에 백그라운드로 실행:
1. Bash(command="npm run lint", run_in_background=true)
2. Bash(command="npm run typecheck", run_in_background=true)
3. Bash(command="npm run test", run_in_background=true)

이후 TaskOutput으로 각 결과 수집
```

### 2. 의존성 있는 병렬 실행

그룹 간 의존성이 있을 때:

```yaml
parallel_execution:
  name: "dependent-parallel"

  groups:
    - name: "install"
      commands:
        - cmd: "npm install"
        - cmd: "pip install -r requirements.txt"

    - name: "build"
      depends_on: ["install"]
      commands:
        - cmd: "npm run build:frontend"
        - cmd: "npm run build:backend"
        - cmd: "npm run build:shared"

    - name: "test"
      depends_on: ["build"]
      commands:
        - cmd: "npm test"
        - cmd: "pytest"
```

**실행 순서:**
1. `install` 그룹의 2개 명령어 병렬 실행
2. 완료 후 `build` 그룹의 3개 명령어 병렬 실행
3. 완료 후 `test` 그룹의 2개 명령어 병렬 실행

### 3. 조건부 실행

특정 조건에서만 실행:

```yaml
parallel_execution:
  name: "conditional-parallel"

  groups:
    - name: "check"
      commands:
        - cmd: "npm run lint"
          continue_on_error: true
        - cmd: "npm run typecheck"

    - name: "build"
      depends_on: ["check"]
      condition: "all_success"  # check 그룹 전체 성공 시에만
      commands:
        - cmd: "npm run build"
```

## 결과 수집

### 성공/실패 집계

```yaml
results:
  summary:
    total: 5
    success: 4
    failed: 1
    skipped: 0

  details:
    - command: "npm run lint"
      status: "success"
      duration: 12340

    - command: "npm run test"
      status: "failed"
      duration: 45230
      error: "3 tests failed"
```

### 로그 병합

```yaml
log_aggregation:
  strategy: "timestamp"  # 타임스탬프 기준 정렬
  output: ".temp/parallel/merged.log"
  separate_stderr: true
```

## 롤백 옵션

```yaml
rollback:
  enabled: true
  strategy: "reverse"  # 역순으로 정리 명령 실행
  commands:
    - "rm -rf dist/"
    - "docker-compose down"
```

## Claude Code 구현 패턴

### 병렬 실행: Bash 도구 vs Agent 도구

독립적인 CLI 명령은 Bash 도구 호출을 한 메시지에 모아 병렬 실행합니다
(서브에이전트가 필요 없습니다 — `subagent_type` 에 도구 이름은 올 수 없습니다):

```markdown
독립 CLI 명령 3건을 병렬로 수행:

1. Bash(command="npm run lint")
2. Bash(command="npm run typecheck")
3. Bash(command="npm test")

세 호출을 같은 메시지에 담으면 동시에 실행됩니다.
조사·구현처럼 판단이 필요한 작업만 Agent(subagent_type="...") 로 위임합니다.
```

### 결과 통합 리포트

```markdown
## 병렬 실행 결과

| 명령어 | 상태 | 소요시간 | 비고 |
|--------|------|----------|------|
| npm run lint | ✅ 성공 | 12.3s | - |
| npm run typecheck | ✅ 성공 | 8.7s | - |
| npm test | ❌ 실패 | 45.2s | 3 tests failed |

**전체 결과**: 2/3 성공 (66.7%)
**총 소요시간**: 45.2s (가장 긴 작업 기준)
```
