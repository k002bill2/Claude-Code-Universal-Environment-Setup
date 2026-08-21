# Log Streaming Protocol

병렬 CLI 작업의 로그를 실시간으로 수집하고 통합 표시하는 프로토콜입니다.

## 로그 아키텍처

```
+-------------------+     +-------------------+
| Task 1 (stdout)   |---->|                   |
+-------------------+     |   Log Aggregator  |
| Task 2 (stdout)   |---->|                   |
+-------------------+     |   - Buffering     |
| Task 3 (stderr)   |---->|   - Tagging       |
+-------------------+     |   - Filtering     |
                          +--------+----------+
                                   |
                          +--------v----------+
                          |  Unified Output   |
                          +-------------------+
```

## 로그 포맷

### 태그 구조

```
[TIMESTAMP] [TASK_ID] [LEVEL] message

예시:
[14:32:15.123] [build:frontend] [INFO] Compiling 45 files...
[14:32:15.456] [test] [WARN] Deprecated API usage
[14:32:15.789] [build:backend] [ERROR] Module not found
```

### 레벨 정의

| Level | 색상 | 설명 |
|-------|------|------|
| DEBUG | Gray | 상세 디버깅 정보 |
| INFO | White | 일반 진행 상황 |
| WARN | Yellow | 경고 (계속 진행) |
| ERROR | Red | 오류 (실패 가능) |
| FATAL | Red+Bold | 치명적 오류 (즉시 중단) |

## 스트리밍 전략

### 1. 인터리브드 출력 (기본)

모든 작업의 로그가 시간순으로 통합 표시:

```
[14:32:10] [frontend] Starting development server...
[14:32:11] [backend] Connecting to database...
[14:32:11] [frontend] Compiled successfully
[14:32:12] [backend] Database connected
```

### 2. 분리된 출력

각 작업의 로그를 별도 섹션으로 분리:

```
--- [frontend] ---
Starting development server...
Compiled successfully

--- [backend] ---
Connecting to database...
Database connected
```

### 3. 요약 모드

핵심 이벤트만 표시:

```
[OK] frontend: Compiled in 2.3s
[OK] backend: Server started on :8000
[!!] test: 3 tests failed
```

## 버퍼링 설정

```yaml
buffer:
  size: 1000              # 작업당 최대 로그 라인
  flush_interval: 100ms   # 출력 주기

  overflow_strategy: "drop_oldest"  # 또는 "compress", "file"

  # 중요 메시지는 항상 유지
  preserve_patterns:
    - "error"
    - "warning"
    - "failed"
    - "success"
```

## 필터링 규칙

```yaml
filters:
  # 레벨 필터
  min_level: INFO   # DEBUG 숨김

  # 패턴 필터
  exclude:
    - "node_modules"
    - "Compiling..."  # 반복 메시지 제거
    - "^\\s*$"        # 빈 줄 제거

  # 작업별 필터
  task_filters:
    test:
      min_level: WARN  # 테스트는 경고 이상만
    build:
      include: ["error", "warning", "built"]
```

## 에러 집계

```yaml
error_aggregation:
  enabled: true

  # 동일 에러 그룹화
  group_by:
    - error_code
    - file_path

  # 요약 표시
  summary_format: |
    [{count}x] {first_occurrence_time} - {error_message}

  # 예시:
  # [5x] 14:32:15 - TS2322: Type mismatch
  # [2x] 14:32:18 - Module not found: @/utils
```

## 파일 출력

```yaml
file_output:
  enabled: true
  directory: ".temp/cli_logs/"

  naming:
    pattern: "{task_id}_{timestamp}.log"
    # 예: build-frontend_20240130_143215.log

  rotation:
    max_size: 10MB
    max_files: 5
    compress: true
```

## 실시간 검색

로그 스트림에서 실시간 검색:

```yaml
search:
  # 하이라이트 모드
  highlight:
    pattern: "error|warning"
    style: "bold_red"

  # 필터 모드
  filter:
    pattern: "TS\\d{4}"  # TypeScript 에러 코드만
    context_lines: 2      # 전후 2줄 포함
```

## 알림 트리거

특정 패턴 감지 시 알림:

```yaml
notifications:
  - pattern: "Build failed"
    action: "notify_user"
    message: "빌드가 실패했습니다. 로그를 확인하세요."

  - pattern: "All tests passed"
    action: "notify_user"
    message: "모든 테스트가 통과했습니다!"

  - pattern: "FATAL"
    action: "pause_and_alert"
    message: "치명적 오류 발생. 작업이 일시 중지되었습니다."
```

## 성능 최적화

```yaml
performance:
  # 출력 디바운싱
  debounce_ms: 50

  # 배치 업데이트
  batch_size: 10

  # 메모리 제한
  max_memory_mb: 100

  # 긴 라인 처리
  max_line_length: 500
  truncate_suffix: "... [truncated]"
```
