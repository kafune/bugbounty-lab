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
