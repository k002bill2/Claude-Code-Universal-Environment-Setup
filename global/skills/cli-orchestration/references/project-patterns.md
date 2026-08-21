# Multi-Project Patterns Reference

다중 프로젝트 CLI 오케스트레이션 패턴에 대한 참조 문서입니다.

## 패턴 개요

### 1. Monorepo 패턴

하나의 저장소에 여러 패키지가 있는 구조입니다.

```
project/
├── packages/
│   ├── frontend/
│   ├── backend/
│   ├── shared/
│   └── utils/
├── package.json
└── lerna.json (또는 pnpm-workspace.yaml)
```

**워크플로우 예시:**

```yaml
name: monorepo-build
tasks:
  - id: install-root
    command: npm ci

  - id: build-shared
    command: npm run build
    working_directory: $PROJECT_ROOT/packages/shared
    depends_on: [install-root]

  - id: build-utils
    command: npm run build
    working_directory: $PROJECT_ROOT/packages/utils
    depends_on: [install-root]

  - id: build-frontend
    command: npm run build
    working_directory: $PROJECT_ROOT/packages/frontend
    depends_on: [build-shared, build-utils]

  - id: build-backend
    command: npm run build
    working_directory: $PROJECT_ROOT/packages/backend
    depends_on: [build-shared, build-utils]
```

### 2. Multi-Repo 패턴

여러 저장소에 걸친 프로젝트 구조입니다.

```
~/projects/
├── frontend-app/
├── backend-api/
├── shared-lib/
└── infrastructure/
```

**워크플로우 예시:**

```yaml
name: multi-repo-deploy
settings:
  working_directory: ~/projects

tasks:
  - id: sync-repos
    command: |
      cd frontend-app && git pull
      cd ../backend-api && git pull
      cd ../shared-lib && git pull

  - id: build-shared
    command: npm run build
    working_directory: ~/projects/shared-lib
    depends_on: [sync-repos]

  - id: build-frontend
    command: npm run build
    working_directory: ~/projects/frontend-app
    depends_on: [build-shared]
    parallel_group: apps

  - id: build-backend
    command: npm run build
    working_directory: ~/projects/backend-api
    depends_on: [build-shared]
    parallel_group: apps
```

### 3. Microservices 패턴

마이크로서비스 아키텍처의 서비스들을 조율합니다.

```
services/
├── api-gateway/
├── user-service/
├── order-service/
├── payment-service/
└── notification-service/
```

**워크플로우 예시:**

```yaml
name: microservices-deploy
tasks:
  # 1. 모든 서비스 테스트 (병렬)
  - id: test-user
    command: npm test
    working_directory: $PROJECT_ROOT/services/user-service
    parallel_group: test

  - id: test-order
    command: npm test
    working_directory: $PROJECT_ROOT/services/order-service
    parallel_group: test

  - id: test-payment
    command: npm test
    working_directory: $PROJECT_ROOT/services/payment-service
    parallel_group: test

  # 2. 모든 서비스 빌드 (병렬)
  - id: build-user
    command: docker build -t user-service .
    working_directory: $PROJECT_ROOT/services/user-service
    depends_on: [test-user]
    parallel_group: build

  - id: build-order
    command: docker build -t order-service .
    working_directory: $PROJECT_ROOT/services/order-service
    depends_on: [test-order]
    parallel_group: build

  - id: build-payment
    command: docker build -t payment-service .
    working_directory: $PROJECT_ROOT/services/payment-service
    depends_on: [test-payment]
    parallel_group: build

  # 3. 순차 배포 (의존성 순서)
  - id: deploy-user
    command: kubectl apply -f k8s/
    working_directory: $PROJECT_ROOT/services/user-service
    depends_on: [build-user]

  - id: deploy-order
    command: kubectl apply -f k8s/
    working_directory: $PROJECT_ROOT/services/order-service
    depends_on: [build-order, deploy-user]

  - id: deploy-payment
    command: kubectl apply -f k8s/
    working_directory: $PROJECT_ROOT/services/payment-service
    depends_on: [build-payment, deploy-order]
```

## 공통 패턴

### 의존성 그래프 분석

프로젝트 간 의존성을 자동 분석하여 빌드 순서를 결정합니다.

```yaml
# 자동 의존성 분석 활성화
settings:
  auto_dependency_analysis: true
  dependency_files:
    - package.json
    - requirements.txt
    - go.mod
```

### 변경 감지

변경된 프로젝트만 빌드합니다.

```yaml
settings:
  change_detection: true
  change_detection_base: origin/main

tasks:
  - id: build-changed
    command: npm run build
    condition: "changed_files.includes('packages/frontend/')"
```

### 병렬 제한

리소스 제한을 고려한 병렬 실행입니다.

```yaml
settings:
  max_parallel: 4
  resource_limits:
    memory_per_task: 2GB
    cpu_per_task: 2
```

## 프로젝트 타입별 명령어

### Node.js

```yaml
tasks:
  - id: install
    command: npm ci
  - id: build
    command: npm run build
  - id: test
    command: npm test
```

### Python

```yaml
tasks:
  - id: install
    command: pip install -r requirements.txt
  - id: lint
    command: ruff check .
  - id: test
    command: pytest
```

### Go

```yaml
tasks:
  - id: build
    command: go build ./...
  - id: test
    command: go test ./...
```

### Rust

```yaml
tasks:
  - id: build
    command: cargo build --release
  - id: test
    command: cargo test
```

### Docker

```yaml
tasks:
  - id: build
    command: docker build -t $IMAGE_NAME .
  - id: push
    command: docker push $IMAGE_NAME
```

## 에러 처리

### 개별 프로젝트 실패

```yaml
settings:
  fail_fast: false  # 다른 프로젝트는 계속 실행

tasks:
  - id: build-frontend
    on_failure: continue  # 실패해도 다음 진행
```

### 전체 실패 시 롤백

```yaml
error_strategies:
  rollback:
    - task: deploy-all
      rollback_steps:
        - for svc in user order payment; do
            kubectl rollout undo deployment/$svc
          done
```

## 모니터링

### 진행 상황 추적

```bash
/run-workflow monorepo-build --status
```

출력:
```
워크플로우: monorepo-build
상태: running (3/8 완료)

태스크:
  ✓ install-root (2.5s)
  ✓ build-shared (15.3s)
  ✓ build-utils (12.1s)
  ⏳ build-frontend (실행 중...)
  ⏳ build-backend (실행 중...)
  ○ test-frontend (대기 중)
  ○ test-backend (대기 중)
  ○ deploy (승인 대기)
```

## 베스트 프랙티스

1. **의존성 순서 명확히**: 공유 라이브러리를 먼저 빌드
2. **병렬 그룹 활용**: 독립적인 프로젝트는 병렬로
3. **체크포인트 설정**: 긴 빌드 후 체크포인트 생성
4. **환경 변수 격리**: 프로젝트별 환경 변수 분리
5. **타임아웃 조정**: 프로젝트 크기에 맞는 타임아웃
