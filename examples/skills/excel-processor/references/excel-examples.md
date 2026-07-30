<!-- 출처: docs/Claude code system setup/Agent Skills 예시 모음.md (SKILL.md Usage Examples 참조 항목) -->
# Excel Examples

본 내용은 스킬 정합을 위해 저작됨

SKILL.md `Usage Examples`가 참조하는 문서로, `Core Functions`의 `read_excel_with_formulas` ·
`create_pivot_table` · `validate_and_clean_data` 를 호출하는 종단 간 패턴과, `Capabilities`에
있으나 코드가 없는 차트·조건부 서식·다중 시트·VLOOKUP 사용법을 담는다. 임포트는
SKILL.md `Dependencies` 블록을 그대로 사용한다.

## 0. 수식 읽기 — 먼저 알아야 할 것

openpyxl 셀에는 `cell.formula` 속성이 없다. 수식과 계산값은 **로드 모드로 구분**한다.

```python
wb_formula = openpyxl.load_workbook("report.xlsx", data_only=False)
cell = wb_formula["Sales"]["D2"]
print(cell.value)       # '=B2*C2'  ← 수식 문자열 자체
print(cell.data_type)   # 'f'       ← 수식 셀 판별
wb_cached = openpyxl.load_workbook("report.xlsx", data_only=True)
print(wb_cached["Sales"]["D2"].value)   # 32000 ← Excel이 저장 시 캐시한 계산값
```

> `data_only=True`의 값은 **Excel이 저장 시 캐시한 결과**다. 파일을 Excel로 연 적이 없거나
> openpyxl로 방금 만든 수식은 `None`이 된다. openpyxl은 수식을 계산하지 않는다.

## 1. 수식 보존 읽기 → 정제 → 저장

```python
sheets_data, workbook = read_excel_with_formulas("sales_raw.xlsx")
df = pd.read_excel("sales_raw.xlsx", sheet_name="Sales")
df_clean = validate_and_clean_data(df)    # 중복 제거 + 결측 0 + 3σ 이상치 제거
sheet = workbook.create_sheet("Cleaned")  # 원본 수식·서식 유지한 채 결과 시트 추가
for row in dataframe_to_rows(df_clean, index=False, header=True):
    sheet.append(row)
workbook.save("sales_cleaned.xlsx")
```

## 2. 피벗 테이블 생성 후 시트로 기록

```python
pivot = create_pivot_table(
    df_clean, index="region", columns="quarter", values="amount", aggfunc="sum"
)
wb = openpyxl.Workbook()
ws = wb.active
for row in dataframe_to_rows(pivot.reset_index(), index=False, header=True):
    ws.append(row)
for cell in ws[1]:                        # 헤더 강조
    cell.font = Font(bold=True, color="FFFFFF")
    cell.fill = PatternFill("solid", fgColor="4472C4")
    cell.alignment = Alignment(horizontal="center")
wb.save("pivot_report.xlsx")
```

## 3. 차트 추가 (BarChart / LineChart)

```python
data = Reference(ws, min_col=2, min_row=1, max_col=ws.max_column, max_row=ws.max_row)
cats = Reference(ws, min_col=1, min_row=2, max_row=ws.max_row)
chart = BarChart()
chart.title = "지역별 분기 매출"
chart.add_data(data, titles_from_data=True)   # 1행을 계열 이름으로
chart.set_categories(cats)
ws.add_chart(chart, "H2")                     # 앵커 셀
trend = LineChart()
trend.add_data(data, titles_from_data=True)
ws.add_chart(trend, "H20")
wb.save("pivot_report.xlsx")
```

## 4. 조건부 서식 (임계값 강조)

```python
RED = PatternFill("solid", fgColor="FFC7CE")
GREEN = PatternFill("solid", fgColor="C6EFCE")
for row in ws.iter_rows(min_row=2, min_col=2, max_col=ws.max_column):
    for cell in row:
        if isinstance(cell.value, (int, float)):
            cell.number_format = "#,##0"
            cell.fill = RED if cell.value < 1_000_000 else GREEN
```

## 5. 다중 시트 일괄 처리

```python
frames = pd.read_excel("multi.xlsx", sheet_name=None)   # None → 전 시트 dict
with pd.ExcelWriter("multi_cleaned.xlsx", engine="openpyxl") as writer:
    summaries = []
    for name, frame in frames.items():
        cleaned = validate_and_clean_data(frame)
        cleaned.to_excel(writer, sheet_name=name[:31], index=False)  # 시트명 31자 제한
        summaries.append({"sheet": name, "rows": len(cleaned)})
    pd.DataFrame(summaries).to_excel(writer, sheet_name="Summary", index=False)
```

## 6. VLOOKUP — 두 가지 방식

```python
# (a) 파이썬에서 조인 — 정적 결과가 필요할 때 권장
merged = orders.merge(products[["sku", "price"]], on="sku", how="left")
merged["price"] = merged["price"].fillna(0)

# (b) 수식 그대로 기록 — 시트에서 원본 수정 시 자동 갱신되어야 할 때
for r in range(2, ws.max_row + 1):
    ws.cell(row=r, column=5).value = (
        f"=IFERROR(VLOOKUP(A{r},Products!$A$2:$C$500,3,FALSE),0)"
    )
```

> (b)의 셀은 저장 직후 `data_only=True`로 읽으면 `None`이다(§0 참조).

## 7. 자주 겪는 문제

| 증상 | 원인 | 해결 |
|------|------|------|
| 수식이 `None` | `data_only=True` + 미계산 | `data_only=False`로 수식 문자열 읽기 |
| 저장 후 수식이 값으로 바뀜 | `data_only=True`로 로드해 저장 | 쓰기용은 항상 `data_only=False` |
| 시트명 오류 | 31자 초과 또는 `: \ / ? * [ ]` 포함 | 이름 절단·치환 |
| 메모리 초과 | 대용량 파일 전체 로드 | `read_only=True` / `write_only=True` 모드 |
