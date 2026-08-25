#!/bin/bash
set -euo pipefail

# Only relevant for Claude Code on the web / remote sessions - a local
# checkout should use whatever Python the user already has.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# tools/stage2_combined/tests/run_all.py spends nearly all its time inside
# tools/z80emu.py's pure-Python Z80 instruction interpreter. PyPy's JIT
# speeds that up by roughly 10x over CPython (measured: a single heavy test
# file went from 57s to 5.4s; the full 629-test regression suite went from
# 19m53s on stock CPython to 34.7s with PyPy + this repo's other test
# speedups combined). run_all.py already prefers pypy3 automatically via
# shutil.which("pypy3") when present, falling back to whatever launched it
# otherwise - this hook just makes sure pypy3 IS present.
if ! command -v pypy3 >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq pypy3
fi
