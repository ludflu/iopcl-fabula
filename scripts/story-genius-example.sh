#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cabal run narrative-planning -- story-genius misbelief --timeout 120
