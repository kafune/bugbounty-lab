# OpenCode local-first agent design for Qwen3 8B

## Goal

Configure OpenCode to work as a constrained, entirely local coding and bug-bounty assistant using Qwen3 8B. The design compensates for a model that is less reliable than Claude Code at following long instructions and selecting tools.

## Model strategy

- Use `qwen3:8b` as the only default model for every agent.
- Keep prompts short, imperative, and phase-specific. Each invocation has one objective and a fixed response format.
- Do not rely on the model to remember authorization or scope between turns. Enforce those limits with agent permissions and repository scripts.
- Use a modest context length (16K tokens) to preserve interactive speed and headroom in VRAM.

## Agent roles

| Agent | Mode | Responsibility | Writes files? |
| --- | --- | --- | --- |
| `plan` | primary | Turn one user request into a short, explicit next-step plan | No |
| `explore` | subagent | Map codebases and report concrete evidence with paths | No |
| `bugbounty` | subagent | Analyze local program artifacts and apply the 7-Question Gate | No |
| `recon` | subagent | Propose or execute one authorized, scope-checked recon step | Only via explicit confirmation |

## Safety model

- All OpenCode configuration and agent definitions live in `.opencode/` in this repository; the setup does not modify global OpenCode files.
- Reading source files, search, LSP, and non-mutating local inspection remain available. `.env` is protected and requires explicit approval to read.
- No agent may edit files, commit, push, access external directories, or invoke a network-capable command without explicit approval.
- `plan`, `explore`, and `bugbounty` have no network-capable tools. `bugbounty` is local-only: it may inspect `CLAUDE.md`, scope files, loot, findings, and scripts, but cannot contact a target.
- `recon` is the only agent that may request network activity. It must first run `bash bin/scope-check.sh <host-or-url> <handle>`, present the passing result, and stop before outward mutation. The user must explicitly approve each recon step.
- The `bugbounty` and `recon` prompts repeat the repository's scope guard, confirmation rule for outward mutation, and excluded vulnerability classes in compact form.

## Configuration layout

- Add `.opencode/opencode.json` with Ollama model registration, a `qwen3:8b` default, private sharing, LSP, compaction, and deny-by-default permissions.
- Add prompts in `.opencode/agents/` so each role has a focused system prompt and independent permissions.
- Leave the repository's existing `CLAUDE.md` unchanged; it remains the operational policy that the OpenCode prompts reinforce.

## Verification

1. Verify that `qwen3:8b` responds locally through Ollama.
2. Validate the OpenCode configuration is loadable with `opencode agent list`.
3. Confirm `plan`, `explore`, `bugbounty`, and `recon` appear with the intended mode and permission restrictions.
4. Smoke-test a read-only exploration prompt and confirm that no file changes occur.
5. Confirm that a recon request cannot proceed to a host interaction without the scope-check and an explicit user approval.

## Non-goals

- No cloud provider, API key, telemetry-dependent feature, remote model fallback, or automatic subagent dispatch.
- No automatic committing, pushing, scanning, or mutation of third-party systems.
