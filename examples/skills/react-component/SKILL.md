---
# 출처: docs/Claude code system setup/프로젝트별 템플릿.md
name: react-component
description: Generate React components with TypeScript, tests, and stories. Use when creating new UI components.
---

# React Component Generator

## Instructions
1. Create component file with TypeScript interface
2. Generate corresponding test file
3. Create Storybook story if applicable
4. Add proper accessibility attributes
5. Implement responsive design

## Component Template
```tsx
interface ComponentProps {
  // Define props
}

export const Component: React.FC<ComponentProps> = ({ ...props }) => {
  // Implementation
}
```
