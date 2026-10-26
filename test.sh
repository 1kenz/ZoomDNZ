#!/bin/bash
# Runs the dependency-free self-test (debug build only). Exit code 0 = all checks passed.
set -euo pipefail
cd "$(dirname "$0")"
swift build 2>&1 | grep -E "error:|Compiling|Build complete" || true
exec "$(swift build --show-bin-path)/ZoomDNZ" --self-test
