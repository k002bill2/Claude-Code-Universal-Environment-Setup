# Package Parsers Reference

각 패키지 매니저별 의존성 파싱 규칙과 구현 가이드입니다.

## npm/pnpm/yarn (package.json)

### 파싱 대상 필드

```json
{
  "name": "my-package",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  },
  "peerDependencies": {
    "react": "^18.0.0"
  },
  "optionalDependencies": {
    "fsevents": "^2.3.0"
  },
  "workspaces": [
    "packages/*"
  ]
}
```

### 워크스페이스 패턴

```yaml
workspace_patterns:
  npm:
    field: "workspaces"
    format: ["array", "object.packages"]

  yarn:
    field: "workspaces"
    format: ["array", "object.packages"]

  pnpm:
    file: "pnpm-workspace.yaml"
    field: "packages"
```

### 내부 의존성 감지

```yaml
internal_dependency_detection:
  # workspace: 프로토콜
  patterns:
    - "workspace:*"
    - "workspace:^"
    - "workspace:~"

  # 파일 경로 참조
  file_patterns:
    - "file:../shared"
    - "link:../core"

  # 버전이 "*"이고 워크스페이스에 존재
  wildcard_matching:
    version: "*"
    check_workspace: true
```

### 버전 해석

```yaml
version_parsing:
  semver:
    exact: "1.0.0"
    caret: "^1.0.0"     # >=1.0.0 <2.0.0
    tilde: "~1.0.0"     # >=1.0.0 <1.1.0
    range: ">=1.0.0 <2.0.0"

  special:
    latest: "latest"
    tag: "next"
    git: "git+https://..."
    url: "https://..."
```

## Python (pyproject.toml, requirements.txt)

### pyproject.toml (Poetry/PDM)

```toml
[tool.poetry]
name = "my-package"
version = "1.0.0"

[tool.poetry.dependencies]
python = "^3.10"
requests = "^2.28.0"

[tool.poetry.group.dev.dependencies]
pytest = "^7.0.0"

# 모노레포 내부 의존성
[tool.poetry.dependencies.shared-utils]
path = "../shared-utils"
develop = true
```

### requirements.txt

```yaml
parsing_rules:
  # 기본 형식
  basic: "package==1.0.0"

  # 버전 범위
  range: "package>=1.0.0,<2.0.0"

  # 환경 마커
  marker: "package; python_version>='3.10'"

  # 파일 참조
  include: "-r base.txt"

  # editable 설치
  editable: "-e ../shared-utils"
```

### uv 지원

```toml
# pyproject.toml (uv)
[project]
name = "my-package"
dependencies = [
    "requests>=2.28.0",
]

[project.optional-dependencies]
dev = ["pytest>=7.0.0"]

[tool.uv]
workspace = true
members = ["packages/*"]
```

## Rust (Cargo.toml)

### 기본 구조

```toml
[package]
name = "my-crate"
version = "1.0.0"

[dependencies]
serde = "1.0"
tokio = { version = "1.0", features = ["full"] }

[dev-dependencies]
criterion = "0.5"

[build-dependencies]
cc = "1.0"

# 워크스페이스 의존성
[dependencies.shared-utils]
path = "../shared-utils"
```

### 워크스페이스

```toml
# Cargo.toml (root)
[workspace]
members = [
    "crates/*",
    "examples/*",
]

[workspace.dependencies]
serde = "1.0"
```

## Go (go.mod)

### 기본 구조

```go
module github.com/org/project

go 1.21

require (
    github.com/gin-gonic/gin v1.9.0
    github.com/org/shared v0.0.0
)

replace github.com/org/shared => ../shared
```

### 워크스페이스 (go.work)

```go
go 1.21

use (
    ./api
    ./shared
    ./web
)
```

## Java/Kotlin

### Maven (pom.xml)

```xml
<project>
    <groupId>com.example</groupId>
    <artifactId>my-app</artifactId>
    <version>1.0.0</version>

    <dependencies>
        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-core</artifactId>
            <version>5.3.0</version>
        </dependency>
    </dependencies>

    <modules>
        <module>api</module>
        <module>web</module>
    </modules>
</project>
```

### Gradle (build.gradle.kts)

```kotlin
plugins {
    kotlin("jvm") version "1.9.0"
}

dependencies {
    implementation("org.springframework:spring-core:5.3.0")
    implementation(project(":shared"))
    testImplementation("junit:junit:4.13")
}
```

## 공통 파싱 인터페이스

```yaml
parser_interface:
  input:
    file_path: string
    file_content: string

  output:
    package_name: string
    version: string
    dependencies:
      - name: string
        version: string
        type: "production" | "development" | "peer" | "optional"
        internal: boolean
        path: string?  # 내부 의존성 경로

    workspaces:
      - pattern: string
        resolved_paths: string[]
```

## 에러 처리

```yaml
error_handling:
  invalid_format:
    action: "skip_with_warning"
    message: "Invalid {file} format at {path}"

  missing_version:
    action: "use_latest"
    message: "No version specified for {package}, using latest"

  circular_reference:
    action: "break_cycle"
    message: "Circular dependency detected: {cycle}"
```

## 캐싱

```yaml
caching:
  # 파싱 결과 캐시
  parsed_results:
    key: "{file_path}:{file_hash}"
    ttl: "1h"

  # 버전 해석 캐시
  version_resolution:
    key: "{package}:{version_spec}"
    ttl: "24h"
```
