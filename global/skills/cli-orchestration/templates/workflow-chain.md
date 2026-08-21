# Workflow Chain Template

순차적 의존성이 있는 작업 파이프라인을 실행하기 위한 템플릿입니다.

## 기본 구조

```yaml
workflow:
  name: "워크플로우 이름"
  description: "워크플로우 설명"

  # 전역 설정
  config:
    checkpoint_enabled: true
    checkpoint_dir: ".temp/checkpoints/"
    artifacts_dir: ".temp/artifacts/"
    notify_on_completion: true

  # 스테이지 정의
  stages:
    - name: "stage_1"
      command: "command 1"
      on_failure: "abort"      # abort | continue | retry | rollback
      timeout: 60000

    - name: "stage_2"
      command: "command 2"
      on_failure: "abort"
      artifacts: ["output/"]   # 보관할 아티팩트

    - name: "stage_3"
      command: "command 3"
      on_failure: "rollback"
      requires_approval: true  # 사용자 승인 필요
```

## 실행 예시

### 1. 기본 CI 파이프라인

```yaml
workflow:
  name: "ci-pipeline"
  description: "린트 → 테스트 → 빌드 파이프라인"

  stages:
    - name: "lint"
      command: "npm run lint"
      on_failure: "abort"
      timeout: 60000

    - name: "typecheck"
      command: "npm run typecheck"
      on_failure: "abort"
      timeout: 60000

    - name: "test"
      command: "npm test -- --coverage"
      on_failure: "abort"
      timeout: 180000
      artifacts: ["coverage/"]

    - name: "build"
      command: "npm run build"
      on_failure: "abort"
      timeout: 120000
      artifacts: ["dist/"]
```

### 2. 배포 파이프라인 (승인 포함)

```yaml
workflow:
  name: "deploy-pipeline"
  description: "테스트 → 빌드 → 스테이징 → 프로덕션"

  stages:
    - name: "test"
      command: "npm test"
      on_failure: "abort"

    - name: "build"
      command: "npm run build"
      on_failure: "abort"
      artifacts: ["dist/"]

    - name: "deploy-staging"
      command: "npm run deploy:staging"
      on_failure: "rollback"

    - name: "smoke-test"
      command: "npm run test:e2e:staging"
      on_failure: "rollback"

    - name: "deploy-production"
      command: "npm run deploy:production"
      on_failure: "rollback"
      requires_approval: true
      approval_message: "프로덕션 배포를 진행하시겠습니까?"
```

### 3. 재시도 로직 포함

```yaml
workflow:
  name: "resilient-pipeline"

  stages:
    - name: "install"
      command: "npm install"
      on_failure: "retry"
      retry_config:
        max_attempts: 3
        delay: 5000          # 재시도 간격 (ms)
        backoff: "exponential"

    - name: "test"
      command: "npm test"
      on_failure: "continue"  # 실패해도 계속

    - name: "build"
      command: "npm run build"
      on_failure: "abort"
```

## 체크포인트 시스템

### 체크포인트 저장

각 스테이지 완료 시 자동 저장:

```yaml
checkpoint:
  workflow: "ci-pipeline"
  timestamp: "2024-01-15T10:30:00Z"
  current_stage: "test"
  completed_stages:
    - name: "lint"
      status: "success"
      duration: 12340
    - name: "typecheck"
      status: "success"
      duration: 8720
  artifacts:
    - path: "coverage/"
      size: "2.3MB"
```

### 체크포인트에서 재시작

```
"test 스테이지부터 다시 실행해줘"
```

**실행 동작:**
1. 체크포인트 파일 로드
2. 완료된 스테이지 스킵
3. 지정된 스테이지부터 재시작

## 실패 처리 전략

### abort (기본)
```yaml
on_failure: "abort"
# 즉시 중단, 에러 리포트 생성
```

### continue
```yaml
on_failure: "continue"
# 실패 기록 후 다음 스테이지 계속
```

### retry
```yaml
on_failure: "retry"
retry_config:
  max_attempts: 3
  delay: 5000
# 지정된 횟수만큼 재시도
```

### rollback
```yaml
on_failure: "rollback"
rollback_command: "npm run rollback"
# 롤백 명령 실행 후 중단
```

## Claude Code 구현 패턴

### 순차 실행 체인

```markdown
워크플로우 체인 실행:

1. lint 스테이지 실행
   - 성공: 다음 스테이지로
   - 실패: 중단 및 에러 리포트

2. test 스테이지 실행
   - 성공: 아티팩트 저장, 다음 스테이지로
   - 실패: 중단

3. build 스테이지 실행
   - 성공: 완료 리포트
   - 실패: 롤백 시도
```

### 승인 요청 패턴

```markdown
배포 스테이지 도달 시:

AskUserQuestion 도구로 승인 요청:
- question: "프로덕션 배포를 진행하시겠습니까?"
- options:
  - "예, 배포 진행"
  - "아니오, 중단"
  - "스테이징 결과 확인"
```

### 결과 리포트

```markdown
## 워크플로우 실행 결과

**워크플로우**: ci-pipeline
**상태**: ✅ 성공
**총 소요시간**: 2분 34초

### 스테이지별 결과

| 순서 | 스테이지 | 상태 | 소요시간 |
|------|----------|------|----------|
| 1 | lint | ✅ 성공 | 12.3s |
| 2 | typecheck | ✅ 성공 | 8.7s |
| 3 | test | ✅ 성공 | 45.2s |
| 4 | build | ✅ 성공 | 28.1s |

### 아티팩트
- `coverage/` - 2.3MB
- `dist/` - 15.7MB
```
