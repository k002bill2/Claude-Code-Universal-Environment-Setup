<!-- 출처: docs/Claude code system setup/Agent Skills 예시 모음.md (SKILL.md Resources 참조 항목) -->
# Security Checklist

본 내용은 스킬 정합을 위해 저작됨

SKILL.md `Review Checklist > 2. Security`의 5개 항목을 리뷰 시 대조할 수 있도록 확장한 문서다.
각 항목은 **확인 방법**과 **위반 신호**로 구성되며, 심각도는 `Review Process`의
`issues` 분류(`critical` / `warning` / `suggestion`)와 `Output Format`의 🔴 / 🟡 / 🟢에 대응한다.

## 심각도 기준

| 심각도 | 키 | 출력 | 처리 |
|--------|----|------|------|
| Critical | `critical` | 🔴 Required Changes | 머지 차단. 수정 전 승인 금지 |
| Warning | `warning` | 🟡 Suggestions | 머지 가능하나 이슈 등록 필수 |
| Suggestion | `suggestion` | 🟢 Good Practices | 재량 |

---

## 1. Input validation present

- **확인 방법**: 신뢰 경계(HTTP 핸들러, 메시지 컨슈머, 파일 업로드, CLI 인자)에서
  스키마 검증기로 타입·길이·범위·허용값을 강제하는지 확인한다.
  검증은 경계에 모으고 내부 계층에서 재파싱하지 않는다.
- **위반 신호**
  - 요청 본문을 검증 없이 그대로 도메인 객체나 DB 레이어로 전달
  - 화이트리스트가 아닌 블랙리스트 필터링(`replace("<script>", "")` 류)
  - 클라이언트 검증만 있고 서버 검증이 없음
  - 경로 조작 입력(`../`)을 정규화 없이 파일 경로에 결합
- **심각도**: 외부 입력이 쿼리·명령·파일 경로로 흐르면 **critical**, 내부 전용 경로면 **warning**

## 2. No SQL injection vulnerabilities

- **확인 방법**: 모든 쿼리가 파라미터 바인딩(플레이스홀더)을 쓰는지 확인한다.
  ORM을 쓰더라도 raw 조각을 문자열로 조립하는 지점을 따로 찾는다.
- **위반 신호**

  ```python
  # 🔴 문자열 결합 — 주입 가능
  cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")

  # 🟢 파라미터 바인딩
  cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
  ```

  - 정렬 컬럼·테이블명을 사용자 입력에서 직접 수용(바인딩 불가 → 허용값 매핑 필요)
  - NoSQL에서 사용자 입력 객체를 쿼리 필터로 그대로 전달(연산자 주입)
  - 동일 위험군: OS 명령(`shell=True`), LDAP, XPath, 서버 사이드 템플릿 인젝션
- **심각도**: **critical** (예외 없음)

## 3. Proper authentication/authorization

- **확인 방법**: 인증(누구인가)과 인가(무엇을 할 수 있는가)를 분리해 본다.
  신규·변경된 엔드포인트마다 "인증 필요 여부"와 "리소스 소유자 검증"을 각각 확인한다.
- **위반 신호**
  - 리소스 ID만으로 조회하고 소유자·테넌트 일치를 확인하지 않음(IDOR)
  - 권한 검사가 UI에만 있고 API에는 없음
  - 토큰의 서명·만료·발급자(`iss`)·대상(`aud`) 미검증, 알고리즘 `none` 허용
  - 세션 고정: 로그인 성공 후 세션 식별자를 재발급하지 않음
  - 상태 변경 요청에 CSRF 보호 또는 `SameSite` 쿠키 정책 부재
- **심각도**: 인가 누락·우회는 **critical**, 권한 범위가 필요 이상으로 넓은 설계는 **warning**

## 4. Sensitive data encrypted

- **확인 방법**: 저장 시(at rest)와 전송 시(in transit)를 나눠 확인하고,
  로그·에러 응답·캐시·분석 이벤트로 새는 경로까지 추적한다.
- **위반 신호**
  - 비밀번호를 가역 암호화 또는 범용 해시(MD5/SHA-1)로 저장
    → 비밀번호는 전용 KDF(bcrypt/scrypt/Argon2)로 솔트와 함께 저장
  - 개인정보·토큰·카드번호가 로그, 스택트레이스, URL 쿼리스트링에 노출
  - 평문 통신 허용, 인증서 검증 비활성화(`verify=False`)
  - 에러 응답이 내부 경로·쿼리·스택트레이스를 그대로 반환
- **심각도**: 자격증명·개인정보 평문 노출은 **critical**, 과다 로깅은 **warning**

## 5. No hardcoded secrets

- **확인 방법**: diff 전체에서 키 형태 문자열을 검색하고, 설정이 환경변수·시크릿 매니저로
  주입되는지 확인한다. 테스트 픽스처와 예제 파일도 같은 기준으로 본다.
- **위반 신호**
  - 소스·설정·IaC·CI 워크플로에 API 키, 비밀번호, 개인키, 접속 문자열 리터럴
  - `.env` 실파일이 커밋됨(예제는 `.env.example`에 더미 값만 둔다)
  - 클라이언트 번들에 서버 전용 시크릿이 포함됨
  - 시크릿을 상수로 두고 "나중에 교체" 주석만 남김
- **심각도**: **critical**. 이미 푸시된 경우 코드 제거로 끝내지 말고
  **즉시 키 교체(rotate)** 까지 요구한다.

---

## 리뷰 종료 전 최종 확인

- [ ] 신규·변경 엔드포인트마다 인증·인가 검사를 개별로 확인했다
- [ ] 사용자 입력이 쿼리·명령·파일 경로·템플릿에 닿는 경로를 모두 추적했다
- [ ] diff에 시크릿 리터럴이 없고, 노출 이력이 있으면 교체를 요청했다
- [ ] critical 0건이며, 넘어간 warning은 사유를 리뷰 코멘트로 남겼다
