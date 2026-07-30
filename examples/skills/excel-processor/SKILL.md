---
# 출처: docs/Claude code system setup/Agent Skills 예시 모음.md
name: excel-processor
description: Process Excel files with formulas, pivot tables, and charts. Use for spreadsheet analysis, data transformation, or report generation.
---

# Excel Processing Skill

## Capabilities
- Read/write Excel files preserving formulas
- Create pivot tables and charts
- Data validation and cleaning
- Multi-sheet operations
- Conditional formatting
- VLOOKUP/HLOOKUP operations

## Dependencies
```python
import pandas as pd
import openpyxl
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.styles import PatternFill, Font, Alignment
from openpyxl.utils.dataframe import dataframe_to_rows
import numpy as np
```

## Core Functions

### 1. Read Excel with Formulas
```python
def read_excel_with_formulas(filepath):
    workbook = openpyxl.load_workbook(filepath, data_only=False)
    sheets_data = {}
    for sheet_name in workbook.sheetnames:
        sheet = workbook[sheet_name]
        data = []
        for row in sheet.iter_rows():
            row_data = []
            for cell in row:
                if cell.value:
                    row_data.append({
                        'value': cell.value,
                        'formula': cell.formula if hasattr(cell, 'formula') else None,
                        'format': cell.number_format
                    })
                else:
                    row_data.append(None)
            data.append(row_data)
        sheets_data[sheet_name] = data
    return sheets_data, workbook
```

### 2. Create Pivot Table
```python
def create_pivot_table(df, index, columns, values, aggfunc='sum'):
    pivot = pd.pivot_table(
        df, index=index, columns=columns,
        values=values, aggfunc=aggfunc, fill_value=0
    )
    return pivot
```

### 3. Data Validation
```python
def validate_and_clean_data(df):
    df = df.drop_duplicates()
    numeric_columns = df.select_dtypes(include=[np.number]).columns
    df[numeric_columns] = df[numeric_columns].fillna(0)
    for col in numeric_columns:
        mean = df[col].mean()
        std = df[col].std()
        df = df[(df[col] > mean - 3*std) & (df[col] < mean + 3*std)]
    return df
```

## Usage Examples
See references/excel-examples.md for complete usage patterns.
