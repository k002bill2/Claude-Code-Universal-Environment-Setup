# Restore · List · Diff — Backup 사용 시점 작업

`restore` / `list` / `diff` 서브커맨드의 상세 절차. SKILL.md의 라우팅 표에서 referenced.

## 1. list — 백업 목록

```bash
ls -lt .claude/backups/ 2>/dev/null || echo "No backups found"
```

각 백업의 `backup-manifest.json`을 읽어 테이블로 표시:

```
📦 Available Backups
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

| Backup Name                          | Date       | Files | Size  |
|--------------------------------------|------------|-------|-------|
| 20260111_143022_aos                  | 2026-01-11 | 87    | 240KB |
| 20260110_091545_aos_pre-update       | 2026-01-10 | 85    | 235KB |

Total: 2 backups
```

---

## 2. restore <backup-name> [--dry-run] [--only <path>]

### 2.1 사전 검증

먼저 `verify` 워크플로우([references/create-and-verify.md](create-and-verify.md) §2) 실행.

### 2.2 안전 백업 생성

```bash
if [ -d ".claude" ]; then
  SAFETY_BACKUP=".claude.bak.$(date +%Y%m%d_%H%M%S)"
  cp -r .claude "${SAFETY_BACKUP}"
  echo "Safety backup created: ${SAFETY_BACKUP}"
fi
```

### 2.3 Dry-run 모드

`--dry-run` 플래그가 있으면 실제 복원 없이 변경 사항만 표시:

```
🔍 DRY-RUN: Would restore from {BACKUP_NAME}

Changes:
- Replace: 87 files
- Preserve: settings.local.json

No changes made.
```

### 2.4 선택적 복원 (`--only`)

```bash
# 예: --only commands
tar -xzf "${BACKUP_DIR}/claude-config.tar.gz" -C "$(pwd)" .claude/commands/
```

### 2.5 전체 복원 (settings.local.json 보존)

```bash
if [ -f ".claude/settings.local.json" ]; then
  cp .claude/settings.local.json /tmp/settings.local.json.bak
fi

tar -xzf "${BACKUP_DIR}/claude-config.tar.gz" -C "$(pwd)"

if [ -f "/tmp/settings.local.json.bak" ]; then
  cp /tmp/settings.local.json.bak .claude/settings.local.json
  rm /tmp/settings.local.json.bak
fi
```

### 2.6 결과

```
✅ Restore completed from: {BACKUP_NAME}
   Files restored: 87
   Safety backup: {SAFETY_BACKUP}
   Preserved: settings.local.json
```

---

## 3. diff <backup1> [backup2]

### 3.1 비교 대상 결정

- 인자 1개: `backup1` vs 현재 `.claude/`
- 인자 2개: `backup1` vs `backup2`

### 3.2 파일 목록 추출

```bash
tar -tzf "${BACKUP_DIR}/claude-config.tar.gz" | sort > /tmp/backup_files.txt
find .claude -type f | sed 's|^\./||' | sort > /tmp/current_files.txt
```

### 3.3 차이점 계산

```bash
# 추가된 파일 (현재에만)
comm -13 /tmp/backup_files.txt /tmp/current_files.txt > /tmp/added.txt

# 삭제된 파일 (백업에만)
comm -23 /tmp/backup_files.txt /tmp/current_files.txt > /tmp/removed.txt

# 공통 파일 (수정 여부 확인 필요)
comm -12 /tmp/backup_files.txt /tmp/current_files.txt > /tmp/common.txt
```

### 3.4 결과 출력

```
📊 DIFF: {BACKUP_NAME} ⟷ Current
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 ADDED (3 files):
   + commands/run-eval.md
   + skills/agent-improvement/SKILL.md
   + evals/tasks/ui-component-creation.yaml

📁 REMOVED (1 file):
   - skills/deprecated-skill/SKILL.md

📁 MODIFIED (5 files):
   ~ hooks.json
   ~ commands/verify-app.md
   ~ agents/aos-orchestrator.md

📊 Summary:
   Added: 3 | Removed: 1 | Modified: 5 | Unchanged: 78
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
