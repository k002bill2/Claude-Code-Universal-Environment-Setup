# 실시간 모니터링 예제

CLI 작업의 실시간 모니터링 기능 활용 예제입니다.

## 예제 1: 병렬 빌드 모니터링

### 요청

```
"frontend, backend, shared 빌드를 병렬로 실행하고 진행 상황 보여줘"
```

### 실행 과정

#### 1. 작업 시작

```yaml
parallel_tasks:
  - task_id: "build_frontend"
    command: "npm run build:frontend"
    background: true

  - task_id: "build_backend"
    command: "npm run build:backend"
    background: true

  - task_id: "build_shared"
    command: "npm run build:shared"
    background: true
```

#### 2. 대시보드 표시

```
╔══════════════════════════════════════════════════════════════╗
║  Parallel Build Monitor                         [14:32:15]   ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  ┌─────────────────────────────────────────────────────────┐ ║
║  │ frontend (build:frontend)                                │ ║
║  │ [=================>          ] 67%                       │ ║
║  │ Time: 45s / ~70s    Status: Compiling TypeScript...      │ ║
║  └─────────────────────────────────────────────────────────┘ ║
║                                                               ║
║  ┌─────────────────────────────────────────────────────────┐ ║
║  │ backend (build:backend)                                  │ ║
║  │ [========================>   ] 89%                       │ ║
║  │ Time: 1:12 / ~1:20   Status: Bundling...                 │ ║
║  └─────────────────────────────────────────────────────────┘ ║
║                                                               ║
║  ┌─────────────────────────────────────────────────────────┐ ║
║  │ shared (build:shared)                                    │ ║
║  │ [############] COMPLETE                                  │ ║
║  │ Time: 23s           Status: Done                         │ ║
║  └─────────────────────────────────────────────────────────┘ ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║  LOGS (최근 5줄)                                              ║
║  [14:32:10] frontend: Compiling 45 TypeScript files...       ║
║  [14:32:12] backend:  Generated chunk main.js (245 KB)       ║
║  [14:32:14] shared:   Build complete!                        ║
║  [14:32:14] frontend: Processing styles...                   ║
║  [14:32:15] backend:  Optimizing production build...         ║
╚══════════════════════════════════════════════════════════════╝
```

#### 3. 완료 요약

```
╔══════════════════════════════════════════════════════════════╗
║                    Build Summary                              ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Total Time: 1m 25s                                           ║
║  Tasks: 3 completed, 0 failed                                 ║
║                                                               ║
║  ┌──────────────┬──────────┬─────────┐                       ║
║  │ Task         │ Duration │ Status  │                       ║
║  ├──────────────┼──────────┼─────────┤                       ║
║  │ shared       │    23s   │   OK    │                       ║
║  │ frontend     │  1m 15s  │   OK    │                       ║
║  │ backend      │  1m 25s  │   OK    │                       ║
║  └──────────────┴──────────┴─────────┘                       ║
║                                                               ║
║  Parallelization: 3 concurrent tasks                          ║
║  Time Saved: ~1m 38s (vs sequential)                          ║
║  Efficiency: 72%                                              ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 2: CI 파이프라인 모니터링

### 요청

```
"lint → typecheck → test → build 파이프라인 실행하고 각 단계 진행 상황 보여줘"
```

### 실행 과정

#### 대시보드 (진행 중)

```
╔══════════════════════════════════════════════════════════════╗
║  CI Pipeline                                    [14:35:00]   ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Pipeline Progress                                            ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  [1] lint         [DONE]  ████████████████████  8s           ║
║  [2] typecheck    [DONE]  ████████████████████  12s          ║
║  [3] test         [>>>>]  ████████████░░░░░░░░  65% (28s)    ║
║  [4] build        [WAIT]  ░░░░░░░░░░░░░░░░░░░░  pending      ║
║                                                               ║
║  ═══════════════════════════════════════════════════════════ ║
║  Overall: ████████████████░░░░░░░░░░░░░░░░░░░░  48%          ║
║  Elapsed: 48s / ~1m 40s                                       ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║  Current Stage: test                                          ║
║  ─────────────────────────────────────────────────────────── ║
║  Running: 45/68 tests                                         ║
║  Passed: 43  Failed: 0  Skipped: 2                            ║
║                                                               ║
║  Latest:                                                      ║
║  ✓ src/components/Button.test.tsx (245ms)                    ║
║  ✓ src/hooks/useAuth.test.ts (189ms)                         ║
║  ⏳ src/pages/Dashboard.test.tsx (running...)                ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 3: 에러 발생 시 모니터링

### 상황

테스트 실행 중 실패 발생

### 대시보드 (에러)

```
╔══════════════════════════════════════════════════════════════╗
║  CI Pipeline                                    [14:38:45]   ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Pipeline Progress                                            ║
║  ═══════════════════════════════════════════════════════════ ║
║                                                               ║
║  [1] lint         [DONE]  ████████████████████  8s           ║
║  [2] typecheck    [DONE]  ████████████████████  12s          ║
║  [3] test         [FAIL]  ████████████████XXXX  FAILED       ║
║  [4] build        [SKIP]  ░░░░░░░░░░░░░░░░░░░░  cancelled    ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║  ⚠️  FAILURE DETAILS                                          ║
║  ─────────────────────────────────────────────────────────── ║
║                                                               ║
║  Stage: test                                                  ║
║  Exit Code: 1                                                 ║
║  Duration: 45s                                                ║
║                                                               ║
║  Error Summary:                                               ║
║  ┌─────────────────────────────────────────────────────────┐ ║
║  │ FAIL src/services/auth.test.ts                          │ ║
║  │   ● should validate token expiry                        │ ║
║  │     Expected: true                                      │ ║
║  │     Received: false                                     │ ║
║  │                                                          │ ║
║  │ FAIL src/utils/date.test.ts                             │ ║
║  │   ● should format date correctly                        │ ║
║  │     Expected: "2024-01-30"                              │ ║
║  │     Received: "01/30/2024"                              │ ║
║  └─────────────────────────────────────────────────────────┘ ║
║                                                               ║
║  Test Results: 66 passed, 2 failed, 68 total                 ║
║                                                               ║
╠══════════════════════════════════════════════════════════════╣
║  Suggested Actions:                                           ║
║  1. Fix failing tests in auth.test.ts and date.test.ts       ║
║  2. Run 'npm test -- --testPathPattern="auth|date"' to retry ║
║  3. Run 'npm test' to run full test suite again              ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 예제 4: 로그 스트리밍

### 요청

```
"npm run build 실행하면서 로그 실시간으로 보여줘"
```

### 로그 스트림 출력

```
╔══════════════════════════════════════════════════════════════╗
║  Log Stream: npm run build                      [LIVE]       ║
╠══════════════════════════════════════════════════════════════╣
║  Filter: ALL  │  Level: INFO+  │  Auto-scroll: ON            ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  [14:40:01] [INFO]  Starting build process...                ║
║  [14:40:01] [INFO]  TypeScript version: 5.3.3                ║
║  [14:40:02] [INFO]  Compiling TypeScript files...            ║
║  [14:40:03] [DEBUG] Processing: src/index.ts                 ║
║  [14:40:03] [DEBUG] Processing: src/App.tsx                  ║
║  [14:40:04] [WARN]  Unused import in src/utils/helpers.ts    ║
║  [14:40:05] [INFO]  TypeScript compilation complete (3.2s)   ║
║  [14:40:05] [INFO]  Starting Vite build...                   ║
║  [14:40:06] [INFO]  Building for production...               ║
║  [14:40:08] [INFO]  vite v5.0.10 building for production...  ║
║  [14:40:10] [INFO]  ✓ 234 modules transformed.               ║
║  [14:40:12] [INFO]  Rendering chunks...                      ║
║  [14:40:15] [INFO]  Computing gzip size...                   ║
║  [14:40:16] [INFO]  dist/index.html         0.54 kB          ║
║  [14:40:16] [INFO]  dist/assets/index.js   145.23 kB         ║
║  [14:40:16] [INFO]  dist/assets/index.css   12.45 kB         ║
║  [14:40:16] [INFO]  ✓ built in 10.12s                        ║
║  ▌                                                            ║
╠══════════════════════════════════════════════════════════════╣
║  Duration: 15s  │  Lines: 18  │  Errors: 0  │  Warnings: 1   ║
╚══════════════════════════════════════════════════════════════╝
```

---

## 모니터링 설정 예시

### 사용자 설정

```yaml
# ~/.claude/cli-orchestration/monitoring-config.yaml
monitoring:
  default_mode: "dashboard"  # dashboard, logs, minimal

  dashboard:
    refresh_rate: 500ms
    show_logs: true
    log_lines: 5

  logs:
    level: "INFO"
    timestamp: true
    color: true

  notifications:
    on_complete: true
    on_error: true
    sound: false
```
