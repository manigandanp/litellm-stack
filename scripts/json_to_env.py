#!/usr/bin/env python3
"""Convert a JSON file to .env (KEY=VALUE) format.

Nested objects and arrays are flattened using a configurable separator
(default: `__`). Values are serialized so that strings stay as-is, while
numbers, booleans, null, lists, and objects become JSON-encoded strings.

Usage:
    python scripts/json_to_env.py input.json
    python scripts/json_to_env.py input.json -o .env
    python scripts/json_to_env.py input.json -s _ --upper
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def flatten(obj: Any, prefix: str = "", sep: str = "__") -> list[tuple[str, str]]:
    """Flatten a nested JSON structure into (KEY, VALUE) string pairs."""
    pairs: list[tuple[str, str]] = []

    if isinstance(obj, dict):
        for key, value in obj.items():
            child_prefix = f"{prefix}{sep}{key}" if prefix else str(key)
            pairs.extend(flatten(value, child_prefix, sep))
    elif isinstance(obj, list):
        for index, value in enumerate(obj):
            child_prefix = f"{prefix}{sep}{index}" if prefix else str(index)
            pairs.extend(flatten(value, child_prefix, sep))
    else:
        # Leaf value -> serialize. Strings stay raw; everything else is JSON-encoded.
        if obj is None:
            value_str = ""
        elif isinstance(obj, str):
            value_str = obj
        elif isinstance(obj, bool):
            value_str = "true" if obj else "false"
        else:
            value_str = json.dumps(obj)
        pairs.append((prefix, value_str))

    return pairs


def to_env_line(key: str, value: str, upper: bool = False) -> str:
    """Build a single .env line, optionally upper-casing the key."""
    env_key = key.upper() if upper else key
    # Quote values that contain whitespace, #, or = to keep them valid .env.
    if value and any(ch in value for ch in (" ", "\t", "#", "=", "\n")):
        return f'{env_key}="{value}"'
    return f"{env_key}={value}"


def convert(json_path: Path, sep: str, upper: bool) -> str:
    """Read a JSON file and return its .env representation as a string."""
    with json_path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)

    pairs = flatten(data, sep=sep)
    lines = [to_env_line(key, value, upper) for key, value in pairs]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert a JSON file to .env (KEY=VALUE) format."
    )
    parser.add_argument("input", type=Path, help="Path to the input JSON file.")
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="Output .env file path. Defaults to stdout.",
    )
    parser.add_argument(
        "-s", "--separator", default="__",
        help="Separator used when flattening nested keys (default: '__').",
    )
    parser.add_argument(
        "--upper", action="store_true",
        help="Upper-case all environment variable names.",
    )
    args = parser.parse_args(argv)

    if not args.input.is_file():
        print(f"error: input file not found: {args.input}", file=sys.stderr)
        return 1

    try:
        env_text = convert(args.input, args.separator, args.upper)
    except json.JSONDecodeError as exc:
        print(f"error: invalid JSON in {args.input}: {exc}", file=sys.stderr)
        return 1

    if args.output:
        args.output.write_text(env_text, encoding="utf-8")
        print(f"wrote {len(env_text.splitlines())} variables to {args.output}")
    else:
        sys.stdout.write(env_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
