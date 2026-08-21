---
name: agent-observability
description: Production tracing and metrics for multi-agent workflows. Track agent decisions, tool calls, and performance without monitoring conversation content.
user-invocable: false
---

# Agent Observability

## Purpose

다중 에이전트 워크플로우의 체계적 진단:
- Agent 결정 패턴 추적
- 인터랙션 구조 분석
- 성능 메트릭 수집
- 에러 패턴 식별

**중요**: 행동만 추적, 내용은 추적하지 않음. 사용자 프라이버시 존중.

## KPIs

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Agent success rate | >90% | <80% | <60% |
| Avg tools per agent | 10-20 | >30 | >50 |
| Iteration count | 1-2 | 3 | >4 |
| Token efficiency | <100K | >150K | >200K |
| Time to completion | <15min | >30min | >60min |

## 언제 쓰나

- 다중 에이전트 세션의 실행 시간 / 토큰 사용량 / 도구 호출 횟수를 정량적으로 측정할 때
- 실패 세션을 분석하고 에러 패턴(클러스터링, 결정 경로, 성능 이상치)을 진단할 때
- KPI 임계치(위 표)와 비교해 Warning/Critical 이상치를 식별할 때
- 성공 세션의 재사용 가능한 에이전트 조합/위임 패턴을 추출할 때
- 분석 결과를 `agent-improvement` 스킬로 전달하기 전 데이터를 수집할 때

## 상세 이벤트 스키마 / 메트릭

이벤트 8종 스키마 표, 이벤트별 상세 데이터 스키마, 이벤트/JSONL 포맷, Trace Storage 구조,
세션 메트릭 JSON 상세, 분석 패턴(Failure Diagnosis / Success Patterns), Privacy 규칙,
Integration 절차, Quick Commands, Example Trace Summary는 모두 아래 참조:

[references/event-schemas.md](references/event-schemas.md)

---

**Version**: 1.1 (Skills 2.0 migration)
