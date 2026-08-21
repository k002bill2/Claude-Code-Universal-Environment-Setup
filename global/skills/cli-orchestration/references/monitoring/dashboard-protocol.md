# Terminal Dashboard Protocol

실시간 CLI 작업 진행 상황을 터미널에 시각화하는 프로토콜입니다.

## 대시보드 레이아웃

```
+------------------------------------------------------------------+
|  CLI Orchestration Dashboard                    [14:32:15]       |
+------------------------------------------------------------------+
| ACTIVE TASKS (3/5)                                               |
| +--------------------------+  +---------------------------+       |
| | npm run build:frontend   |  | npm run build:backend     |       |
| | [=========>    ] 67%     |  | [=============>  ] 89%    |       |
| | Time: 45s / ~60s         |  | Time: 1:12 / ~1:20        |       |
| | Status: Compiling...     |  | Status: Bundling...       |       |
| +--------------------------+  +---------------------------+       |
| +--------------------------+                                     |
| | npm test                 |                                     |
| | [====>         ] 34%     |                                     |
| | Time: 23s / ~70s         |                                     |
| | Status: Running tests... |                                     |
| +--------------------------+                                     |
+------------------------------------------------------------------+
| QUEUE (2 pending)                                                |
| > npm run deploy (waiting: build:frontend, build:backend)        |
| > npm run notify                                                 |
+------------------------------------------------------------------+
| COMPLETED (1)          FAILED (0)                                |
| > npm install [OK]                                               |
+------------------------------------------------------------------+
| LOGS (latest 3)                                                  |
| [14:32:10] build:frontend: Compiling TypeScript...               |
| [14:32:12] build:backend: Generated 45 chunks                    |
| [14:32:14] test: 23/68 tests passed                              |
+------------------------------------------------------------------+
```

## 표시 요소

### 1. 상태 인디케이터

| 상태 | 아이콘 | 색상 |
|------|--------|------|
| Running | `[>>>]` | Blue |
| Success | `[OK]` | Green |
| Failed | `[!!]` | Red |
| Pending | `[..]` | Gray |
| Paused | `[||]` | Yellow |

### 2. 진행률 바

```
[=========>    ] 67%   # 진행 중
[##############] 100%  # 완료
[XXXXXXXXXXXXXX] ERR   # 실패
[..............] 0%    # 대기 중
```

### 3. 시간 추정

```
Time: 실제경과 / 예상총시간
Time: 45s / ~60s      # 정상 진행
Time: 2:30 / ~1:00    # 예상 초과 (빨간색 표시)
```

## 업데이트 전략

```yaml
update_interval:
  active_tasks: 500ms    # 활성 작업 상태
  logs: 100ms            # 로그 스트림
  summary: 2000ms        # 전체 요약

rendering:
  mode: incremental      # 전체 새로고침 대신 부분 업데이트
  clear_on_complete: true
  preserve_history: last_50_logs
```

## 구현 패턴

### Bash 출력 파싱

```bash
# 진행 상황 파싱 패턴
npm_progress_pattern='\[(\d+)/(\d+)\]'
webpack_progress_pattern='(\d+)%'
pytest_progress_pattern='(\d+) passed'

# 실시간 출력 캡처
command 2>&1 | while IFS= read -r line; do
  parse_and_update "$line"
done
```

### Task 도구 상태 조회

```yaml
polling_strategy:
  initial_interval: 500ms
  max_interval: 5000ms
  backoff_multiplier: 1.5

  status_mapping:
    task_running: "active"
    task_complete: "completed"
    task_error: "failed"
```

## 에러 표시

```
+------------------------------------------------------------------+
| FAILED: npm run build:backend                                    |
+------------------------------------------------------------------+
| Exit Code: 1                                                     |
| Duration: 1:45                                                   |
| Error: TypeScript compilation failed                             |
|                                                                  |
| > src/api/routes.ts(45,12): error TS2322                         |
| > Type 'string' is not assignable to type 'number'               |
|                                                                  |
| Suggested Actions:                                               |
| 1. Fix type error in routes.ts:45                                |
| 2. Run 'npm run build:backend' to retry                          |
+------------------------------------------------------------------+
```

## 키보드 단축키 (대화형 모드)

| 키 | 동작 |
|----|------|
| `q` | 대시보드 종료 |
| `r` | 실패한 작업 재시도 |
| `c` | 작업 취소 |
| `l` | 로그 전체 보기 |
| `↑↓` | 작업 선택 |

## 접근성

- 색맹 지원: 아이콘과 텍스트로 상태 구분
- 스크린 리더: 주요 상태 변경 시 알림
- 저시력: 큰 폰트 모드 지원
