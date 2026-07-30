---
# 출처: docs/Claude code system setup/프로젝트별 템플릿.md
name: terraform-module
description: Create Terraform modules for cloud resources
---

# Terraform Module Generator

## Instructions
1. Define module variables
2. Create main resource definitions
3. Set up outputs
4. Write documentation
5. Add examples

## Module Structure
```hcl
variable "name" {
  description = "Resource name"
  type        = string
}

resource "aws_instance" "main" {
  # Resource configuration
}

output "instance_id" {
  value = aws_instance.main.id
}
```
