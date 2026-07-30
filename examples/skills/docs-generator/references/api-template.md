<!-- 출처: docs/Claude code system setup/Agent Skills 예시 모음.md (SKILL.md Documentation Types 참조 항목) -->
# API Documentation Template

본 내용은 스킬 정합을 위해 저작됨

SKILL.md `Documentation Types > 1. API Documentation`이 참조하는 템플릿이다.
아래 스캐폴드를 복사한 뒤 `{{ }}` 자리표시자를 실제 값으로 치환하고, 엔드포인트 1개당
"개요 → 파라미터 → 요청(본문이 있으면) → 응답 → 에러 → 예제" 순서를 유지한다.

## 문서 상단 (API 전체 공통, 1회 작성)

````markdown
# {{ API 이름 }} API

- **Base URL**: `{{ https://api.example.com/v1 }}`
- **버전**: `{{ v1 }}` — 버전 정책: {{ URL 경로 버전 / 헤더 버전 }}
- **인증**: `Authorization: Bearer {{ TOKEN }}`
- **Content-Type**: `application/json; charset=utf-8`
- **Rate Limit**: {{ 1000 }} req / {{ 1분 }} — 초과 시 `429`
  (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` 헤더 반환)
````

## 엔드포인트 단위 스캐폴드

엔드포인트 1개는 한 오퍼레이션 스타일만 문서화한다 — 목록 조회는 A, 생성은 B를 골라 복사하고 둘을 섞지 않는다.

### A. 목록 조회 (GET — 요청 본문 없음, `200`)

````markdown
## {{ 엔드포인트 이름 }}

```
{{ GET }} {{ /users/{userId}/orders }}
```

{{ 무엇을 하는지 1~2문장. 부수효과가 있으면 명시한다. }}

- **인증**: {{ 필요 / 불필요 }} · **필요 권한**: `{{ orders:read }}` · **멱등성**: {{ 예 / 아니오 }}

### Parameters

| 위치 | 이름 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|------|--------|------|
| path | `{{ userId }}` | `{{ string(uuid) }}` | 예 | – | {{ 대상 사용자 }} |
| query | `{{ status }}` | `{{ string }}` | 아니오 | `{{ all }}` | {{ 허용값: `paid`, `shipped` }} |
| query | `{{ limit }}` | `{{ integer }}` | 아니오 | `{{ 20 }}` | {{ 1~100 }} |
| query | `{{ cursor }}` | `{{ string }}` | 아니오 | – | {{ 다음 페이지 커서 }} |

### Request Body

없음 — `GET`은 요청 본문을 갖지 않는다. 필터는 위 query 파라미터로 표현한다.

### Responses

| 상태 코드 | 의미 | 본문 |
|-----------|------|------|
| `200` | 성공 | {{ 리소스 목록 + 다음 페이지 커서 }} |
| `400` | 검증 실패 | 에러 객체 |
| `401` / `403` | 인증 실패 / 권한 없음 | 에러 객체 |
| `404` | 대상 없음 | 에러 객체 |
| `429` | 요청 한도 초과 | 에러 객체 |

```json
{
  "items": [
    { "id": "ord_01H8X", "status": "paid", "totalAmount": 32000 }
  ],
  "nextCursor": "eyJpZCI6Im9yZF8wMUg4WCJ9"
}
```

### Error Codes

에러 응답은 아래 형태로 통일한다.

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "quantity must be >= 1",
    "field": "items[0].quantity",
    "requestId": "req_9f2c"
  }
}
```

| `code` | 상태 코드 | 원인 | 해결 |
|--------|-----------|------|------|
| `VALIDATION_FAILED` | `400` | {{ 입력 스키마 불일치 }} | {{ 필드 제약 확인 }} |
| `UNAUTHORIZED` | `401` | {{ 토큰 만료 }} | {{ 토큰 재발급 }} |
| `RATE_LIMITED` | `429` | {{ 한도 초과 }} | {{ `X-RateLimit-Reset` 이후 재시도 }} |

### 예제

```bash
curl "{{ https://api.example.com/v1/users/u_123/orders?status=paid&limit=20 }}" \
  -H "Authorization: Bearer $API_TOKEN"
```

### 변경 이력

| 버전 | 날짜 | 변경 |
|------|------|------|
| `{{ v1.1 }}` | {{ 2026-01-27 }} | {{ `cursor` 파라미터 추가 }} |
````

### B. 생성 (POST — 요청 본문 있음, `201`)

A에서 달라지는 절만 아래로 교체한다. `Parameters`(path 파라미터만 사용) · `Error Codes` · `변경 이력`은 A와 동일하다.

````markdown
## {{ 엔드포인트 이름 }}

```
{{ POST }} {{ /users/{userId}/orders }}
```

{{ 무엇을 하는지 1~2문장. 부수효과가 있으면 명시한다. }}

- **인증**: {{ 필요 }} · **필요 권한**: `{{ orders:write }}` · **멱등성**: {{ 예 / 아니오 }}
  ({{ 예 }}이면 `Idempotency-Key` 헤더 규약을 함께 적는다)

### Request Body

| 필드 | 타입 | 필수 | 제약 | 설명 |
|------|------|------|------|------|
| `{{ items }}` | `{{ array }}` | 예 | {{ 1개 이상 }} | {{ 주문 항목 목록 }} |
| `{{ items[].sku }}` | `{{ string }}` | 예 | – | {{ 상품 코드 }} |

```json
{
  "items": [{ "sku": "ABC-123", "quantity": 2 }],
  "note": "문 앞에 놓아주세요"
}
```

### Responses

| 상태 코드 | 의미 | 본문 |
|-----------|------|------|
| `201` | 생성됨 | {{ 생성된 리소스 객체 }} — `Location` 헤더에 리소스 URI |
| `400` / `401` / `403` / `404` / `429` | A와 동일 | 에러 객체 |

```json
{
  "id": "ord_01H8X",
  "status": "paid",
  "totalAmount": 32000,
  "createdAt": "2026-01-27T09:15:00Z"
}
```

### 예제

```bash
curl -X {{ POST }} "{{ https://api.example.com/v1/users/u_123/orders }}" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"sku":"ABC-123","quantity":2}]}'
```
````

## 작성 체크리스트

- [ ] 모든 파라미터에 타입·필수 여부·기본값·제약을 적었다
- [ ] 성공 응답과 주요 에러 응답 예제를 넣었고 `code` 값이 구현과 일치한다
- [ ] 복사해서 바로 실행되는 `curl` 예제가 있으며, 파괴적 변경은 버전 이력에 표시했다
