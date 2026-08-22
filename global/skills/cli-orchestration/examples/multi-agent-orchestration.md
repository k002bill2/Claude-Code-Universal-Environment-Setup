# Multi-Agent Orchestration Example

여러 전문 에이전트를 조율하는 실제 워크플로우 예시입니다.

## 시나리오

PR 코드 리뷰 자동화:
- 테스트 커버리지 분석
- 성능 영향 분석
- 타입 안전성 검증
- 코드 품질 점수 계산

## 전체 아키텍처

```
                   CLI Orchestration Skill
                          │
           ┌──────────────┼──────────────┐
           ↓              ↓              ↓
   test-automation   performance    backend-integration
    -specialist       -optimizer      -specialist
           │              │              │
           └──────────────┼──────────────┘
                          ↓
                   Result Aggregation
                          │
                          ↓
                    PR Review Comment
```

## Step 1: 작업 정의

### CLI 명령

```bash
"PR #156 코드 리뷰 해줘"
```

### 오케스트레이션 설정

```yaml
orchestration:
  name: "pr-code-review"
  pr_number: 156

  context:
    # PR 정보 수집
    pr_info:
      title: "feat: 새로운 체크아웃 플로우"
      branch: "feature/checkout-v2"
      files_changed: 23
      additions: 847
      deletions: 156

    changed_files:
      - "src/components/Checkout/**/*.tsx"
      - "src/hooks/useCheckout.ts"
      - "src/services/payment.ts"
      - "tests/**/*.test.ts"
```

## Step 2: 병렬 에이전트 위임

### 위임 정의

```yaml
delegation:
  parallel: true
  timeout: 300000

  tasks:
    # 1. 테스트 분석
    - agent: "test-automation-specialist"
      task: |
        PR #156의 테스트 커버리지를 분석하세요.

        ## 작업
        1. 변경된 파일의 테스트 커버리지 확인
        2. 누락된 테스트 케이스 식별
        3. 테스트 품질 평가

        ## 변경된 파일
        - src/components/Checkout/**/*.tsx
        - src/hooks/useCheckout.ts
        - src/services/payment.ts

        ## 기대 출력
        - 커버리지 퍼센트
        - 누락된 테스트 목록
        - 권장 사항

      input:
        pr_number: 156
        coverage_threshold: 80

    # 2. 성능 분석
    - agent: "general-purpose"
      task: |
        PR #156의 성능 영향을 분석하세요.

        ## 작업
        1. 번들 크기 변화 측정
        2. 렌더링 성능 영향 분석
        3. 메모리 사용량 예측

        ## 기대 출력
        - 번들 크기 변화량
        - 성능 점수
        - 최적화 권장 사항

      input:
        base_branch: "main"
        pr_branch: "feature/checkout-v2"

    # 3. 타입 안전성 검증
    - agent: "api-architect"
      task: |
        PR #156의 타입 안전성을 검증하세요.

        ## 작업
        1. TypeScript 엄격 모드 체크
        2. API 타입 호환성 검증
        3. any 타입 사용 검출

        ## 기대 출력
        - 타입 에러 수
        - any 타입 사용 위치
        - 타입 개선 제안

      input:
        strict_mode: true
```

## Step 3: 에이전트 실행 모니터링

### 실시간 진행 상황

```
Multi-Agent Orchestration: PR #156 Code Review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Agents:
[▶] test-automation-specialist   Running (1m 23s)
    └─ Analyzing coverage for 23 files...

[▶] general-purpose        Running (58s)
    └─ Measuring bundle size diff...

[✓] api-architect  Completed (45s)
    └─ 0 type errors found

Progress: 1/3 completed
Estimated remaining: ~2 minutes
```

## Step 4: 결과 수집

### 개별 에이전트 결과

#### test-automation-specialist

```yaml
agent: test-automation-specialist
status: success
duration: 95000

output:
  test_results:
    total: 156
    passed: 156
    failed: 0

  coverage:
    overall: 78.5
    changed_files:
      "src/components/Checkout/CheckoutForm.tsx": 85
      "src/hooks/useCheckout.ts": 72
      "src/services/payment.ts": 68

  missing_tests:
    - file: "src/hooks/useCheckout.ts"
      function: "handlePaymentError"
      reason: "Error handling path not tested"

    - file: "src/services/payment.ts"
      function: "validateCard"
      reason: "Edge cases not covered"

  recommendations:
    - "useCheckout hook에 에러 핸들링 테스트 추가 필요"
    - "payment service의 validateCard 엣지 케이스 테스트 추가 권장"
```

#### general-purpose

```yaml
agent: general-purpose
status: success
duration: 72000

output:
  bundle_analysis:
    before: 234500
    after: 238200
    diff: +3700
    diff_percent: +1.58%

  chunk_analysis:
    new_chunks:
      - name: "checkout-v2"
        size: 12400

  performance_score: 92

  recommendations:
    - "Checkout 컴포넌트 lazy loading 적용 권장"
    - "payment service를 별도 청크로 분리 가능"
```

#### api-architect

```yaml
agent: api-architect
status: success
duration: 45000

output:
  type_check:
    errors: 0
    warnings: 2

  any_usage:
    count: 0
    locations: []

  api_compatibility:
    status: "compatible"
    breaking_changes: []

  improvements:
    - file: "src/services/payment.ts:45"
      suggestion: "PaymentResult 타입을 더 구체적으로 정의 가능"
```

## Step 5: 결과 집계

### 집계 로직

```yaml
aggregation:
  strategy: collect_all

  scoring:
    # 가중치 적용
    test_coverage:
      value: 78.5
      weight: 0.35
      score: 78.5

    performance:
      value: 92
      weight: 0.30
      score: 92

    type_safety:
      value: 100  # 에러 0개
      weight: 0.35
      score: 100

    # 최종 점수
    final_score: 89.5  # (78.5*0.35 + 92*0.30 + 100*0.35)

  action_items:
    priority_order:
      - severity: high
      - severity: medium
      - severity: low
```

### 집계 결과

```yaml
aggregated_result:
  overall:
    status: "approved_with_suggestions"
    quality_score: 89.5
    agents_completed: 3
    agents_failed: 0

  summary:
    test_coverage: "78.5% (target: 80%)"
    bundle_size: "+3.7KB (+1.58%)"
    type_errors: 0
    performance_score: "92/100"

  action_items:
    - priority: high
      category: "test"
      description: "커버리지가 80% 미만입니다 (78.5%)"
      suggestion: "useCheckout, payment service 테스트 추가 필요"

    - priority: medium
      category: "performance"
      description: "번들 크기 3.7KB 증가"
      suggestion: "Checkout 컴포넌트 lazy loading 검토"

    - priority: low
      category: "type"
      description: "PaymentResult 타입 개선 가능"
      suggestion: "더 구체적인 타입 정의 권장"
```

## Step 6: PR 리뷰 코멘트 생성

### 생성된 리뷰 코멘트

```markdown
## 🤖 AI Code Review - PR #156

### Quality Score: 89.5/100 ⭐

---

### 📊 Test Coverage

| Metric | Value | Status |
|--------|-------|--------|
| Overall | 78.5% | ⚠️ Below target (80%) |
| CheckoutForm.tsx | 85% | ✅ |
| useCheckout.ts | 72% | ⚠️ |
| payment.ts | 68% | ⚠️ |

**Missing Tests:**
- `useCheckout.ts` - `handlePaymentError` function needs error handling tests
- `payment.ts` - `validateCard` edge cases not covered

---

### 📦 Bundle Analysis

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Total Size | 234.5KB | 238.2KB | +3.7KB (+1.58%) |

**New Chunks:**
- `checkout-v2`: 12.4KB

**Recommendation:** Consider lazy loading for Checkout component

---

### 🔒 Type Safety

✅ **0 type errors**
✅ **No `any` usage detected**
✅ **API compatibility verified**

**Suggestion:** Consider more specific type for `PaymentResult` in payment.ts:45

---

### 📋 Action Items

| Priority | Category | Action |
|----------|----------|--------|
| 🔴 High | Test | Add tests for error handling in useCheckout |
| 🟡 Medium | Performance | Consider lazy loading for Checkout |
| 🟢 Low | Type | Improve PaymentResult type definition |

---

<details>
<summary>📈 Detailed Metrics</summary>

- Test execution time: 95s
- Performance analysis: 72s
- Type checking: 45s
- Total review time: 3m 32s

</details>

---

*Generated by CLI Orchestration Skill v3.0*
*Reviewed by: test-automation-specialist, general-purpose, api-architect*
```

## CLI 실행 요약

```
PR #156 Code Review Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Quality Score: 89.5/100 ⭐

Summary:
├─ Test Coverage: 78.5% (⚠️ below 80%)
├─ Bundle Size: +3.7KB (+1.58%)
├─ Type Errors: 0 ✅
└─ Performance: 92/100 ✅

Action Items: 3
├─ 🔴 High: 1
├─ 🟡 Medium: 1
└─ 🟢 Low: 1

Review comment posted to PR #156 ✅

Agents Used:
├─ test-automation-specialist (95s)
├─ general-purpose (72s)
└─ api-architect (45s)

Total Time: 3m 32s
```

## 후속 작업

### 자동 트리거

```yaml
automation:
  on_pr_update:
    # PR 업데이트 시 재실행
    trigger: "code-review"
    conditions:
      - files_changed: true
      - ready_for_review: true

  on_review_approval:
    # 리뷰 승인 시 머지 준비
    trigger: "merge-preparation"
```

### 수동 재실행

```bash
# 특정 에이전트만 재실행
"PR #156 테스트 커버리지만 다시 분석해줘"

# 전체 재실행
"PR #156 코드 리뷰 다시 해줘"
```
