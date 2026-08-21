# Create & Verify — Backup 생성과 무결성 검증

`backup` / `verify` 서브커맨드의 상세 절차. SKILL.md의 라우팅 표에서 referenced.

## 1. backup [custom-name]

### 1.1 환경 준비

```bash
mkdir -p .claude/backups
```

### 1.2 백업명 생성

포맷: `{YYYYMMDD}_{HHMMSS}_{project-name}[_custom-name]`

```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PROJECT_NAME=$(basename "$(pwd)")
BACKUP_NAME="${TIMESTAMP}_${PROJECT_NAME}"
# custom-name이 있으면: "${TIMESTAMP}_${PROJECT_NAME}_${CUSTOM_NAME}"
```

### 1.3 백업 디렉토리 생성

```bash
BACKUP_DIR=.claude/backups/${BACKUP_NAME}
mkdir -p "${BACKUP_DIR}"
```

### 1.4 Manifest 생성

`.claude/` 디렉토리를 스캔하여 메타데이터 수집:

```bash
COMMANDS_COUNT=$(find .claude/commands -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
SKILLS_COUNT=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
AGENTS_COUNT=$(find .claude/agents -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
HOOKS_COUNT=$(find .claude/hooks -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
TOTAL_FILES=$(find .claude -type f 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh .claude 2>/dev/null | cut -f1)
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
```

`backup-manifest.json` 작성:

```json
{
  "version": "1.0.0",
  "created_at": "{ISO_TIMESTAMP}",
  "project_name": "{PROJECT_NAME}",
  "project_path": "{PWD}",
  "backup_name": "{BACKUP_NAME}",
  "custom_label": "{CUSTOM_NAME or null}",
  "git_commit": "{GIT_COMMIT}",
  "git_branch": "{GIT_BRANCH}",
  "stats": {
    "total_files": {TOTAL_FILES},
    "total_size": "{TOTAL_SIZE}",
    "commands_count": {COMMANDS_COUNT},
    "skills_count": {SKILLS_COUNT},
    "agents_count": {AGENTS_COUNT},
    "hooks_count": {HOOKS_COUNT}
  }
}
```

### 1.5 아카이브 + 체크섬

```bash
tar -czf "${BACKUP_DIR}/claude-config.tar.gz" -C "$(pwd)" .claude/
cd .claude && find . -type f -exec shasum -a 256 {} \; > "${BACKUP_DIR}/checksums.sha256" && cd ..
```

### 1.6 Quick Reference (`quick-reference.txt`)

```
Claude Code Config Backup
========================
Backup: {BACKUP_NAME}
Created: {TIMESTAMP}
Project: {PROJECT_NAME}
Git: {GIT_BRANCH}@{GIT_COMMIT}

Contents:
- Commands: {COMMANDS_COUNT}
- Skills: {SKILLS_COUNT}
- Agents: {AGENTS_COUNT}
- Hooks: {HOOKS_COUNT}
- Total Files: {TOTAL_FILES}
- Size: {TOTAL_SIZE}
```

### 1.7 결과 출력

```
✅ Backup created: {BACKUP_NAME}
   Location: .claude/backups/{BACKUP_NAME}/
   Files: {TOTAL_FILES} | Size: {TOTAL_SIZE}
```

---

## 2. verify <backup-name>

### 2.1 백업 존재 확인

```bash
BACKUP_DIR=.claude/backups/${BACKUP_NAME}
[ -d "${BACKUP_DIR}" ] || echo "Backup not found: ${BACKUP_NAME}"
```

### 2.2 아카이브 무결성

```bash
tar -tzf "${BACKUP_DIR}/claude-config.tar.gz" > /dev/null 2>&1
echo "Archive integrity: $([[ $? -eq 0 ]] && echo 'PASSED' || echo 'FAILED')"
```

### 2.3 체크섬 검증

```bash
TEMP_DIR=$(mktemp -d)
tar -xzf "${BACKUP_DIR}/claude-config.tar.gz" -C "${TEMP_DIR}"

cd "${TEMP_DIR}/.claude"
shasum -a 256 -c "${BACKUP_DIR}/checksums.sha256"
CHECKSUM_RESULT=$?
cd - > /dev/null
rm -rf "${TEMP_DIR}"

echo "Checksum validation: $([[ ${CHECKSUM_RESULT} -eq 0 ]] && echo 'PASSED' || echo 'FAILED')"
```

### 2.4 Manifest 검증

`backup-manifest.json`의 필수 필드: `version`, `created_at`, `project_name`, `backup_name`.

### 2.5 결과 리포트

```
📋 BACKUP VERIFICATION: {BACKUP_NAME}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Archive integrity: PASSED
✅ Checksum validation: PASSED (87/87 files)
✅ Manifest validation: PASSED

📊 Statistics:
   - Total files: 87
   - Size: 240 KB
   - Created: 2026-01-11 14:30:22

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VERIFICATION RESULT: ✅ VALID
```
