#!/usr/bin/env python3
"""Check resolved Kconfig and optionally guard all unrelated config changes."""
import argparse
import pathlib
import re
import sys


def read_config(path):
    result = {}
    for line in pathlib.Path(path).read_text().splitlines():
        match = re.fullmatch(r"CONFIG_(\w+)=(.*)", line)
        disabled = re.fullmatch(r"# CONFIG_(\w+) is not set", line)
        if match:
            result[match[1]] = match[2]
        elif disabled:
            result[disabled[1]] = "n"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("--baseline")
    parser.add_argument("--source", help="Verify symbols exist in source Kconfig files")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    required = [s.strip() for s in (root / "config/docker-required.txt").read_text().splitlines()
                if s.strip() and not s.startswith("#")]
    config = read_config(args.config)
    errors = []
    symbols = set()
    if args.source:
        for path in pathlib.Path(args.source).rglob("Kconfig*"):
            if path.is_file():
                symbols.update(re.findall(r"^\s*(?:menu)?config\s+(\w+)",
                                         path.read_text(errors="replace"), re.M))
    for symbol in required:
        value = config.get(symbol, "n")
        allowed = {"y", "m"} if symbol == "BRIDGE_NETFILTER" else {"y"}
        print(f"CONFIG_{symbol}={value}")
        if value not in allowed:
            errors.append(f"CONFIG_{symbol}: expected {sorted(allowed)}, got {value}")
        if args.source and symbol not in symbols:
            errors.append(f"CONFIG_{symbol}: absent from source Kconfig")
    if args.baseline:
        baseline = read_config(args.baseline)
        # PAGE_COUNTER/EVENTFD are selected by MEMCG. CGROUP_WRITEBACK is
        # hidden, depends on MEMCG && the existing BLK_CGROUP, and defaults y.
        # MEMCG options appear
        # only when their parent is enabled. No driver changes are allowed.
        allowed_changes = {"MEMCG", "MEMCG_SWAP", "MEMCG_SWAP_ENABLED", "MEMCG_KMEM",
                           "PAGE_COUNTER", "EVENTFD", "CGROUP_WRITEBACK", "CFS_BANDWIDTH", "CGROUP_NET_PRIO"}
        for symbol in sorted(set(baseline) | set(config)):
            before, after = baseline.get(symbol, "n"), config.get(symbol, "n")
            if before != after:
                print(f"DIFF CONFIG_{symbol}: {before} -> {after}")
                if symbol not in allowed_changes:
                    errors.append(f"Unexpected config change: CONFIG_{symbol}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("PASS: all Docker requirements resolved; unrelated config preserved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
