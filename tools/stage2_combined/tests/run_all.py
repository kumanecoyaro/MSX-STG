"""Runs every regression test in this directory and reports a combined
pass/fail total. Each test file is self-contained (its own PASS/FAIL
lines via a local check() helper) - this just aggregates the final
"N passed, M failed" line each one prints.
"""
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKIP = {"banked_helpers.py", "run_all.py", "night_visual_check.py"}

total_pass = 0
total_fail = 0
failed_files = []

for path in sorted(glob.glob(os.path.join(HERE, "*.py"))):
    name = os.path.basename(path)
    if name in SKIP:
        continue
    result = subprocess.run([sys.executable, path], capture_output=True, text=True)
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
