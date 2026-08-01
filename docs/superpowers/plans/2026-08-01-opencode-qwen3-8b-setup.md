# OpenCode Qwen3 8B Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Configure this repository for a private, local-only OpenCode workflow that contains Qwen3 8B with mechanical guardrails.

**Architecture:** A root opencode.json makes local Ollama the only provider and sets the read-only plan agent as default. Four Markdown agents in .opencode/agents use short prompts, low temperature, and limited steps. The recon agent is separated from local analysis and must ask before Bash; bin/scope-check.sh remains the guard for a target.

**Tech Stack:** OpenCode 1.18.11, Ollama OpenAI-compatible endpoint, Qwen3 8B, JSON, Markdown, Bash.

## Global Constraints

- Use only ollama/qwen3:8b and a 16,384-token model context.
- Do not edit global OpenCode configuration.
- Do not change CLAUDE.md, bin scope scripts, or vendored files.
- plan, explore, and bugbounty must deny edit, Bash, webfetch, websearch, external_directory, and task.
- recon must deny edit, webfetch, websearch, external_directory, and task; Bash must be ask.
- Target interaction requires successful scope-check followed by explicit user approval. Outward mutation requires separate explicit confirmation.

---

### Task 1: Add a guardrail test

**Files:**
- Create: tests/test_opencode_setup.sh
- Modify: Makefile

**Interfaces:**
- Produces: make test-opencode, exit status 0 only when the expected model and agent permission markers are present.

- [ ] **Step 1: Write the failing test**

Create tests/test_opencode_setup.sh:

~~~bash
#!/usr/bin/env bash
set -euo pipefail

python3 -m json.tool opencode.json >/dev/null
grep -Fq '"model": "ollama/qwen3:8b"' opencode.json
grep -Fq '"enabled_providers": ["ollama"]' opencode.json
grep -Fq '"share": "disabled"' opencode.json

for agent in plan explore bugbounty recon; do
  test -f ".opencode/agents/$agent.md"
done

for agent in plan explore bugbounty; do
  grep -Fq 'edit: deny' ".opencode/agents/$agent.md"
  grep -Fq 'bash: deny' ".opencode/agents/$agent.md"
  grep -Fq 'webfetch: deny' ".opencode/agents/$agent.md"
  grep -Fq 'websearch: deny' ".opencode/agents/$agent.md"
  grep -Fq 'task: deny' ".opencode/agents/$agent.md"
done

grep -Fq 'edit: deny' .opencode/agents/recon.md
grep -Fq 'bash: ask' .opencode/agents/recon.md
grep -Fq 'webfetch: deny' .opencode/agents/recon.md
grep -Fq 'websearch: deny' .opencode/agents/recon.md
grep -Fq 'task: deny' .opencode/agents/recon.md
grep -Fq 'bin/scope-check.sh' .opencode/agents/recon.md
~~~

Add test-opencode to Makefile .PHONY and:

~~~make
test-opencode:
	@bash tests/test_opencode_setup.sh
~~~

- [ ] **Step 2: Verify the test fails**

Run: bash tests/test_opencode_setup.sh

Expected: non-zero exit because the files do not exist.

- [ ] **Step 3: Commit the test**

~~~bash
git add tests/test_opencode_setup.sh Makefile
git commit -m "test: add OpenCode setup guardrail checks"
~~~

### Task 2: Add local provider configuration

**Files:**
- Create: opencode.json
- Test: tests/test_opencode_setup.sh

**Interfaces:**
- Produces: Qwen3 8B as the only provider/model, plan as the default agent, no conversation sharing.

- [ ] **Step 1: Create opencode.json**

~~~json
{
  "$schema": "https://opencode.ai/config.json",
  "enabled_providers": ["ollama"],
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": { "baseURL": "http://127.0.0.1:11434/v1" },
      "models": {
        "qwen3:8b": {
          "name": "Qwen3 8B (local)",
          "limit": { "context": 16384, "output": 4096 }
        }
      }
    }
  },
  "model": "ollama/qwen3:8b",
  "small_model": "ollama/qwen3:8b",
  "default_agent": "plan",
  "share": "disabled",
  "autoupdate": false,
  "lsp": true,
  "compaction": { "auto": true, "prune": true, "reserved": 4096 },
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "webfetch": "deny",
    "websearch": "deny",
    "external_directory": "deny",
    "task": "deny"
  }
}
~~~

- [ ] **Step 2: Validate the JSON**

Run: python3 -m json.tool opencode.json >/dev/null

Expected: exit status 0.

- [ ] **Step 3: Commit configuration**

~~~bash
git add opencode.json
git commit -m "feat: add local Ollama OpenCode configuration"
~~~

### Task 3: Add local analysis agents

**Files:**
- Create: .opencode/agents/plan.md
- Create: .opencode/agents/explore.md
- Create: .opencode/agents/bugbounty.md
- Test: tests/test_opencode_setup.sh

**Interfaces:**
- Produces: agents that only read local workspace content; none can edit, execute shell, browse, or dispatch tasks.

- [ ] **Step 1: Create plan.md**

~~~markdown
---
description: Produces a short, read-only next-step plan for one request.
mode: primary
model: ollama/qwen3:8b
temperature: 0.1
steps: 4
permission:
  edit: deny
  bash: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
  task: deny
---

Read CLAUDE.md before answering. Work only in this repository.
Handle one objective at a time. State assumptions and give at most five ordered next steps.
Do not claim tool use without tool output. Do not contact targets.
~~~

- [ ] **Step 2: Create explore.md**

~~~markdown
---
description: Maps local files and reports concise evidence.
mode: subagent
model: ollama/qwen3:8b
temperature: 0.1
steps: 6
permission:
  edit: deny
  bash: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
  task: deny
---

Read CLAUDE.md before answering. Inspect only local files with read, glob, grep, and list.
Answer one question with paths and short evidence. Do not edit files, run commands, contact targets, or dispatch agents.
~~~

- [ ] **Step 3: Create bugbounty.md**

~~~markdown
---
description: Applies local scope and 7-Question Gate analysis without contacting targets.
mode: subagent
model: ollama/qwen3:8b
temperature: 0.1
steps: 6
permission:
  edit: deny
  bash: deny
  webfetch: deny
  websearch: deny
  external_directory: deny
  task: deny
---

Read CLAUDE.md before answering. Work only on local files; do not contact a host or call network tools.
For a HANDLE, inspect only local scope, loot, findings, and program files. Apply the 7-Question Gate and reject excluded classes.
Do not create a report without evidence of scope, impact, and reproducibility. Return evidence, gate status, and one read-only next step.
~~~

- [ ] **Step 4: Verify the test still fails**

Run: bash tests/test_opencode_setup.sh

Expected: non-zero exit because recon.md is absent.

- [ ] **Step 5: Commit local analysis agents**

~~~bash
git add .opencode/agents/plan.md .opencode/agents/explore.md .opencode/agents/bugbounty.md
git commit -m "feat: add bounded OpenCode analysis agents"
~~~

### Task 4: Add the approval-gated recon agent

**Files:**
- Create: .opencode/agents/recon.md
- Test: tests/test_opencode_setup.sh

**Interfaces:**
- Consumes: CLAUDE.md and bin/scope-check.sh.
- Produces: at most one user-approved recon command, never an edit or automatic subtask.

- [ ] **Step 1: Create recon.md**

~~~markdown
---
description: Performs one explicitly approved, scope-checked read-only recon step.
mode: subagent
model: ollama/qwen3:8b
temperature: 0.1
steps: 3
permission:
  edit: deny
  bash: ask
  webfetch: deny
  websearch: deny
  external_directory: deny
  task: deny
---

Read CLAUDE.md before answering. Work only in this repository. Execute at most one authorized recon step.
Before any host or URL interaction, require a HANDLE and run bash bin/scope-check.sh <host-or-url> <handle> with the exact target. Stop on failure.
Ask the user to approve the specific read-only command before running it. Never POST, upload, write storage, or cause outward mutation without separate explicit confirmation. Skip excluded vulnerability classes.
Return the scope-check result, command result, and next safe step. Do not dispatch agents.
~~~

- [ ] **Step 2: Run static checks**

Run: make test-opencode

Expected: exit status 0.

- [ ] **Step 3: Commit recon guardrail**

~~~bash
git add .opencode/agents/recon.md
git commit -m "feat: add scope-guarded OpenCode recon agent"
~~~

### Task 5: Document and verify

**Files:**
- Modify: README.md
- Test: tests/test_opencode_setup.sh

**Interfaces:**
- Produces: local-only setup and safe-use instructions.

- [ ] **Step 1: Add an OpenCode local Qwen3 8B section to README**

Document these commands:

~~~bash
ollama run qwen3:8b "Reply with exactly: local model ready"
opencode agent list
make test-opencode
opencode run --agent explore "Liste os diretórios de topo e sua responsabilidade. Não modifique arquivos."
opencode run --agent recon "HANDLE=<handle>. Execute somente o scope-check de <host-ou-url>."
~~~

State that recon pauses for approval and never authorizes external action without a passing scope check and explicit approval.

- [ ] **Step 2: Run final verification**

Run: make test-opencode && git diff --check && opencode agent list

Expected: exit status 0, the four configured agents are listed, and no target is contacted.

- [ ] **Step 3: Review affected files and commit**

Run: git status --short

Expected: only planned paths changed, besides the pre-existing user-owned untracked files.

~~~bash
git add README.md Makefile tests/test_opencode_setup.sh
git commit -m "docs: describe local OpenCode Qwen3 workflow"
~~~

## Spec coverage review

- Model, context, local provider, sharing, and compaction: Task 2.
- Read-only default and no automatic task dispatch: Tasks 2 and 3.
- Scope-check plus command approval boundary: Task 4.
- Static guardrail test and documented workflow: Tasks 1 and 5.
