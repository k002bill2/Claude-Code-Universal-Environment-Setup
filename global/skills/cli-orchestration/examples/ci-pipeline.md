# CI Pipeline Example

지속적 통합(CI) 파이프라인을 CLI 오케스트레이션으로 구현하는 예시입니다.

## 파이프라인 구조

```
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│  Lint   │ → │  Type   │ → │  Test   │ → │  Build  │ → │ Deploy  │
│         │   │  Check  │   │         │   │         │   │         │
└─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
```

## 기본 CI 파이프라인

### 설정

```yaml
workflow:
  name: "ci-pipeline"
  description: "표준 CI 파이프라인: lint → typecheck → test → build"

  config:
    checkpoint_enabled: true
    checkpoint_dir: ".temp/ci_checkpoints/"
    artifacts_dir: ".temp/ci_artifacts/"
    fail_fast: true

  stages:
    - name: "lint"
      command: "npm run lint"
      timeout: 60000
      on_failure: "abort"
      description: "코드 스타일 검사"

    - name: "typecheck"
      command: "npm run typecheck"
      timeout: 120000
      on_failure: "abort"
      description: "TypeScript 타입 검사"

    - name: "test"
      command: "npm test -- --coverage"
      timeout: 300000
      on_failure: "abort"
      artifacts: ["coverage/"]
      description: "단위 테스트 실행"

    - name: "build"
      command: "npm run build"
      timeout: 180000
      on_failure: "abort"
      artifacts: ["dist/"]
      description: "프로덕션 빌드"
```

## 실행 예시

### 전체 파이프라인 실행

**요청:**
```
"CI 파이프라인 실행해줘"
```

**실행:**

```
═══════════════════════════════════════════════════
  CI Pipeline: ci-pipeline
═══════════════════════════════════════════════════

[Stage 1/4] lint
───────────────────────────────────────────────────
실행: npm run lint
상태: ✅ 성공 (12.3s)

[Stage 2/4] typecheck
───────────────────────────────────────────────────
실행: npm run typecheck
상태: ✅ 성공 (8.7s)

[Stage 3/4] test
───────────────────────────────────────────────────
실행: npm test -- --coverage
상태: ✅ 성공 (45.2s)
아티팩트: coverage/ (2.3MB)

[Stage 4/4] build
───────────────────────────────────────────────────
실행: npm run build
상태: ✅ 성공 (28.1s)
아티팩트: dist/ (15.7MB)

═══════════════════════════════════════════════════
  결과: ✅ 성공 (총 94.3s)
═══════════════════════════════════════════════════
```

### 실패 시 동작

**테스트 실패 예시:**

```
[Stage 3/4] test
───────────────────────────────────────────────────
실행: npm test -- --coverage
상태: ❌ 실패 (32.5s)

오류 내용:
  FAIL src/components/Button.test.tsx
    ● Button › renders correctly
      Expected: "Click me"
      Received: "Click Me"

파이프라인 중단됨 (on_failure: abort)

체크포인트 저장: .temp/ci_checkpoints/ci-pipeline-20240115.json
```

### 체크포인트에서 재시작

**요청:**
```
"test 스테이지부터 다시 실행해줘"
```

**실행:**
```
체크포인트 로드: .temp/ci_checkpoints/ci-pipeline-20240115.json

스킵된 스테이지:
  ✅ lint (이전 실행에서 성공)
  ✅ typecheck (이전 실행에서 성공)

[Stage 3/4] test (재시작)
───────────────────────────────────────────────────
실행: npm test -- --coverage
상태: ✅ 성공 (43.8s)

[Stage 4/4] build
───────────────────────────────────────────────────
실행: npm run build
상태: ✅ 성공 (27.9s)

═══════════════════════════════════════════════════
  결과: ✅ 성공 (재시작 후 71.7s)
═══════════════════════════════════════════════════
```

## 고급 CI 파이프라인

### 병렬 검사 단계

```yaml
workflow:
  name: "parallel-ci"

  stages:
    # Phase 1: 병렬 검사
    - name: "checks"
      parallel:
        - command: "npm run lint"
          name: "lint"
        - command: "npm run typecheck"
          name: "typecheck"
        - command: "npm run format:check"
          name: "format"
      on_failure: "abort"

    # Phase 2: 테스트
    - name: "test"
      command: "npm test -- --coverage"
      on_failure: "abort"

    # Phase 3: 빌드
    - name: "build"
      command: "npm run build"
      on_failure: "abort"
```

**실행:**
```
[Phase 1] 병렬 검사
───────────────────────────────────────────────────
  lint ─────────── ✅ 12.3s
  typecheck ────── ✅ 8.7s   } 병렬 실행
  format ────────── ✅ 3.2s

Phase 1 완료: 12.3s (가장 긴 작업 기준)

[Phase 2] 테스트
───────────────────────────────────────────────────
  test ─────────── ✅ 45.2s

[Phase 3] 빌드
───────────────────────────────────────────────────
  build ────────── ✅ 28.1s

총 소요시간: 85.6s
순차 실행 예상: 97.5s (12% 단축)
```

### 배포 파이프라인 (승인 포함)

```yaml
workflow:
  name: "deploy-pipeline"

  stages:
    - name: "ci"
      stages:
        - name: "lint"
          command: "npm run lint"
        - name: "test"
          command: "npm test"
        - name: "build"
          command: "npm run build"
          artifacts: ["dist/"]

    - name: "deploy-staging"
      command: "npm run deploy:staging"
      on_failure: "rollback"

    - name: "smoke-test"
      command: "npm run test:e2e:staging"
      on_failure: "rollback"

    - name: "deploy-production"
      command: "npm run deploy:production"
      requires_approval: true
      approval_message: |
        스테이징 테스트 통과!
        프로덕션 배포를 진행하시겠습니까?
      on_failure: "rollback"
      rollback_command: "npm run rollback:production"
```

**실행:**
```
[CI 단계] lint → test → build
═══════════════════════════════════════════════════
모든 CI 단계 ✅ 성공

[배포 단계] 스테이징
═══════════════════════════════════════════════════
deploy-staging: ✅ 성공
smoke-test: ✅ 성공

[배포 단계] 프로덕션
═══════════════════════════════════════════════════
⚠️ 승인 필요

스테이징 테스트 통과!
프로덕션 배포를 진행하시겠습니까?

[1] 예, 배포 진행
[2] 아니오, 중단
[3] 스테이징 로그 확인
```

## Claude Code 구현 패턴

### 파이프라인 실행

```markdown
CI 파이프라인 실행 절차:

1. 파이프라인 설정 로드
2. 체크포인트 확인 (재시작인 경우)
3. 각 스테이지 순차 실행:
   - 명령어 실행
   - 결과 확인
   - 성공: 체크포인트 저장, 다음 스테이지
   - 실패: on_failure 전략 적용
4. 아티팩트 수집
5. 최종 리포트 생성
```

### 승인 요청

```markdown
승인 필요 스테이지 도달 시:

AskUserQuestion 도구 사용:
- question: approval_message 내용
- options:
  - label: "배포 진행"
    description: "프로덕션에 배포합니다"
  - label: "중단"
    description: "파이프라인을 중단합니다"
  - label: "로그 확인"
    description: "이전 단계 로그를 확인합니다"
```

### 결과 리포트

```markdown
## CI 파이프라인 결과

**파이프라인**: ci-pipeline
**트리거**: manual
**상태**: ✅ 성공

### 스테이지별 결과

| 스테이지 | 상태 | 소요시간 | 비고 |
|----------|------|----------|------|
| lint | ✅ | 12.3s | - |
| typecheck | ✅ | 8.7s | - |
| test | ✅ | 45.2s | 커버리지 78% |
| build | ✅ | 28.1s | 번들 크기 15.7MB |

### 테스트 커버리지

| 영역 | 커버리지 |
|------|----------|
| Statements | 78.5% |
| Branches | 72.3% |
| Functions | 81.2% |
| Lines | 79.1% |

### 빌드 정보

- **번들 크기**: 15.7MB (gzip: 4.2MB)
- **청크 수**: 12
- **소스맵**: 생성됨

### 다음 단계

1. `npm run deploy:staging` - 스테이징 배포
2. `npm run test:e2e` - E2E 테스트
3. `npm run deploy:production` - 프로덕션 배포
```

## 문제 해결

### 일반적인 실패 원인

```yaml
common_failures:
  lint:
    - "ESLint 규칙 위반"
    - "Prettier 포맷 불일치"
    recovery: "npm run lint:fix && npm run format"

  typecheck:
    - "타입 불일치"
    - "누락된 타입 정의"
    recovery: "타입 오류 수정 후 재실행"

  test:
    - "스냅샷 불일치"
    - "비동기 타임아웃"
    recovery: "npm test -- -u (스냅샷 업데이트)"

  build:
    - "모듈 해석 실패"
    - "메모리 부족"
    recovery: "node --max-old-space-size=4096 node_modules/.bin/vite build"
```

### 디버깅 모드

```yaml
debug_mode:
  enabled: false
  verbose_logging: true
  keep_temp_files: true
  pause_on_failure: true
```
