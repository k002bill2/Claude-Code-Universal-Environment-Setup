# Resource Limits Protocol

CLI 오케스트레이션 시 리소스 사용을 제한하고 관리하기 위한 프로토콜입니다.

## 리소스 제한 설정

### 기본 제한값

```yaml
resource_limits:
  # 동시 실행 제한
  concurrency:
    max_parallel_commands: 5
    max_parallel_agents: 3
    max_parallel_projects: 4

  # 시간 제한
  timeouts:
    command_default: 120000      # 2분
    command_max: 600000          # 10분
    workflow_default: 1800000    # 30분
    workflow_max: 3600000        # 1시간

  # 메모리 제한
  memory:
    per_process: "2GB"
    total_max: "8GB"
    node_options: "--max-old-space-size=4096"

  # 디스크 제한
  disk:
    temp_dir_max: "5GB"
    artifact_max: "1GB"
    log_max: "100MB"
```

## 동시성 제한

### 동시 실행 수 결정

```yaml
concurrency_rules:
  # 시스템 리소스 기반
  auto_scale:
    cpu_threshold: 0.8          # CPU 80% 이상 시 제한
    memory_threshold: 0.7       # 메모리 70% 이상 시 제한

  # 작업 유형별 제한
  by_task_type:
    build: 2                    # 빌드는 최대 2개
    test: 4                     # 테스트는 최대 4개
    lint: 5                     # 린트는 최대 5개
    install: 2                  # 설치는 최대 2개
```

### 큐잉 전략

```yaml
queuing:
  strategy: "priority"          # fifo | lifo | priority
  max_queue_size: 20
  queue_timeout: 300000         # 5분

  priority_levels:
    critical: 1                 # 배포, 롤백
    high: 2                     # 빌드
    normal: 3                   # 테스트
    low: 4                      # 린트, 포맷
```

## 타임아웃 관리

### 명령어별 타임아웃

```yaml
command_timeouts:
  # 빠른 명령어
  fast:
    - pattern: "npm run lint"
      timeout: 60000
    - pattern: "npm run format"
      timeout: 30000

  # 중간 명령어
  medium:
    - pattern: "npm test"
      timeout: 180000
    - pattern: "npm run typecheck"
      timeout: 120000

  # 느린 명령어
  slow:
    - pattern: "npm run build"
      timeout: 300000
    - pattern: "docker build"
      timeout: 600000
    - pattern: "npm install"
      timeout: 300000
```

### 타임아웃 처리

```yaml
timeout_handling:
  on_timeout:
    action: "kill"              # kill | warn | extend
    grace_period: 10000         # 정리 시간 10초

  extension:
    allowed: true
    max_extensions: 2
    extension_amount: 60000     # 1분씩 연장
```

## 메모리 관리

### Node.js 메모리 설정

```yaml
node_memory:
  # 환경별 설정
  development:
    max_old_space: 4096         # 4GB
    max_semi_space: 256         # 256MB

  ci:
    max_old_space: 2048         # 2GB
    max_semi_space: 128         # 128MB

  production:
    max_old_space: 8192         # 8GB
    max_semi_space: 512         # 512MB
```

### 메모리 모니터링

```yaml
memory_monitoring:
  check_interval: 10000         # 10초마다 체크
  warning_threshold: 0.7        # 70% 경고
  critical_threshold: 0.9       # 90% 위험

  actions:
    warning:
      - "log_warning"
      - "reduce_concurrency"
    critical:
      - "pause_new_tasks"
      - "gc_collect"
```

## 디스크 관리

### 임시 파일 관리

```yaml
temp_management:
  base_dir: ".temp/cli_orchestration/"
  cleanup_policy: "on_success"  # always | on_success | never

  retention:
    logs: "7d"                  # 7일 보관
    artifacts: "30d"            # 30일 보관
    checkpoints: "24h"          # 24시간 보관

  size_limits:
    per_task: "500MB"
    total: "5GB"
```

### 자동 정리

```yaml
auto_cleanup:
  enabled: true
  schedule: "after_workflow"

  rules:
    - type: "logs"
      max_age: "7d"
      max_size: "100MB"

    - type: "temp"
      max_age: "24h"
      max_size: "1GB"

    - type: "cache"
      max_age: "30d"
      max_size: "2GB"
```

## 네트워크 제한

### 대역폭 관리

```yaml
network_limits:
  # 동시 다운로드 제한
  max_concurrent_downloads: 5

  # 레지스트리별 제한
  registries:
    npm:
      max_concurrent: 3
      timeout: 60000
    docker:
      max_concurrent: 2
      timeout: 300000
```

## Effort Scaling

### 복잡도별 리소스 할당

```yaml
effort_scaling:
  trivial:
    description: "단일 명령어"
    max_concurrent: 1
    timeout: 60000
    memory: "512MB"

  simple:
    description: "2-3개 병렬 명령어"
    max_concurrent: 3
    timeout: 180000
    memory: "1GB"

  moderate:
    description: "워크플로우 체인"
    max_concurrent: 5
    timeout: 600000
    memory: "2GB"

  complex:
    description: "멀티 프로젝트 오케스트레이션"
    max_concurrent: 10
    timeout: 1800000
    memory: "4GB"
```

## 모니터링 및 알림

### 리소스 모니터링

```yaml
monitoring:
  metrics:
    - "cpu_usage"
    - "memory_usage"
    - "disk_usage"
    - "active_processes"

  alerts:
    - condition: "cpu_usage > 90%"
      action: "reduce_concurrency"

    - condition: "memory_usage > 85%"
      action: "pause_new_tasks"

    - condition: "disk_usage > 95%"
      action: "emergency_cleanup"
```

### 리포트 형식

```markdown
## 리소스 사용 리포트

**시간**: 2024-01-15 10:30:00
**워크플로우**: build-all

### 리소스 사용량

| 리소스 | 최대값 | 평균값 | 제한 |
|--------|--------|--------|------|
| CPU | 78% | 45% | 80% |
| 메모리 | 3.2GB | 2.1GB | 4GB |
| 디스크 I/O | 120MB/s | 45MB/s | - |
| 활성 프로세스 | 5 | 3 | 5 |

### 권장 사항
- ✅ 리소스 사용 정상 범위
- ⚠️ 메모리 사용량 모니터링 권장
```

## Claude Code 구현

### 리소스 체크

```markdown
CLI 명령 실행 전 리소스 확인:

1. 현재 활성 프로세스 수 확인
2. 가용 메모리 확인
3. 디스크 공간 확인
4. 제한 초과 시 대기 또는 경고
```

### 제한 초과 처리

```markdown
리소스 제한 초과 시:

1. 새 작업 큐에 추가
2. 사용자에게 대기 상태 알림
3. 리소스 확보 시 자동 재개
4. 타임아웃 시 옵션 제시
```
