# Coding Style

- Immutability 우선 — 정전: golden-principles.md. 항상 새 객체를 반환하고 입력을 변경하지 않는다.
- 파일 구성: 타입별이 아닌 기능/도메인별. 많은 작은 파일 > 큰 파일 (높은 응집도, 낮은 결합도). 파일 200-400줄 권장, 크기 한도 SSOT = golden-principles.md (함수 50·파일 800·네스팅 4).
- 경계에서 입력 검증 — 정전: golden-principles.md (zod, Pydantic). 백엔드 패턴은 aos-backend.md.
- 에러는 컨텍스트를 담아 로깅하고 사용자 친화적 메시지로 다시 던진다.
- 커밋 전 정리: 디버깅 잔재(console.log 등)·하드코딩 값 제거.
