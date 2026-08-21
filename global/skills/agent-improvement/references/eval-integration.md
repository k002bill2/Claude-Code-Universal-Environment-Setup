# Eval 시스템 연동 — Eval-Driven Improvement

평가 시스템 (`.claude/evals/`)의 결과를 활용해 에이전트를 데이터 기반으로 개선하는 루프. SKILL.md "Eval 연동" 섹션에서 referenced.

## Eval-Driven Improvement Cycle

```
1. RUN EVALS          → /run-eval --all --k=3
2. ANALYZE METRICS    → pass@k < 0.8 태스크 식별
3. DIAGNOSE FAILURES  → grader 피드백·트랜스크립트 리뷰
4. PROPOSE IMPROVE    → 에이전트 프롬프트·루브릭·태스크 정의
5. VALIDATE CHANGES   → 영향받은 태스크 재실행
6. DEPLOY IF IMPROVED → 에이전트 정의 업데이트
```

## 저성능 태스크 분석 템플릿

```markdown
### Task: task_ui_002 (pass@3: 0.67)

**실패 패턴**:
- Run 1: 접근성 레이블 누락 (grader: has_accessibility_label FAIL)
- Run 3: TypeScript 에러 (grader: typescript_compiles FAIL)

**근본 원인**:
- web-ui-specialist 프롬프트에 접근성 명시 부족
- 참조 파일에 접근성 예시 없음

**개선 제안**:
1. web-ui-specialist 프롬프트에 접근성 체크리스트 추가
2. 참조 파일 목록에 접근성 구현 예시 추가
3. code-quality 루브릭에 접근성 가중치 상향
```

## Grader 피드백 패턴 스키마

```json
{
  "pattern_id": "eval_pat_001",
  "source": "eval_grader",
  "task_category": "ui_component",
  "frequency": 5,
  "feedback_pattern": "Performance could be improved with memo()",
  "proposed_fix": {
    "target": "web-ui-specialist",
    "change": "Add memo() reminder to CRITICAL REMINDERS section"
  }
}
```

## 루브릭 캘리브레이션

LLM 채점과 코드 채점 간 불일치 해결:

```markdown
### 문제: Performance 점수 불일치
- 코드 검사: PASS (memo() 없어도 통과)
- LLM 평가: 3/5 (memo() 없으면 감점)

### 해결:
1. 코드 검사에 `has_memo` 체크 추가
2. 또는 LLM 루브릭에서 memo()를 권장 사항으로 조정

### 적용:
`.claude/evals/rubrics/code-quality.md` 수정
```

## 자동화 워크플로우

```bash
# 1. 전체 평가 실행
/run-eval --all --k=3

# 2. 저성능 태스크 확인
cat .claude/evals/results/*/summary.json | jq '.low_performers'

# 3. 개선 제안 생성 (agent-improvement가 분석)

# 4. 변경 적용 후 재평가
/run-eval task_ui_002 --k=3

# 5. 개선 확인 (pass@3: 0.67 → 0.90)
```

## Eval 메트릭 목표

| 메트릭 | 대상 | 현재 | 목표 |
|--------|------|------|------|
| 평균 pass@1 | 전체 | 0.85 | 0.90 |
| 평균 pass@3 | 전체 | 0.92 | 0.95 |
| 저성능 태스크 수 | pass@3 < 0.8 | 3 | 0 |
| LLM 평균 점수 | 전체 | 0.78 | 0.85 |

## Quick Commands

```bash
# Eval 결과 요약
cat .claude/evals/results/$(date +%Y-%m-%d)/summary.json | jq '.metrics'

# 저성능 태스크 목록
cat .claude/evals/results/*/summary.json | jq '.low_performers[]'

# 특정 태스크 grader 피드백
cat .claude/evals/results/*/task_ui_001.json | jq '.runs[].grades.llm_evaluation.feedback'

# 카테고리별 pass@k 통계
cat .claude/evals/results/*/summary.json | jq '.by_category'
```

## 관련 자산

- Eval Task Runner: `../../agents/eval-task-runner.md`
- Eval Grader: `../../agents/eval-grader.md`
- Rubrics: `../../evals/rubrics/`
- Task Definitions: `../../evals/tasks/`
