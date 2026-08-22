# Topological Sort Algorithm

DAG 워크플로우의 최적 실행 순서를 결정하는 토폴로지컬 정렬 알고리즘입니다.

## 개요

토폴로지컬 정렬은 DAG(Directed Acyclic Graph)의 모든 노드를 의존성 순서대로 나열하는 알고리즘입니다. CLI 오케스트레이션에서는 이를 통해:

1. **실행 순서 결정**: 어떤 작업을 먼저 실행해야 하는지 결정
2. **병렬 실행 그룹 식별**: 동시에 실행 가능한 작업 그룹 식별
3. **순환 의존성 감지**: 잘못된 워크플로우 정의 감지

## 알고리즘

### Kahn's Algorithm (BFS 기반)

```
1. 모든 노드의 진입 차수(in-degree) 계산
2. 진입 차수가 0인 노드를 큐에 추가
3. 큐에서 노드를 꺼내 결과에 추가
4. 해당 노드에서 나가는 간선 제거 (연결된 노드의 진입 차수 감소)
5. 진입 차수가 0이 된 노드를 큐에 추가
6. 큐가 빌 때까지 3-5 반복
7. 결과 노드 수가 전체 노드 수와 같으면 성공, 아니면 순환 존재
```

### 의사 코드

```python
def topological_sort(dag):
    # 1. 진입 차수 계산
    in_degree = {node.id: 0 for node in dag.nodes}
    for node in dag.nodes:
        for dep in node.depends_on:
            in_degree[node.id] += 1

    # 2. 진입 차수가 0인 노드 큐에 추가
    queue = [node for node in dag.nodes if in_degree[node.id] == 0]
    result = []

    while queue:
        # 3. 노드 꺼내서 결과에 추가
        node = queue.pop(0)
        result.append(node)

        # 4. 연결된 노드의 진입 차수 감소
        for next_node in dag.nodes:
            if node.id in next_node.depends_on:
                in_degree[next_node.id] -= 1

                # 5. 진입 차수가 0이 되면 큐에 추가
                if in_degree[next_node.id] == 0:
                    queue.append(next_node)

    # 7. 순환 검사
    if len(result) != len(dag.nodes):
        raise Error("Cycle detected")

    return result
```

## 실행 레벨 (Parallel Levels)

동시에 실행 가능한 노드들을 "레벨"로 그룹화합니다.

### 레벨 계산 알고리즘

```
1. 의존성이 없는 노드 = Level 0
2. 각 노드의 레벨 = max(의존하는 노드들의 레벨) + 1
```

### 예시

```yaml
nodes:
  - id: install          # Level 0
  - id: lint             # Level 1 (install에 의존)
    depends_on: [install]
  - id: typecheck        # Level 1 (install에 의존)
    depends_on: [install]
  - id: test             # Level 2 (lint, typecheck에 의존)
    depends_on: [lint, typecheck]
  - id: build            # Level 3 (test에 의존)
    depends_on: [test]
```

**결과:**

| Level | Nodes | 실행 방식 |
|-------|-------|----------|
| 0 | install | 순차 |
| 1 | lint, typecheck | 병렬 |
| 2 | test | 순차 |
| 3 | build | 순차 |

## 실행 전략

### 1. 레벨별 순차 실행

각 레벨 내에서는 병렬로, 레벨 간에는 순차로 실행합니다.

```
[Level 0] install
    ↓
[Level 1] lint || typecheck  (병렬)
    ↓
[Level 2] test
    ↓
[Level 3] build
```

### 2. 최대 동시성 제한

동시 실행 수를 제한하면서 최적화합니다.

```yaml
# max_concurrent: 3
[Time 1] install
[Time 2] lint, typecheck        # 2개 병렬 (limit 내)
[Time 3] test
[Time 4] build
```

### 3. 우선순위 기반 스케줄링

크리티컬 패스 또는 예상 실행 시간 기반으로 우선순위를 부여합니다.

```yaml
# 긴 작업 우선 시작
nodes:
  - id: slow-test       # 예상 10분, 우선 시작
    estimated_time: 600000
  - id: fast-lint       # 예상 30초
    estimated_time: 30000
```

## 동적 스케줄링

실행 중 노드 완료 시점에 다음 실행 가능한 노드를 동적으로 결정합니다.

```
1. 완료된 노드 X
2. X를 의존하는 모든 노드 Y 확인
3. Y의 모든 의존성이 완료되었으면 Y 실행 가능
4. 실행 가능한 노드 중 max_concurrent 내에서 실행
```

### 의사 코드

```python
def dynamic_schedule(dag, max_concurrent):
    completed = set()
    running = set()
    ready = {n for n in dag.nodes if not n.depends_on}

    while ready or running:
        # 실행 가능한 노드 시작
        while ready and len(running) < max_concurrent:
            node = ready.pop()
            start_execution(node)
            running.add(node)

        # 완료 대기
        finished = wait_for_any(running)

        # 완료 처리
        for node in finished:
            running.remove(node)
            completed.add(node)

            # 새로 실행 가능해진 노드 확인
            for next_node in dag.nodes:
                if node.id in next_node.depends_on:
                    deps_completed = all(
                        dep in [c.id for c in completed]
                        for dep in next_node.depends_on
                    )
                    if deps_completed:
                        ready.add(next_node)
```

## 순환 의존성 감지

### DFS 기반 감지

```python
def detect_cycle(dag):
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n.id: WHITE for n in dag.nodes}

    def dfs(node):
        color[node.id] = GRAY

        for next_node in dag.nodes:
            if node.id in next_node.depends_on:
                continue  # 역방향
            if next_node.id in node.depends_on:
                if color[next_node.id] == GRAY:
                    return True  # 순환 발견
                if color[next_node.id] == WHITE:
                    if dfs(next_node):
                        return True

        color[node.id] = BLACK
        return False

    for node in dag.nodes:
        if color[node.id] == WHITE:
            if dfs(node):
                return True
    return False
```

## CLI Orchestration 적용

### Agent 도구와의 통합

```yaml
# 실행 계획 생성
execution_plan:
  - level: 0
    tasks:
      - task_id: "task_1"
        command: "npm ci"
        mode: sequential

  - level: 1
    tasks:
      - task_id: "task_2"
        command: "npm run lint"
        mode: parallel
      - task_id: "task_3"
        command: "npm run typecheck"
        mode: parallel
```

### 진행 상황 추적

```yaml
progress:
  total_nodes: 6
  completed: 3
  running: 2
  pending: 1
  current_level: 2

  nodes:
    - id: install
      status: completed
      duration: 45000
    - id: lint
      status: completed
      duration: 12000
    - id: typecheck
      status: running
      started_at: "2024-01-05T10:00:00Z"
```
