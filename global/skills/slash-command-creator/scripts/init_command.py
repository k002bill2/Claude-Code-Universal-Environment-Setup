#!/usr/bin/env python3
"""
Slash Command Initializer - Creates a new slash command from template

Usage:
    init_command.py <command-name> [--scope project|personal] [--path <custom-path>]

Examples:
    init_command.py review                    # Creates .claude/commands/review.md
    init_command.py deploy --scope personal   # Creates ~/.claude/commands/deploy.md
    init_command.py test --path ./my-commands # Creates ./my-commands/test.md
"""

import sys
import os
import re
from pathlib import Path
import argparse

# 커맨드명/네임스페이스 세그먼트 허용 문자: 경로 구분자·'..'·숨김 파일·절대경로를
# 문자 집합 차원에서 차단한다 ('.', '/', '\\' 자체가 허용되지 않음).
_SAFE_SEGMENT = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]*$')


COMMAND_TEMPLATE = '''---
{frontmatter}
---

# {command_title}

{body}
'''

# frontmatter 필드 출력 순서. 고정 템플릿을 옵션 조합으로 고르면 3개 필드 = 8가지 조합을
# 템플릿 3개가 덮지 못해 '--argument-hint 만' 같은 조합에서 값이 조용히 사라진다.
# 존재하는 필드만 이 순서로 조립한다 (description 은 항상 채워지므로 언제나 포함된다).
_FRONTMATTER_ORDER = ('allowed-tools', 'argument-hint', 'description', 'model')


def build_frontmatter(
    description: str,
    allowed_tools: str = None,
    argument_hint: str = None,
    model: str = None
) -> str:
    """값이 있는 frontmatter 필드만 정해진 순서로 조립한다."""
    values = {
        'allowed-tools': allowed_tools,
        'argument-hint': argument_hint,
        'description': description,
        'model': model,
    }
    return '\n'.join(
        f'{key}: {values[key]}' for key in _FRONTMATTER_ORDER if values[key]
    )


def title_case(name: str) -> str:
    """Convert hyphenated name to Title Case."""
    return ' '.join(word.capitalize() for word in name.replace('-', ' ').split())


def get_project_commands_path() -> Path:
    """Get the project-level commands directory."""
    return Path.cwd() / '.claude' / 'commands'


def get_personal_commands_path() -> Path:
    """Get the user-level commands directory."""
    return Path.home() / '.claude' / 'commands'


def init_command(
    command_name: str,
    scope: str = 'project',
    custom_path: str = None,
    description: str = None,
    body: str = None,
    allowed_tools: str = None,
    argument_hint: str = None,
    model: str = None,
    namespace: str = None
) -> Path:
    """
    Initialize a new slash command.

    Args:
        command_name: Name of the command (without .md extension)
        scope: 'project' or 'personal'
        custom_path: Optional custom path override
        description: Command description
        body: Command body content
        allowed_tools: Comma-separated list of allowed tools
        argument_hint: Hint for command arguments
        model: Specific model to use
        namespace: Optional subdirectory namespace

    Returns:
        Path to created command file, or None if error
    """
    # 경로 탈출 방지: 파일시스템 작업(mkdir 포함) 이전에 이름을 검증한다.
    # fullmatch 필수 — match+$ 는 후행 개행('review\n')을 통과시킨다.
    if not command_name or not _SAFE_SEGMENT.fullmatch(command_name):
        print(f"Error: invalid command name '{command_name}' — "
              "use letters, digits, '-', '_' only (no path separators or dots)")
        return None
    if namespace is not None:
        segments = namespace.split('/')
        if not segments or not all(_SAFE_SEGMENT.fullmatch(s) for s in segments):
            print(f"Error: invalid namespace '{namespace}' — "
                  "each segment must use letters, digits, '-', '_' only")
            return None

    # Determine base path
    if custom_path:
        base_path = Path(custom_path).resolve()
    elif scope == 'personal':
        base_path = get_personal_commands_path()
    else:
        base_path = get_project_commands_path()

    # Add namespace subdirectory if specified
    if namespace:
        base_path = base_path / namespace

    # Create directory if it doesn't exist
    try:
        base_path.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"Error creating directory {base_path}: {e}")
        return None

    # Create command file path
    command_file = base_path / f'{command_name}.md'

    # Check if file already exists
    if command_file.exists():
        print(f"Error: Command already exists: {command_file}")
        return None

    # Prepare content
    command_title = title_case(command_name)
    description = description or f"[TODO: Brief description of /{command_name}]"
    body = body or f"[TODO: Add instructions for /{command_name}]\n\n$ARGUMENTS"

    # frontmatter 는 주어진 옵션만으로 조립한다 — 어떤 조합이든 값이 유실되지 않는다.
    content = COMMAND_TEMPLATE.format(
        frontmatter=build_frontmatter(
            description=description,
            allowed_tools=allowed_tools,
            argument_hint=argument_hint,
            model=model
        ),
        command_title=command_title,
        body=body
    )

    # Write command file
    try:
        command_file.write_text(content)
        print(f"Created: {command_file}")
        return command_file
    except Exception as e:
        print(f"Error writing command file: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Initialize a new Claude Code slash command',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s review
      Creates .claude/commands/review.md (project command)

  %(prog)s deploy --scope personal
      Creates ~/.claude/commands/deploy.md (personal command)

  %(prog)s component --namespace frontend
      Creates .claude/commands/frontend/component.md

  %(prog)s commit --allowed-tools "Bash(git add:*), Bash(git commit:*)"
      Creates command with specific tool permissions

Command naming:
  - Use lowercase with hyphens (e.g., 'review-pr', 'run-tests')
  - Avoid spaces and special characters
  - Keep names concise and descriptive
'''
    )

    parser.add_argument('command_name', help='Name of the slash command (without .md)')
    parser.add_argument('--scope', choices=['project', 'personal'], default='project',
                        help='Command scope: project (.claude/commands) or personal (~/.claude/commands)')
    parser.add_argument('--path', dest='custom_path', help='Custom path for command file')
    parser.add_argument('--namespace', help='Subdirectory namespace (e.g., frontend, backend)')
    parser.add_argument('--description', help='Command description')
    parser.add_argument('--allowed-tools', dest='allowed_tools', help='Comma-separated list of allowed tools')
    parser.add_argument('--argument-hint', dest='argument_hint', help='Hint for command arguments')
    parser.add_argument('--model', help='Specific model to use (e.g., claude-3-5-haiku-20241022)')

    args = parser.parse_args()

    result = init_command(
        command_name=args.command_name,
        scope=args.scope,
        custom_path=args.custom_path,
        description=args.description,
        allowed_tools=args.allowed_tools,
        argument_hint=args.argument_hint,
        model=args.model,
        namespace=args.namespace
    )

    if result:
        print(f"\nSlash command '/{args.command_name}' initialized successfully!")
        print("\nNext steps:")
        print("1. Edit the command file to update the description and body")
        print("2. Test the command by running it in Claude Code")
        print(f"\nUsage: /{args.command_name} [arguments]")
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
