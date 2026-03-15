---
name: run-workflow
description: YAML 기반 워크플로우를 실행하는 슬래시 커맨드
argument-hint: "<name> [--list | --status | --resume | --abort | --dry-run]"
disable-model-invocation: true
---

# /run-workflow

YAML 기반 워크플로우를 실행하는 슬래시 커맨드입니다.

## 사용법

```bash
/run-workflow <name>              # 워크플로우 실행
/run-workflow --list              # 워크플로우 목록
/run-workflow --status            # 실행 중인 워크플로우
/run-workflow <name> --resume     # 체크포인트에서 재개
/run-workflow <name> --abort      # 실행 중단
/run-workflow <name> --dry-run    # 실행 시뮬레이션
```

## 워크플로우 위치

```
~/.claude/cli-orchestration/workflows/
```

## 실행 프로세스

### 1. 워크플로우 로드

```bash
WORKFLOW_DIR=~/.claude/cli-orchestration/workflows
WORKFLOW_FILE=$WORKFLOW_DIR/$1.yaml

# 파일 존재 확인
if [ ! -f "$WORKFLOW_FILE" ]; then
    echo "워크플로우를 찾을 수 없습니다: $1"
    echo "사용 가능한 워크플로우:"
    ls -1 $WORKFLOW_DIR/*.yaml 2>/dev/null | xargs -I{} basename {} .yaml
    exit 1
fi
```

### 2. DAG 분석

워크플로우를 파싱하여 의존성 그래프를 구축합니다:

```yaml
# 토폴로지컬 정렬
# 1. 의존성 없는 노드 찾기
# 2. 병렬 실행 가능한 그룹 식별
# 3. 실행 순서 결정
```

### 3. 실행

```
cli-orchestrator 에이전트가 워크플로우를 조율합니다:

1. 워크플로우 YAML 파싱
2. 의존성 그래프 구축
3. 토폴로지컬 정렬
4. 레벨별 병렬 실행
5. 조건 평가 및 분기
6. 결과 집계 및 리포트
```

## 예시

### 기본 실행

```bash
/run-workflow full-stack-build
```

### 체크포인트에서 재개

```bash
/run-workflow full-stack-build --resume
```

### 특정 체크포인트에서 재개

```bash
/run-workflow full-stack-build --checkpoint cp_build_20250131
```

### 실패한 태스크 건너뛰기

```bash
/run-workflow full-stack-build --resume --skip integration-tests
```

### 상태 확인

```bash
/run-workflow --status
```

## 옵션

| 옵션 | 설명 |
|------|------|
| `--list` | 사용 가능한 워크플로우 목록 |
| `--status` | 실행 중인 워크플로우 상태 |
| `--resume` | 마지막 체크포인트에서 재개 |
| `--checkpoint <id>` | 특정 체크포인트에서 재개 |
| `--skip <task>` | 특정 태스크 건너뛰기 |
| `--abort` | 실행 중인 워크플로우 중단 |
| `--dry-run` | 실행 시뮬레이션 (실제 실행 안함) |
| `--parallel <n>` | 최대 병렬 실행 수 (기본: 4) |
| `--timeout <s>` | 태스크별 타임아웃 (기본: 300s) |

## 에이전트 연동

이 커맨드는 다음 에이전트를 활용합니다:

| 에이전트 | 역할 |
|----------|------|
| `cli-orchestrator` | 워크플로우 파싱, 의존성 분석, 스케줄링, 결과 집계 |
| `cli-worker` | 개별 태스크 실행, 결과 수집, 진행 보고 |

## 실행 흐름

```
/run-workflow full-stack-build
        │
        ▼
┌─────────────────┐
│ cli-orchestrator │  ← 워크플로우 로드 & 의존성 분석
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌────────┐
│worker-1│ │worker-2│  ← 병렬 실행 (parallel_group)
└────┬───┘ └───┬────┘
     │         │
     └────┬────┘
          ▼
     ┌────────┐
     │worker-3│  ← 순차 실행 (depends_on)
     └────┬───┘
          ▼
     [사용자 승인]  ← requires_approval: true
          ▼
     ┌────────┐
     │worker-4│
     └────────┘
```

## 에러 처리

| 전략 | 설명 |
|------|------|
| `retry` | N회 재시도 후 실패 |
| `fallback` | 대체 명령어 실행 |
| `rollback` | 이전 상태로 복원 |
| `skip` | 실패 무시하고 계속 |
| `abort` | 즉시 중단 |

## 참조

- [워크플로우 템플릿](~/.claude/cli-orchestration/workflows/template.yaml)
- [CLI Orchestration Skill](~/.claude/skills/cli-orchestration/SKILL.md)
- [cli-orchestrator 에이전트](~/.claude/agents/cli-orchestrator.md)
- [cli-worker 에이전트](~/.claude/agents/cli-worker.md)
