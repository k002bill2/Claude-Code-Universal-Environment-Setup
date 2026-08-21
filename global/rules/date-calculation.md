# Date & Time Calculation (CRITICAL)

## 절대 규칙

날짜/시간을 절대 머릿속으로 계산하지 마라. 항상 시스템 도구를 사용하라.

LLM은 날짜 산술에서 자주 틀린다. 요일, 기간, D-Day, 윤년, 월말 등 모든 날짜 계산에 Bash 또는 Python 사용.

## 필수 패턴

### 요일 확인 (macOS)
```bash
date -j -f '%Y-%m-%d' '2026-03-15' '+%A'
```

### N일 후 (macOS)
```bash
date -j -v+30d '+%Y-%m-%d %A'    # 30일 후
date -j -v-7d '+%Y-%m-%d %A'     # 7일 전
```

### 복잡한 날짜 계산 (Python)
```bash
python3 -c "
from datetime import datetime, timedelta
d1 = datetime(2026, 2, 6)
d2 = datetime(2026, 12, 31)
print(f'{(d2-d1).days} days')
"
```

## 금지

- 날짜 암산
- 요일 추측
- 수동 영업일 계산
