#!/usr/bin/env python3
"""Strict, reusable scope parser for host/URL assets."""

from __future__ import annotations

import argparse
import posixpath
import sys
from dataclasses import dataclass
from fnmatch import fnmatchcase
from pathlib import Path
from urllib.parse import unquote, urlsplit


@dataclass(frozen=True)
class Asset:
    raw: str
    host: str
    wildcard: bool
    host_glob: bool
    is_url: bool
    scheme: str = ""
    port: int | None = None
    path: str = ""


def _decode_path(value: str) -> str:
    for _ in range(3):
        decoded = unquote(value)
        if decoded == value:
            break
        value = decoded
    return value


def parse_asset(raw: str) -> Asset | None:
    raw = raw.strip().rstrip("\r")
    if not raw or raw.startswith("#"):
        return None
    if raw.startswith("/"):
        return Asset(raw=raw, host="", wildcard=False, host_glob=False,
                     is_url=False, path=raw)

    is_url = "://" in raw
    value = raw if is_url else f"scope://{raw}"
    raw_rest = raw.split("://", 1)[1] if is_url else raw
    raw_authority = raw_rest.split("/", 1)[0]
    raw_authority = raw_authority.rsplit("@", 1)[-1]
    # urlsplit interpreta colchetes como IPv6. Em arquivos de escopo eles
    # tambem aparecem como glob, por exemplo ripe[0-9].ripe.net.
    bracket_glob = "[" in raw_authority and not raw_authority.startswith("[")
    if bracket_glob:
        host = raw_authority.rstrip(".").lower()
        port = None
        if ":" in host:
            host, raw_port = host.rsplit(":", 1)
            try:
                port = int(raw_port)
            except ValueError:
                return None
        path = "/" + raw_rest.split("/", 1)[1] if "/" in raw_rest else ""
        return Asset(raw=raw, host=host, wildcard=False, host_glob=True,
                     is_url=is_url,
                     scheme=raw.split("://", 1)[0].lower() if is_url else "",
                     port=port,
                     path=path)
    try:
        parsed = urlsplit(value)
        host = (parsed.hostname or "").rstrip(".").lower()
        port = parsed.port
    except ValueError:
        return None
    if not host:
        return None

    wildcard = host.startswith("*.")
    if wildcard:
        host = host[2:]
    host_glob = not wildcard and any(char in host for char in "*?[")
    path = parsed.path if parsed.path not in ("", "/") else ""
    return Asset(
        raw=raw,
        host=host,
        wildcard=wildcard,
        host_glob=host_glob,
        is_url=is_url,
        scheme=parsed.scheme.lower() if is_url else "",
        port=port,
        path=path,
    )


def load_assets(path: str | Path) -> list[Asset]:
    file = Path(path)
    if not file.is_file():
        return []
    return [asset for line in file.read_text(errors="replace").splitlines()
            if (asset := parse_asset(line)) is not None]


def _safe_path(path: str) -> str | None:
    decoded = _decode_path(path)
    if any(segment in (".", "..") for segment in decoded.split("/")):
        return None
    return posixpath.normpath(decoded)


def matches(candidate: Asset, entry: Asset) -> bool:
    if not entry.host:
        if not entry.path or not candidate.is_url:
            return False
        candidate_path = _safe_path(candidate.path)
        entry_path = _safe_path(entry.path)
        return (candidate_path is not None and entry_path is not None
                and fnmatchcase(candidate_path, entry_path))

    if entry.wildcard:
        if candidate.host == entry.host or not candidate.host.endswith(f".{entry.host}"):
            return False
    elif entry.host_glob:
        if not fnmatchcase(candidate.host, entry.host):
            return False
    elif candidate.host != entry.host:
        return False

    if candidate.is_url and entry.is_url:
        if candidate.scheme != entry.scheme:
            return False
        default_ports = {"http": 80, "https": 443}
        candidate_port = candidate.port or default_ports.get(candidate.scheme)
        entry_port = entry.port or default_ports.get(entry.scheme)
        if candidate_port != entry_port:
            return False
    elif entry.port is not None and candidate.port != entry.port:
        return False

    if entry.path:
        if not candidate.is_url:
            return False
        candidate_path = _safe_path(candidate.path)
        entry_path = _safe_path(entry.path)
        if candidate_path is None or entry_path is None:
            return False
        if any(char in entry_path for char in "*?["):
            if not fnmatchcase(candidate_path, entry_path):
                return False
        elif candidate_path != entry_path and not candidate_path.startswith(f"{entry_path.rstrip('/')}/"):
            return False
    return True


class Guard:
    def __init__(self, scope: str | Path, out_of_scope: str | Path):
        self.scope = load_assets(scope)
        self.out_of_scope = load_assets(out_of_scope)

    def allows(self, raw_candidate: str) -> bool:
        # Primeiro campo = host/URL; colunas extras (ex. saida do httpx) sao
        # ignoradas. Linha em branco -> split vazio; nao indexar cegamente
        # senao o filter inteiro cai com IndexError sob `set -o pipefail`.
        fields = raw_candidate.split(maxsplit=1)
        candidate = parse_asset(fields[0]) if fields else None
        if candidate is None:
            return False
        return (any(matches(candidate, entry) for entry in self.scope)
                and not any(matches(candidate, entry) for entry in self.out_of_scope))


def representative(entry: Asset) -> Asset | None:
    if not entry.host:
        return None
    if not entry.wildcard:
        return parse_asset(entry.raw)
    host = f"bblab-scope-probe.{entry.host}"
    port = f":{entry.port}" if entry.port is not None else ""
    prefix = f"{entry.scheme}://" if entry.is_url else ""
    return parse_asset(f"{prefix}{host}{port}{entry.path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check")
    check.add_argument("candidate")
    check.add_argument("scope")
    check.add_argument("out_of_scope")

    stream = sub.add_parser("filter")
    stream.add_argument("scope")
    stream.add_argument("out_of_scope")

    for command in ("roots", "enum-roots", "seeds"):
        item = sub.add_parser(command)
        item.add_argument("scope")
        item.add_argument("out_of_scope", nargs="?")

    args = parser.parse_args()
    if args.command == "check":
        return 0 if Guard(args.scope, args.out_of_scope).allows(args.candidate) else 1
    if args.command == "filter":
        guard = Guard(args.scope, args.out_of_scope)
        for line in sys.stdin:
            line = line.rstrip("\n")
            if guard.allows(line):
                print(line)
        return 0

    assets = load_assets(args.scope)
    if args.out_of_scope:
        excluded = load_assets(args.out_of_scope)
        assets = [asset for asset in assets
                  if (candidate := representative(asset)) is not None
                  and not any(matches(candidate, entry) for entry in excluded)]
    if args.command == "roots":
        values = {asset.host for asset in assets if asset.host and not asset.host_glob}
    elif args.command == "enum-roots":
        values = {asset.host for asset in assets if asset.host and asset.wildcard}
    else:
        values = {asset.raw for asset in assets
                  if asset.host and not asset.wildcard and not asset.host_glob}
    print("\n".join(sorted(values)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
