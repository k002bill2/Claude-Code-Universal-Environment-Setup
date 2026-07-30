---
# 출처: docs/Claude code system setup/Agent Skills 예시 모음.md
name: docs-generator
description: Generate comprehensive documentation including API docs, README files, and technical guides. Use for documentation tasks.
---

# Documentation Generator Skill

## Capabilities
- API documentation generation
- README file creation
- Code documentation extraction
- Markdown formatting
- Diagram generation (Mermaid)
- Changelog management

## Documentation Types

### 1. API Documentation
See references/api-template.md

### 2. README Template
See references/readme-template.md

### 3. Architecture Diagram (Mermaid)
```mermaid
graph TB
    Client[Client App]
    API[API Gateway]
    Auth[Auth Service]
    User[User Service]
    DB[(Database)]
    Cache[(Redis Cache)]

    Client --> API
    API --> Auth
    API --> User
    Auth --> DB
    User --> DB
    User --> Cache
```

## Best Practices
1. Keep documentation close to code
2. Use consistent formatting
3. Include examples for everything
4. Update docs with code changes
5. Version documentation
6. Use diagrams for complex concepts
