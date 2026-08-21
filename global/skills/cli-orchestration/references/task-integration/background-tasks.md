# Background Tasks Management

백그라운드에서 실행되는 CLI 작업을 관리하는 프로토콜입니다.

## 백그라운드 실행 개요

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Thread                             │
│                                                              │
│  User Request ──► Start Background Tasks ──► Continue Work   │
│                          │                                   │
│                          ▼                                   │
│              ┌───────────────────────┐                       │
│              │  Background Manager   │                       │
│              ├───────────────────────┤                       │
│              │ Task Queue            │                       │
│              │ ├─ Task A (running)   │                       │
│              │ ├─ Task B (running)   │                       │
│              │ └─ Task C (pending)   │                       │
│              │                       │                       │
│              │ Output Files          │                       │
│              │ ├─ /tmp/task_a.out    │                       │
│              │ └─ /tmp/task_b.out    │                       │
│              └───────────────────────┘                       │
│                          │                                   │
│                          ▼                                   │
│              Notification on Complete ──────────────────────►│
└─────────────────────────────────────────────────────────────┘
```

## 백그라운드 작업 유형

### 1. CLI 명령어 (Bash)

```yaml
bash_background:
  tool: "Bash"
  params:
    command: "npm run build"
    run_in_background: true
    timeout: 600000  # 10분

  result:
    task_id: "bash_12345"
    output_file: "/tmp/claude/task_12345.out"
```

### 2. 서브에이전트 (Task)

```yaml
task_background:
  tool: "Task"
  params:
    subagent_type: "test-automation-specialist"
    description: "테스트 실행"
    prompt: "전체 테스트 스위트를 실행하고 결과를 보고해줘"
    run_in_background: true

  result:
    agent_id: "agent_67890"
    output_file: "/tmp/claude/agent_67890.out"
```

## 작업 생명주기

```
┌─────────┐    ┌─────────┐    ┌───────────┐    ┌───────────┐
│ CREATED │───►│ RUNNING │───►│ COMPLETED │    │  FAILED   │
└─────────┘    └────┬────┘    └───────────┘    └───────────┘
                    │                                ▲
                    │         ┌───────────┐          │
                    └────────►│ CANCELLED │          │
                              └───────────┘          │
                    │                                │
                    └────────────────────────────────┘
```

### 상태 전이

```yaml
state_transitions:
  CREATED -> RUNNING:
    trigger: "process_started"

  RUNNING -> COMPLETED:
    trigger: "exit_code == 0"

  RUNNING -> FAILED:
    triggers:
      - "exit_code != 0"
      - "timeout_exceeded"
      - "resource_limit"

  RUNNING -> CANCELLED:
    trigger: "user_cancel OR dependent_failed"
```

## 출력 관리

### 출력 파일 구조

```yaml
output_structure:
  directory: "/tmp/claude/{session_id}/"

  files:
    main_output: "{task_id}.out"      # stdout + stderr
    stdout_only: "{task_id}.stdout"   # stdout만
    stderr_only: "{task_id}.stderr"   # stderr만
    metadata: "{task_id}.meta.json"   # 메타데이터

  metadata_content:
    task_id: string
    command: string
    start_time: timestamp
    end_time: timestamp?
    exit_code: number?
    status: string
```

### 출력 조회 전략

```yaml
output_retrieval:
  # 전체 출력
  full:
    tool: "Read"
    params:
      file_path: "{output_file}"

  # 마지막 N줄
  tail:
    tool: "Bash"
    params:
      command: "tail -n 50 {output_file}"

  # 실시간 스트리밍 (진행 중인 작업)
  streaming:
    tool: "Bash"
    params:
      command: "tail -f {output_file}"
      timeout: 5000
```

## TaskOutput 도구 활용

### 상태 확인 (논블로킹)

```yaml
status_check:
  tool: "TaskOutput"
  params:
    task_id: "{task_id}"
    block: false  # 즉시 반환
    timeout: 1000

  response:
    status: "running" | "completed" | "failed"
    output: string?  # 현재까지의 출력
```

### 완료 대기 (블로킹)

```yaml
wait_completion:
  tool: "TaskOutput"
  params:
    task_id: "{task_id}"
    block: true   # 완료까지 대기
    timeout: 300000  # 최대 5분

  response:
    status: "completed" | "failed"
    output: string
    exit_code: number
```

## 작업 취소

### 단일 작업 취소

```yaml
cancel_task:
  tool: "TaskStop"
  params:
    task_id: "{task_id}"

  cleanup:
    - "SIGTERM 전송"
    - "grace_period: 5s"
    - "SIGKILL if needed"
    - "output_file 보존"
```

### 전체 작업 취소

```yaml
cancel_all:
  strategy: "graceful"

  steps:
    1. "실행 중인 모든 task_id 조회"
    2. "각 작업에 TaskStop 호출"
    3. "대기 중인 작업 제거"
    4. "정리 상태 보고"
```

## 의존성 관리

### 작업 체인

```yaml
task_chain:
  tasks:
    - id: "install"
      command: "npm install"
      background: true

    - id: "build"
      command: "npm run build"
      depends_on: ["install"]
      background: true

    - id: "test"
      command: "npm test"
      depends_on: ["build"]
      background: true

  execution:
    wait_for_deps: true
    fail_fast: true
```

### 의존성 실패 처리

```yaml
dependency_failure:
  # install 실패 시
  on_failure:
    cancel_dependents: true  # build, test 취소

  # 부분 성공
  partial_success:
    report_completed: true
    report_cancelled: true
```

## 리소스 정리

### 자동 정리

```yaml
auto_cleanup:
  # 완료된 작업 출력 파일
  completed_tasks:
    retention: "1h"
    action: "delete"

  # 실패한 작업 출력 파일
  failed_tasks:
    retention: "24h"  # 디버깅 위해 더 오래 보관
    action: "archive"

  # 고아 프로세스
  orphan_processes:
    detection: "periodic"
    interval: "5m"
    action: "terminate"
```

### 세션 종료 시

```yaml
session_cleanup:
  on_session_end:
    - "실행 중인 모든 백그라운드 작업 종료"
    - "출력 파일 정리 (옵션)"
    - "임시 디렉토리 삭제"
```

## 모범 사례

### 백그라운드 실행 권장 상황

| 상황 | 이유 |
|------|------|
| 빌드 작업 | 오래 걸리고 다른 작업과 병렬 가능 |
| 테스트 실행 | 시간이 걸리고 결과만 필요 |
| 파일 다운로드 | I/O 바운드, 대기 불필요 |
| 데이터 처리 | CPU 집약적, 백그라운드에서 처리 |

### 포그라운드 실행 권장 상황

| 상황 | 이유 |
|------|------|
| 즉각 결과 필요 | `git status`, `ls` 등 |
| 인터랙티브 입력 | 사용자 입력 필요한 명령 |
| 짧은 명령어 | 1-2초 내 완료 |
| 의존 작업 준비 | 다음 작업에 결과 즉시 필요 |
