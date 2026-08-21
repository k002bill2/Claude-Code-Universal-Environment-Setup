---
name: agent-improvement
description: Self-improvement loop for multi-agent workflows. Diagnose failures, improve tool descriptions, and learn from success/failure patterns.
user-invocable: false
---

# Agent Self-Improvement

## Purpose

다중 에이전트 워크플로우의 지속적 개선:
- 실패 패턴 분석
- 도구 설명 최적화
- 성공 패턴 인식
- 성능 벤치마킹

**근거**: Anthropic은 LLM 기반 도구 설명 개선으로 40% 빠른 태스크 완료를 달성.

## Improvement Cycle

```
1. COLLECT   → 완료 세션의 트레이스 수집
2. ANALYZE   → 실패 패턴 / 병목 식별
3. DIAGNOSE  → LLM으로 근본 원인 이해
4. IMPROVE   → 도구 설명 / 에이전트 프롬프트 갱신
5. VALIDATE  → 유사 태스크에서 검증
6. DEPLOY    → 전체 에이전트에 적용
```

## 작업별 진입점

| 하고 싶은 일 | 참고 |
|--------------|------|
| 트레이스/패턴 JSON 스키마 | [references/manual-loop.md](references/manual-loop.md) §Data Schemas |
| 실패/병목 분석 리포트 작성 | [references/manual-loop.md](references/manual-loop.md) §Analysis Templates |
| 도구 설명·프롬프트·delegation 개선 템플릿 | [references/manual-loop.md](references/manual-loop.md) §Improvement Actions |
| Eval 결과 기반 개선 루프 (`/run-eval`) | [references/eval-integration.md](references/eval-integration.md) |
| 저성능 태스크 분석 / 루브릭 조정 | [references/eval-integration.md](references/eval-integration.md) |

## Validation Protocol

### Before Deployment

1. **테스트 케이스 식별**: 과거 유사 태스크 + 합성 시나리오
2. **A/B 비교 실행**: 원본 vs 개선 프롬프트 — success rate · 반복 · 토큰 · 시간 측정
3. **품질 기준**: 1개 이상 메트릭 개선 + 어떤 메트릭도 5% 이상 회귀 금지

### Validation Report 템플릿

```markdown
### Change: Added accessibility reminder to web-ui-specialist

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Accessibility issues | 12% | 2% | -83% |
| Success rate | 88% | 96% | +9% |
| Token usage | 45K | 47K | +4% |

### Verdict: APPROVE
```

## Storage Structure

```
.temp/improvement/
├── patterns/
│   ├── failures/pat_{id}.json
│   └── successes/pat_{id}.json
├── proposals/prop_{id}.md
├── validations/val_{id}.json
└── history/{date}/changes.json
```

## Integration

### Periodic Review (Weekly)
1. 지난 주 트레이스 집계
2. 실패 분석 실행
3. 개선 제안 생성
4. impact × frequency 우선순위
5. 상위 3개 구현
6. 머지 전 검증

### Continuous Learning (세션마다)
- 실패 → failure patterns 추가
- 성공 but 느림 → bottleneck analysis 추가
- 최적 성공 → success patterns 추가
- 실패 패턴 빈도 > 5 → 개선 제안 트리거

## Metrics

### Agent Performance

| Metric | Target | Current | Trend |
|--------|--------|---------|-------|
| Success rate | >95% | 92% | ↑ |
| Avg iterations | <2 | 2.3 | → |
| Token efficiency | <80K | 75K | ↓ |
| Time to complete | <10min | 12min | ↑ |

### Improvement Impact

| Change | Implemented | Impact |
|--------|-------------|--------|
| Accessibility reminder | 2025-01-01 | -83% issues |
| Tool description update | 2025-01-02 | +5% success |
| Delegation template | 2025-01-03 | -20% iterations |

## Best Practices

1. **Small, Targeted Changes** — 한 번에 하나, 명확한 before/after, 롤백 준비
2. **Data-Driven** — frequency > 5 후 행동, 실제 태스크로 검증, 영향 측정
3. **Preserve What Works** — 성공 패턴 변경 금지, 변경 사유 문서화
4. **Human Review** — 큰 변경은 승인 필요, 엣지 케이스는 인간 판단

## Quick Commands

```bash
# 실패 패턴 보기
cat .temp/improvement/patterns/failures/*.json | jq '.description'

# 패턴 개수
ls .temp/improvement/patterns/failures/ | wc -l

# 대기 중 제안
cat .temp/improvement/proposals/*.md

# 개선 이력
cat .temp/improvement/history/*/changes.json | jq '.'
```

---

**Version**: 1.2 (Skills 2.0 migration) | **Eval Integration**: see `references/eval-integration.md`
