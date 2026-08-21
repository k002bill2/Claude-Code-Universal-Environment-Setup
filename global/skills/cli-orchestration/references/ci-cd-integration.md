# CI/CD Integration Guide

CLI 오케스트레이션을 CI/CD 파이프라인과 통합하는 가이드입니다.

## 개요

CLI 오케스트레이션 워크플로우는 로컬 개발 환경과 CI/CD 파이프라인에서 동일하게 실행될 수 있습니다.

```
개발 환경                          CI/CD 환경
    │                                  │
    └──► /run-workflow ci-pipeline     │
             │                         │
             ▼                         ▼
    ┌─────────────────────────────────────┐
    │     CLI Orchestration Workflow       │
    │                                      │
    │  install → lint → test → build      │
    └─────────────────────────────────────┘
```

## GitHub Actions 통합

### 기본 워크플로우

```yaml
# .github/workflows/ci.yml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run CI Pipeline
        run: |
          # CLI 오케스트레이션 워크플로우 실행
          npm run workflow:ci
```

### 워크플로우 스크립트

```json
// package.json
{
  "scripts": {
    "workflow:ci": "node scripts/run-workflow.js ci-pipeline",
    "workflow:deploy": "node scripts/run-workflow.js deploy-pipeline"
  }
}
```

### 워크플로우 실행기

```javascript
// scripts/run-workflow.js
const { execSync } = require('child_process');
const fs = require('fs');
const yaml = require('yaml');

const workflowName = process.argv[2];
const workflowFile = `workflows/${workflowName}.yaml`;

if (!fs.existsSync(workflowFile)) {
  console.error(`Workflow not found: ${workflowName}`);
  process.exit(1);
}

const workflow = yaml.parse(fs.readFileSync(workflowFile, 'utf-8'));

// 태스크 실행
async function runTasks(tasks) {
  const completed = new Set();
  const failed = new Set();

  while (completed.size + failed.size < tasks.length) {
    for (const task of tasks) {
      if (completed.has(task.id) || failed.has(task.id)) continue;

      // 의존성 확인
      const deps = task.depends_on || [];
      if (!deps.every(d => completed.has(d))) continue;

      console.log(`\n▶ Running: ${task.name || task.id}`);

      try {
        execSync(task.command, {
          cwd: task.working_directory || '.',
          stdio: 'inherit',
          env: { ...process.env, ...workflow.env, ...task.env }
        });
        completed.add(task.id);
        console.log(`✓ Completed: ${task.id}`);
      } catch (error) {
        failed.add(task.id);
        console.error(`✗ Failed: ${task.id}`);

        if (workflow.settings?.fail_fast) {
          process.exit(1);
        }
      }
    }
  }

  if (failed.size > 0) {
    console.error(`\n${failed.size} task(s) failed`);
    process.exit(1);
  }
}

runTasks(workflow.tasks);
```

## GitLab CI 통합

```yaml
# .gitlab-ci.yml
stages:
  - install
  - validate
  - test
  - build
  - deploy

variables:
  NODE_ENV: production

install:
  stage: install
  script:
    - npm ci
  cache:
    paths:
      - node_modules/

lint:
  stage: validate
  script:
    - npm run lint
  needs: [install]

typecheck:
  stage: validate
  script:
    - npm run typecheck
  needs: [install]

test:
  stage: test
  script:
    - npm test -- --coverage
  needs: [lint, typecheck]
  coverage: '/All files[^|]*\|[^|]*\s+([\d\.]+)/'

build:
  stage: build
  script:
    - npm run build
  needs: [test]
  artifacts:
    paths:
      - dist/

deploy:
  stage: deploy
  script:
    - npm run deploy
  needs: [build]
  when: manual
  only:
    - main
```

## Jenkins 통합

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        NODE_ENV = 'production'
        CI = 'true'
    }

    stages {
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Validate') {
            parallel {
                stage('Lint') {
                    steps {
                        sh 'npm run lint'
                    }
                }
                stage('TypeCheck') {
                    steps {
                        sh 'npm run typecheck'
                    }
                }
            }
        }

        stage('Test') {
            steps {
                sh 'npm test -- --coverage'
            }
        }

        stage('Build') {
            steps {
                sh 'npm run build'
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            input {
                message "Deploy to production?"
                ok "Deploy"
            }
            steps {
                sh 'npm run deploy'
            }
        }
    }

    post {
        failure {
            // 실패 시 알림
            slackSend(
                channel: '#deploys',
                message: "Build failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            )
        }
    }
}
```

## CircleCI 통합

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@5.1.0

jobs:
  install:
    executor: node/default
    steps:
      - checkout
      - node/install-packages

  lint:
    executor: node/default
    steps:
      - checkout
      - node/install-packages
      - run: npm run lint

  typecheck:
    executor: node/default
    steps:
      - checkout
      - node/install-packages
      - run: npm run typecheck

  test:
    executor: node/default
    steps:
      - checkout
      - node/install-packages
      - run: npm test -- --coverage
      - store_test_results:
          path: coverage

  build:
    executor: node/default
    steps:
      - checkout
      - node/install-packages
      - run: npm run build
      - persist_to_workspace:
          root: .
          paths:
            - dist

  deploy:
    executor: node/default
    steps:
      - checkout
      - attach_workspace:
          at: .
      - run: npm run deploy

workflows:
  ci-pipeline:
    jobs:
      - install
      - lint:
          requires: [install]
      - typecheck:
          requires: [install]
      - test:
          requires: [lint, typecheck]
      - build:
          requires: [test]
      - deploy:
          requires: [build]
          filters:
            branches:
              only: main
```

## Docker 통합

### Dockerfile

```dockerfile
# Dockerfile.ci
FROM node:20-alpine

WORKDIR /app

# 의존성 설치
COPY package*.json ./
RUN npm ci

# 소스 복사
COPY . .

# 워크플로우 파일 복사
COPY workflows/ ./workflows/

# CI 파이프라인 실행
CMD ["npm", "run", "workflow:ci"]
```

### docker-compose

```yaml
# docker-compose.ci.yml
version: '3.8'

services:
  ci-runner:
    build:
      context: .
      dockerfile: Dockerfile.ci
    environment:
      - CI=true
      - NODE_ENV=test
    volumes:
      - ./coverage:/app/coverage
      - ./dist:/app/dist
```

## 환경별 설정

### 환경 변수

```yaml
# workflows/ci-pipeline.yaml
env:
  NODE_ENV: $CI_ENVIRONMENT
  API_URL: $API_URL
  DATABASE_URL: $DATABASE_URL
```

### 조건부 태스크

```yaml
tasks:
  - id: deploy-staging
    command: npm run deploy:staging
    condition: "$CI_BRANCH == 'develop'"

  - id: deploy-production
    command: npm run deploy:production
    condition: "$CI_BRANCH == 'main'"
    requires_approval: true
```

## 아티팩트 관리

### 빌드 아티팩트 저장

```yaml
tasks:
  - id: build
    command: npm run build
    artifacts:
      - dist/
      - .next/
      - build/
    artifact_retention: 30d
```

### 테스트 리포트

```yaml
tasks:
  - id: test
    command: npm test -- --coverage
    artifacts:
      - coverage/
      - test-results/
    reports:
      - type: junit
        path: test-results/junit.xml
      - type: coverage
        path: coverage/lcov.info
```

## 알림 설정

### Slack 알림

```yaml
notifications:
  on_success:
    - type: slack
      webhook: $SLACK_WEBHOOK_URL
      channel: "#deploys"
      message: "✅ CI 성공: $WORKFLOW_NAME"

  on_failure:
    - type: slack
      webhook: $SLACK_WEBHOOK_URL
      channel: "#deploys"
      message: "❌ CI 실패: $WORKFLOW_NAME at $FAILED_TASK"
```

### 이메일 알림

```yaml
notifications:
  on_failure:
    - type: email
      to: team@example.com
      subject: "CI 실패: $WORKFLOW_NAME"
```

## 모범 사례

1. **환경 일관성**: 로컬과 CI에서 동일한 워크플로우 사용
2. **캐싱**: 의존성 캐싱으로 빌드 속도 개선
3. **병렬 실행**: 독립적인 태스크는 병렬로
4. **빠른 실패**: lint/typecheck를 먼저 실행
5. **아티팩트 보관**: 빌드 결과물 저장
6. **알림 설정**: 실패 시 즉각 알림
7. **승인 게이트**: 프로덕션 배포 전 수동 승인
