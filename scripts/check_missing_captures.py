#!/usr/bin/env python3
"""Check for missing UDP request/response captures in a trace file.

Matches UDP exchanges by the tuple (check, endpoints) and reports when one
direction is present without the opposite.

Usage:
  python3 scripts/check_missing_captures.py /path/to/3-trace.txt
"""
import sys
import re
import argparse
from collections import defaultdict

DEFAULT_PATH = "/home/emizac/thesis/Analysis/traces/40762/2/2-trace.txt"


def parse_udp_line(line):
    """Return (src, dst, check) for UDP lines, else None."""
    if 'UDP:' not in line:
        return None
    m = re.search(r'UDP:\s*([0-9\.]+):(\d+)\s*-->\s*([0-9\.]+):(\d+)', line)
    if not m:
        return None
    src = f"{m.group(1)}:{m.group(2)}"
    dst = f"{m.group(3)}:{m.group(4)}"
    mc = re.search(r'check=(\d+)', line)
    check = mc.group(1) if mc else None
    return src, dst, check


def analyze(path):
    # key: (check, frozenset({src,dst})) -> {src: [records], dst: [records]}
    records = defaultdict(lambda: defaultdict(list))
    recnum_pat = re.compile(r'^\[\s*(\d+)\]')
    dir_pat = re.compile(r'^\[\s*\d+\]:(d\d{2})')
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            for lineno, line in enumerate(f, 1):
                rn_m = recnum_pat.match(line)
                if not rn_m:
                    continue
                rec = int(rn_m.group(1))
                dir_m = dir_pat.match(line)
                direction = dir_m.group(1) if dir_m else None
                parsed = parse_udp_line(line)
                if not parsed:
                    continue
                src, dst, check = parsed
                key = (check, frozenset((src, dst)))
                records[key][src].append((rec, direction, line.rstrip('\n')))
    except FileNotFoundError:
        print(f"File not found: {path}", file=sys.stderr)
        return None
    return records


def report(records):
    if records is None:
        return 2
    missing = []
    ambiguous = []
    # detect likely server port by frequency across endpoints
    port_count = defaultdict(int)
    for (check, endpoints), sides in records.items():
        for ep in endpoints:
            port = ep.split(':', 1)[1]
            port_count[port] += sum(len(v) for v in sides.values())
    server_port = None
    if port_count:
        server_port = max(port_count.items(), key=lambda kv: kv[1])[0]
    for key, sides in records.items():
        check, endpoints = key
        eps = list(endpoints)
        if len(eps) != 2:
            continue
        a, b = eps[0], eps[1]
        a_count = len(sides.get(a, []))
        b_count = len(sides.get(b, []))
        if a_count > 0 and b_count == 0:
            missing.append((check, a, b, sides[a]))
        elif b_count > 0 and a_count == 0:
            missing.append((check, b, a, sides[b]))
        elif a_count != b_count:
            ambiguous.append((check, a, b, a_count, b_count))

    if not missing and not ambiguous:
        print("No unmatched UDP exchanges (by check+endpoints).")
        return 0

    if missing:
        print("Unmatched UDP exchanges (one direction only):")
        for check, src, dst, recs in missing:
            # classify: if dst port == server_port then these are requests (missing responses)
            src_port = src.split(':', 1)[1]
            dst_port = dst.split(':', 1)[1]
            if server_port and dst_port == server_port:
                kind = 'request(s) present, response(s) missing'
            elif server_port and src_port == server_port:
                kind = 'response(s) present, request(s) missing'
            else:
                kind = 'one direction present (unknown which)'
            print(f"check={check or 'N/A'}  seen: {src} -> {dst}  count={len(recs)}  [{kind}]")
            for rec, direction, line in recs[:5]:
                print(f"  [{rec}] {direction or '-'} {line}")
            if len(recs) > 5:
                print(f"  ... and {len(recs)-5} more\n")

    if ambiguous:
        print("\nExchanges with differing counts per direction:")
        for check, a, b, ca, cb in ambiguous:
            print(f"check={check or 'N/A'}  {a} <-> {b}  counts: {ca}/{cb}")

    return 1


def main(argv):
    p = argparse.ArgumentParser(description='Check UDP request/response presence by check+endpoints.')
    p.add_argument('path', nargs='?', default=DEFAULT_PATH)
    args = p.parse_args(argv[1:])
    records = analyze(args.path)
    return report(records)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
