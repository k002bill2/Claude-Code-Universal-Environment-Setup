# Error Recovery Protocol

CLI 오케스트레이션 중 발생하는 오류를 처리하고 복구하기 위한 프로토콜입니다.

## 오류 분류

### Level 1: 경미한 오류 (Recoverable)

자동 복구 가능한 오류:

| 오류 유형 | 증상 | 자동 복구 전략 |
|-----------|------|----------------|
| 네트워크 타임아웃 | `ETIMEDOUT` | 지수 백오프로 재시도 |
| 일시적 파일 잠금 | `EBUSY` | 대기 후 재시도 |
| 패키지 다운로드 실패 | `npm ERR!` | 캐시 정리 후 재시도 |
| 포트 충돌 | `EADDRINUSE` | 다른 포트 할당 |

### Level 2: 중간 오류 (Partially Recoverable)

수동 개입 또는 대체 전략 필요:

| 오류 유형 | 증상 | 복구 전략 |
|-----------|------|-----------|
| 의존성 충돌 | `peer dependency` | 버전 조정 제안 |
| 빌드 실패 | `Exit code 1` | 로그 분석, 원인 제시 |
| 테스트 실패 | `X tests failed` | 실패 목록, 스킵 옵션 |
| 메모리 부족 | `heap out of memory` | 메모리 증가 옵션 |

### Level 3: 심각한 오류 (Non-Recoverable)

즉시 중단 필요:

| 오류 유형 | 증상 | 대응 |
|-----------|------|------|
| 권한 오류 | `EACCES`, `EPERM` | 중단, 권한 확인 요청 |
| 디스크 공간 부족 | `ENOSPC` | 중단, 공간 확보 요청 |
| 손상된 설정 | `Invalid JSON` | 중단, 설정 복구 안내 |
| 인증 실패 | `401`, `403` | 중단, 인증 정보 요청 |

## 복구 전략

### 1. 재시도 전략 (Retry)

```yaml
retry_strategy:
  max_attempts: 3
  initial_delay: 1000      # ms
  max_delay: 30000         # ms
  backoff: "exponential"   # linear | exponential | fixed

  # 재시도 가능한 오류 패턴
  retryable_errors:
    - "ETIMEDOUT"
    - "ECONNRESET"
    - "ECONNREFUSED"
    - "npm ERR! network"
    - "socket hang up"
```

**구현:**
```markdown
재시도 로직:

1. 첫 번째 시도 실패
2. 1초 대기 → 두 번째 시도
3. 실패 시 2초 대기 → 세 번째 시도
4. 실패 시 4초 대기 → 네 번째 시도 (최종)
5. 최종 실패 시 에러 리포트
```

### 2. 폴백 전략 (Fallback)

```yaml
fallback_strategy:
  npm_install:
    primary: "npm install"
    fallback: "npm install --legacy-peer-deps"
    last_resort: "npm install --force"

  build:
    primary: "npm run build"
    fallback: "npm run build -- --no-cache"
    last_resort: "rm -rf node_modules && npm install && npm run build"
```

### 3. 체크포인트 복구 (Checkpoint Recovery)

```yaml
checkpoint_recovery:
  enabled: true
  checkpoint_dir: ".temp/cli_checkpoints/"

  # 체크포인트 저장 시점
  save_points:
    - "stage_complete"
    - "artifact_generated"
    - "milestone_reached"

  # 복구 방법
  recovery_method:
    - "load_checkpoint"
    - "skip_completed"
    - "resume_from_stage"
```

## 오류 감지

### 종료 코드 매핑

```yaml
exit_codes:
  0: "success"
  1: "general_error"
  2: "misuse"
  126: "permission_denied"
  127: "command_not_found"
  128: "invalid_exit_argument"
  130: "terminated_by_ctrl_c"
  137: "killed_by_sigkill"
  143: "terminated_by_sigterm"
```

### 출력 패턴 매칭

```yaml
error_patterns:
  - pattern: "npm ERR!"
    type: "npm_error"
    severity: "medium"

  - pattern: "FATAL ERROR: .* heap"
    type: "memory_error"
    severity: "high"

  - pattern: "Error: ENOENT"
    type: "file_not_found"
    severity: "medium"

  - pattern: "SyntaxError:"
    type: "syntax_error"
    severity: "high"

  - pattern: "TypeError:"
    type: "type_error"
    severity: "high"
```

## 복구 절차

### 단계별 복구 프로세스

```
오류 발생
    │
    ▼
┌─────────────────┐
│ 오류 분류       │
│ (Level 1/2/3)   │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
Level 1    Level 2/3
    │         │
    ▼         │
자동 복구    │
시도         │
    │         │
    ├─────────┤
    │         │
 성공?     Level 2?
    │         │
    ▼         ▼
  완료     대체 전략
           제안
              │
              ▼
         사용자 확인
              │
              ▼
         조치 실행
```

### 오류별 복구 스크립트

**npm 설치 오류:**
```bash
# 1차: 캐시 정리
npm cache clean --force

# 2차: node_modules 삭제 후 재설치
rm -rf node_modules package-lock.json
npm install

# 3차: 레거시 피어 의존성 모드
npm install --legacy-peer-deps
```

**빌드 오류:**
```bash
# 1차: 캐시 정리 빌드
npm run build -- --no-cache

# 2차: TypeScript 캐시 정리
rm -rf .tsbuildinfo tsconfig.tsbuildinfo
npm run build

# 3차: 전체 정리 후 빌드
rm -rf node_modules dist .cache
npm install
npm run build
```

**테스트 오류:**
```bash
# 1차: 단일 재실행
npm test -- --no-cache

# 2차: 실패한 테스트만 재실행
npm test -- --onlyFailures

# 3차: 워치 모드로 디버깅
npm test -- --watch
```

## Claude Code 구현

### 오류 처리 패턴

```markdown
CLI 명령 실행 후 오류 발생 시:

1. 종료 코드 확인
2. 출력 로그 분석 (error_patterns 매칭)
3. 오류 레벨 분류
4. 복구 전략 선택:
   - Level 1: 자동 재시도
   - Level 2: 사용자에게 옵션 제시
   - Level 3: 즉시 중단 및 보고
```

### 오류 리포트 형식

```markdown
## CLI 오류 발생

**명령어**: `npm run build`
**종료 코드**: 1
**오류 유형**: 빌드 오류 (Level 2)

### 오류 내용
```
Error: Cannot find module '@/components/Button'
```

### 분석
- 모듈 경로 해석 실패
- tsconfig.json의 paths 설정 확인 필요

### 복구 옵션
1. **tsconfig 경로 수정** - paths 설정 확인 (권장)
2. **절대 경로로 변경** - 상대 경로 사용
3. **스킵하고 계속** - 이 빌드 건너뛰기

어떤 옵션을 선택하시겠습니까?
```

## 롤백 절차

### 롤백 트리거

```yaml
rollback_triggers:
  - "deploy_failure"
  - "smoke_test_failure"
  - "critical_error"
  - "user_request"
```

### 롤백 단계

```yaml
rollback_steps:
  - name: "stop_services"
    command: "docker-compose down"

  - name: "restore_backup"
    command: "cp -r .backup/* dist/"

  - name: "restart_services"
    command: "docker-compose up -d"

  - name: "verify_rollback"
    command: "npm run health-check"
```
