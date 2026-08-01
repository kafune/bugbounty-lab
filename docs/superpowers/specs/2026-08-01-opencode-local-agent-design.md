# OpenCode local-first agent design

## Goal

Configure OpenCode to work as a capable, entirely local coding and bug-bounty assistant on the available RTX 3060 (12 GB VRAM), 16 GB system RAM, and Ollama installation.

## Model strategy

- Pull and use `qwen3:14b` as the primary model for `build`, `plan`, and `explore`.
- Retain `qwen2.5-coder:7b` as an explicitly selectable fast model for small, focused edits.
- Do not install 24B+ or 30B+ models as default agents: they exceed available VRAM and would rely heavily on slow CPU/RAM offload.
- Use a modest context length (16K tokens) to preserve interactive speed and headroom in VRAM.

## Agent roles

| Agent | Mode | Responsibility | Writes files? |
| --- | --- | --- | --- |
| `build` | primary | Implement, test, and explain changes | Yes, with approval gates |
| `plan` | primary | Investigate requirements and propose an implementation plan | No |
| `explore` | subagent | Map codebases and report dependencies, workflows, and key logic | No |
| `review` | subagent | Review diffs for defects, regressions, and maintainability | No |
| `bugbounty` | subagent | Analyze the current lab within its scope guard and report evidence-based findings | No by default |

## Safety model

- Reading source files, search, LSP, and non-mutating local inspection remain available.
- `.env` files remain protected and need an explicit approval to read.
- Edits by `build` require approval; no other agent may edit project files.
- All commands initially require approval, except safe read-only inspection commands such as `git status`, `git diff`, `rg`, `find`, and test/listing commands.
- Commits, pushes, remote network calls, and external directories always require approval.
- The `bugbounty` agent must comply with the repository's `CLAUDE.md`: verify scope before contacting a target, request confirmation for outward mutation, and skip excluded vulnerability classes.

## Configuration layout

- Update `~/.config/opencode/opencode.json` with local model registration, default agent, private sharing, LSP, compaction, global permissions, and agent overrides.
- Add agent prompts in `~/.config/opencode/agents/` so each role has a focused system prompt and independent permissions.
- Leave the repository's existing `CLAUDE.md` unchanged; OpenCode reads it as project guidance.

## Verification

1. Pull `qwen3:14b` with Ollama and verify it responds locally.
2. Validate the OpenCode configuration is loadable with `opencode agent list`.
3. Confirm the five intended agents and their modes/permission restrictions appear in that output.
4. Smoke-test one read-only exploration prompt and ensure that no file changes occur.

## Non-goals

- No cloud provider, API key, telemetry-dependent feature, or remote model fallback.
- No automatic committing, pushing, scanning, or mutation of third-party systems.
