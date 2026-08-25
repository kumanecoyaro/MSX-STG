"""Runs every regression test in this directory and reports a combined
pass/fail total. Each test file is self-contained (its own PASS/FAIL
lines via a local check() helper) - this just aggregates the final
"N passed, M failed" line each one prints.

Each file runs as its own subprocess (own Python interpreter, own
z80emu.py instance) with no shared mutable state between files, so
running them concurrently across a thread pool is safe: subprocess.run
blocks on the child process, releasing the GIL while it waits, so N
worker threads genuinely get N children running in parallel on
separate CPU cores. Output is still collected and printed in the same
sorted-by-filename order as the old sequential version for a stable,
diffable log - only the wall-clock execution is concurrent.
"""
import glob
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
SKIP = {"banked_helpers.py", "run_all.py", "night_visual_check.py"}

WORKERS = os.cpu_count() or 4


def run_one(path):
    return subprocess.run([sys.executable, path], capture_output=True, text=True)


paths = [
    p for p in sorted(glob.glob(os.path.join(HERE, "*.py")))
    if os.path.basename(p) not in SKIP
]

with ThreadPoolExecutor(max_workers=WORKERS) as pool:
    results = list(pool.map(run_one, paths))

total_pass = 0
total_fail = 0
failed_files = []

for path, result in zip(paths, results):
    name = os.path.basename(path)
    m = re.search(r"(\d+) passed, (\d+) failed", result.stdout)
    if not m:
        print(f"=== {name}: NO SUMMARY LINE (crashed?) ===")
        print(result.stdout[-2000:])
        print(result.stderr[-2000:])
        failed_files.append(name)
        continue
    p, f = int(m.group(1)), int(m.group(2))
    total_pass += p
    total_fail += f
    status = "OK" if f == 0 else "FAIL"
    print(f"{status:4} {name}: {p} passed, {f} failed")
    if f:
        failed_files.append(name)

print()
print(f"TOTAL: {total_pass} passed, {total_fail} failed")
if failed_files:
    print("FILES WITH FAILURES:", failed_files)
    sys.exit(1)
