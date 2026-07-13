#!/usr/bin/env python3
"""
scope_writer.py — writer de escopo COMPARTILHADO.

Fonte única do formato targets/<handle>/ consumido por recon.sh/monitor.sh.
Usado por h1sync.py (programas H1) e discover.py (materialização do catálogo).
Não duplicar essa lógica em outro lugar.

Layout escrito em targets/<handle>/:
  scope.txt          -> assets in-scope (1/linha) — o recon consome isto
  out-of-scope.txt   -> assets não-submissíveis
  scope.raw.json     -> (opcional) resposta bruta da fonte, p/ fidelidade
  .discovered        -> (opcional) marcador de proveniência da discovery
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = ROOT / "targets"


def write_scope(handle, in_scope, out_scope, raw=None, root=None, marker=None):
    """Materializa targets/<handle>/. Devolve o Path do diretório.

    raw    — se dado, grava scope.raw.json (h1sync passa os structured_scopes).
    marker — se dado (str), grava .discovered (discovery marca proveniência).
    """
    base = Path(root) if root else TARGETS
    d = base / handle
    d.mkdir(parents=True, exist_ok=True)
    # Lista vazia -> arquivo de 0 byte (NÃO "\n"). Um out-of-scope.txt só com
    # newline passa no teste `[ -s ]` de _scope.sh e gera regex vazia, fazendo
    # `grep -vE ""` excluir TODO host. Zero byte mantém o scope-guard correto.
    ins = sorted(set(a for a in in_scope if a and a.strip()))
    outs = sorted(set(a for a in out_scope if a and a.strip()))
    (d / "scope.txt").write_text(("\n".join(ins) + "\n") if ins else "")
    (d / "out-of-scope.txt").write_text(("\n".join(outs) + "\n") if outs else "")
    if raw is not None:
        (d / "scope.raw.json").write_text(json.dumps(raw, indent=2))
    if marker is not None:
        (d / ".discovered").write_text(marker + "\n")
    return d
