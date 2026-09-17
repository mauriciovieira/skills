#!/usr/bin/env bash
# `control drive grilling` runs every *.sh under a test path, so this wrapper is
# what gets the Python test picked up by the repository's own verification.
set -euo pipefail
exec python3 "$(dirname "$0")/test_grill_stop.py"
