#!/usr/bin/env python3

from itertools import product
import sys

if len(sys.argv) != 3:
    print("Usage: python permutations.py <script_path> <repo_path>")
    sys.exit(1)

SCRIPTPATH = sys.argv[1]
REPOPATH = sys.argv[2]

lists = [['iptables', 'ebpf'], ['udp', 'http'], ['none', 'ingress', 'egress', 'both'], ['no', 'with', 'withacceleration'], ['true', 'false']]
permutations = list(product(*lists))

passed = []

suffix = "2>&1 | tee -a /var/log/k8test-ntas.log"

for perm in permutations:
    if perm[1] == 'udp' and perm[3] != 'no':
        pass
    
    elif perm[1] == 'udp' and perm[4] != 'false':
        pass

    elif perm[1] == 'http' and perm[3] == 'no':
        if perm[4] == 'true':
            pass

    else:
        passed.append(' '.join(perm))

for perm in passed:
    print(f"{SCRIPTPATH} {perm} {REPOPATH} {suffix}")
